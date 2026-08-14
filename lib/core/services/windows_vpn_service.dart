import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'vpn_state.dart';

/// Windows VPN backend.
///
/// Android/iOS route through the `axevpn_flutter` native plugin, which has
/// no Windows implementation. On Windows we drive OpenVPN directly as a
/// subprocess via its management interface — this only supports servers
/// whose `vpnProtocolType` is `openvpn` (the default protocol); WireGuard,
/// V2Ray and OpenConnect servers are not yet supported on this platform.
///
/// Requires `openvpn.exe` (2.5+) and `wintun.dll` to be present next to the
/// built executable in a `vpn_bin/` folder — see windows/vpn_bin/README.md.
class WindowsVpnService {
  static final WindowsVpnService _instance = WindowsVpnService._internal();
  factory WindowsVpnService() => _instance;
  WindowsVpnService._internal();

  static WindowsVpnService get instance => _instance;

  Process? _process;
  Socket? _management;
  StreamSubscription<String>? _mgmtSub;
  Directory? _sessionTempDir;

  VpnState _state = VpnState.disconnected;
  final _stateController = StreamController<VpnState>.broadcast();

  VpnState get state => _state;
  Stream<VpnState> get stateStream => _stateController.stream;

  /// Directory the built exe lives in — vpn_bin/ is installed as a sibling
  /// by windows/CMakeLists.txt.
  String get _binDir {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}vpn_bin';
  }

  String get _openvpnExePath =>
      '$_binDir${Platform.pathSeparator}openvpn.exe';

  /// Whether openvpn.exe has been dropped into vpn_bin/ (see README there).
  bool get isAvailable => File(_openvpnExePath).existsSync();

  Future<bool> connect({
    required String config,
    required String name,
    String? username,
    String? password,
  }) async {
    if (!isAvailable) {
      _setState(VpnState.error);
      throw Exception(
        'openvpn.exe not found in $_binDir. '
        'See windows/vpn_bin/README.md for setup instructions.',
      );
    }

    // Ensure any previous session is fully torn down first — both our own
    // (via the management socket) and any orphaned instance left running
    // from a prior app crash/force-close, since a detached elevated
    // process has no parent to signal it when the app dies uncleanly.
    await disconnect();
    await _killOrphanedInstances();

    _setState(VpnState.connecting);

    final tempDir = await Directory.systemTemp.createTemp('axevpn_win_');
    _sessionTempDir = tempDir;

    final configFile = File('${tempDir.path}${Platform.pathSeparator}client.ovpn');
    await configFile.writeAsString(config);

    File? authFile;
    if ((username ?? '').isNotEmpty && (password ?? '').isNotEmpty) {
      authFile = File('${tempDir.path}${Platform.pathSeparator}auth.txt');
      await authFile.writeAsString('$username\n$password\n');
    }

    // Pick a management port that's unlikely to collide across quick
    // reconnects.
    final mgmtPort = 17800 + (DateTime.now().millisecondsSinceEpoch % 1000);

    final args = <String>[
      '--config', configFile.path,
      '--management', '127.0.0.1', '$mgmtPort',
      '--management-hold',
      '--management-query-passwords',
      '--windows-driver', 'wintun',
      '--auth-nocache',
      '--script-security', '1',
      if (authFile != null) ...['--auth-user-pass', authFile.path],
    ];

    // Creating the Wintun TUN adapter requires administrator rights.
    // Rather than require the whole app to run elevated (which hit an
    // mt.exe/manifest-embedding bug in this toolchain), only openvpn.exe
    // itself is launched elevated — triggering one UAC prompt per connect.
    // Its exit is not directly observable this way, so state is driven
    // entirely by the management-interface socket below.
    try {
      _process = await _startElevated(_openvpnExePath, args, _binDir);
    } catch (e) {
      _setState(VpnState.error);
      await _cleanupTempDir();
      return false;
    }

    // The management port isn't listening the instant the process spawns —
    // retry briefly until OpenVPN binds it.
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        _management = await Socket.connect(
          '127.0.0.1',
          mgmtPort,
          timeout: const Duration(milliseconds: 500),
        );
        break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    if (_management == null) {
      _setState(VpnState.error);
      _process?.kill();
      _process = null;
      await _cleanupTempDir();
      return false;
    }

    _mgmtSub = _management!
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleManagementLine, onError: (_) {});

    // Ask for state notifications, then let the connection proceed past
    // --management-hold.
    _mgmtWrite('state on');
    _mgmtWrite('hold release');

    return true;
  }

  /// Kills any already-running instance of *our specific* openvpn.exe copy
  /// (matched by full executable path, elevated to see/kill other elevated
  /// processes) left over from a previous app crash or force-close.
  ///
  /// Deliberately does NOT match by process name alone — other VPN
  /// products (observed: BlazeVPN) also run their own legitimately
  /// installed openvpn.exe from a different path, and a name-only
  /// `taskkill /IM openvpn.exe` would kill an unrelated app's active
  /// connection too.
  Future<void> _killOrphanedInstances() async {
    try {
      final ourPath = _openvpnExePath.replaceAll('/', r'\');
      String psQuote(String s) => "'${s.replaceAll("'", "''")}'";

      // Enumerating processes/paths doesn't need elevation — only checking
      // here avoids a second UAC prompt on every connect when there's
      // nothing orphaned to clean up (the common case).
      final probe = await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "(Get-CimInstance Win32_Process -Filter \"Name='openvpn.exe'\" | "
            "Where-Object { \$_.ExecutablePath -eq ${psQuote(ourPath)} } | "
            'Measure-Object).Count',
      ]);
      final orphanCount = int.tryParse(probe.stdout.toString().trim()) ?? 0;
      if (orphanCount == 0) return;

      final scriptFile = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}'
        'axevpn_cleanup_${DateTime.now().millisecondsSinceEpoch}.ps1',
      );
      await scriptFile.writeAsString(
        "Get-CimInstance Win32_Process -Filter \"Name='openvpn.exe'\" | "
        "Where-Object { \$_.ExecutablePath -eq ${psQuote(ourPath)} } | "
        "ForEach-Object { Stop-Process -Id \$_.ProcessId -Force -ErrorAction SilentlyContinue }",
      );

      final command =
          'Start-Process powershell -Verb RunAs -WindowStyle Hidden -Wait '
          '-ArgumentList @(\'-NoProfile\',\'-NonInteractive\',\'-ExecutionPolicy\',\'Bypass\',\'-File\',${psQuote(scriptFile.path)})';
      await Process.run('powershell.exe', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        command,
      ]);

      try {
        await scriptFile.delete();
      } catch (_) {}
    } catch (_) {
      // Best-effort cleanup — a failure here shouldn't block a fresh connect.
    }
  }

  /// Launches [exePath] elevated (UAC prompt) via PowerShell's Start-Process
  /// -Verb RunAs, since creating the Wintun TUN adapter requires admin
  /// rights. The returned Process is the (unelevated) PowerShell wrapper,
  /// not openvpn.exe itself — its exit does not indicate openvpn exited;
  /// use the management-interface socket for that.
  Future<Process> _startElevated(
    String exePath,
    List<String> args,
    String workingDirectory,
  ) async {
    String psQuote(String s) => "'${s.replaceAll("'", "''")}'";
    final argList = args.map(psQuote).join(',');
    final command =
        'Start-Process -FilePath ${psQuote(exePath)} '
        '-ArgumentList @($argList) '
        '-WorkingDirectory ${psQuote(workingDirectory)} '
        '-Verb RunAs -WindowStyle Hidden';
    return Process.start('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ]);
  }

  void _handleManagementLine(String line) {
    if (line.isEmpty) return;

    if (line.startsWith('>STATE:')) {
      final parts = line.substring('>STATE:'.length).split(',');
      if (parts.length < 2) return;
      switch (parts[1]) {
        case 'CONNECTING':
        case 'WAIT':
        case 'GET_CONFIG':
        case 'RESOLVE':
        case 'TCP_CONNECT':
        case 'ASSIGN_IP':
        case 'ADD_ROUTES':
          _setState(VpnState.connecting);
          break;
        case 'AUTH':
        case 'AUTH_PENDING':
          _setState(VpnState.authenticating);
          break;
        case 'CONNECTED':
          _setState(VpnState.connected);
          break;
        case 'RECONNECTING':
          _setState(VpnState.reconnecting);
          break;
        case 'EXITING':
          _setState(VpnState.disconnected);
          break;
      }
      return;
    }

    if (line.startsWith('>PASSWORD:Verification Failed') ||
        line.startsWith('>FATAL:')) {
      _setState(VpnState.error);
      return;
    }

    if (line.startsWith('>HOLD:')) {
      // Should already be released by connect(), but handle a race safely.
      _mgmtWrite('hold release');
    }
  }

  void _mgmtWrite(String command) {
    try {
      _management?.write('$command\n');
    } catch (_) {}
  }

  Future<void> disconnect() async {
    if (_process == null && _management == null) {
      _setState(VpnState.disconnected);
      return;
    }

    _setState(VpnState.disconnecting);

    _mgmtWrite('signal SIGTERM');
    await Future.delayed(const Duration(milliseconds: 500));

    try {
      _process?.kill(ProcessSignal.sigterm);
    } catch (_) {}

    await _mgmtSub?.cancel();
    _mgmtSub = null;

    try {
      await _management?.close();
    } catch (_) {}
    _management = null;
    _process = null;

    await _cleanupTempDir();
    _setState(VpnState.disconnected);
  }

  Future<void> _cleanupTempDir() async {
    final dir = _sessionTempDir;
    _sessionTempDir = null;
    if (dir == null) return;
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  void _setState(VpnState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _stateController.close();
  }
}
