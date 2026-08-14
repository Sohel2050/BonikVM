import 'dart:async';
import 'dart:io';

import 'vpn_state.dart';

/// Windows WireGuard backend, driving the official `wireguard.exe` /
/// `wg.exe` CLI tools (bundled in windows/vpn_bin/) as a Windows tunnel
/// service — the same mechanism the official WireGuard for Windows GUI
/// uses under the hood (`wireguard.exe /installtunnelservice <conf>`).
class WindowsWireGuardService {
  static final WindowsWireGuardService _instance =
      WindowsWireGuardService._internal();
  factory WindowsWireGuardService() => _instance;
  WindowsWireGuardService._internal();

  static WindowsWireGuardService get instance => _instance;

  VpnState _state = VpnState.disconnected;
  final _stateController = StreamController<VpnState>.broadcast();
  VpnState get state => _state;
  Stream<VpnState> get stateStream => _stateController.stream;

  Timer? _handshakePoll;
  String? _activeTunnelName;
  File? _configFile;

  String get _binDir {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}vpn_bin';
  }

  String get _wireguardExe =>
      '$_binDir${Platform.pathSeparator}wireguard.exe';
  String get _wgExe => '$_binDir${Platform.pathSeparator}wg.exe';

  bool get isAvailable =>
      File(_wireguardExe).existsSync() && File(_wgExe).existsSync();

  /// WireGuard on Windows names the tunnel/service after the config
  /// filename, and is picky about allowed characters.
  String _sanitizeTunnelName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
    final trimmed = cleaned.isEmpty ? 'VPN MASTER' : cleaned;
    return trimmed.length > 32 ? trimmed.substring(0, 32) : trimmed;
  }

  Future<bool> connect({required String config, required String name}) async {
    if (!isAvailable) {
      _setState(VpnState.error);
      throw Exception(
        'wireguard.exe/wg.exe not found in $_binDir. '
        'See windows/vpn_bin/README.md.',
      );
    }

    await disconnect();
    _setState(VpnState.connecting);

    final tunnelName = _sanitizeTunnelName(name);
    _activeTunnelName = tunnelName;
    _configFile = File('$_binDir${Platform.pathSeparator}$tunnelName.conf');
    await _configFile!.writeAsString(config);

    try {
      // Installing a tunnel service creates a network adapter — requires
      // admin rights, hence the elevated launch (one UAC prompt).
      await _runElevated(_wireguardExe, [
        '/installtunnelservice',
        _configFile!.path,
      ]);
    } catch (e) {
      _setState(VpnState.error);
      await _cleanup();
      return false;
    }

    // The tunnel service takes a moment to come up; poll `wg show` for a
    // real handshake to confirm the tunnel is actually passing traffic,
    // not just that the service exists.
    _handshakePoll?.cancel();
    var attempts = 0;
    const maxAttempts = 30; // ~30s at 1s interval
    _handshakePoll = Timer.periodic(const Duration(seconds: 1), (
      timer,
    ) async {
      attempts++;
      if (_activeTunnelName != tunnelName) {
        timer.cancel();
        return;
      }
      final connected = await _hasHandshake(tunnelName);
      if (connected) {
        timer.cancel();
        _setState(VpnState.connected);
      } else if (attempts >= maxAttempts) {
        timer.cancel();
        _setState(VpnState.error);
      }
    });

    return true;
  }

  Future<bool> _hasHandshake(String tunnelName) async {
    try {
      final result = await Process.run(_wgExe, [
        'show',
        tunnelName,
        'latest-handshakes',
      ]);
      if (result.exitCode != 0) return false;
      final output = result.stdout.toString().trim();
      if (output.isEmpty) return false;
      // Output: "<peer-pubkey>\t<unix-epoch-seconds>"
      final parts = output.split(RegExp(r'\s+'));
      if (parts.length < 2) return false;
      final epoch = int.tryParse(parts.last) ?? 0;
      return epoch > 0;
    } catch (_) {
      return false;
    }
  }

  Future<void> disconnect() async {
    _handshakePoll?.cancel();
    _handshakePoll = null;

    final tunnelName = _activeTunnelName;
    if (tunnelName == null) {
      _setState(VpnState.disconnected);
      return;
    }

    _setState(VpnState.disconnecting);
    _activeTunnelName = null;

    try {
      await _runElevated(_wireguardExe, [
        '/uninstalltunnelservice',
        tunnelName,
      ]);
    } catch (_) {}

    await _cleanup();
    _setState(VpnState.disconnected);
  }

  Future<void> _cleanup() async {
    try {
      if (_configFile != null && await _configFile!.exists()) {
        await _configFile!.delete();
      }
    } catch (_) {}
    _configFile = null;
  }

  Future<void> _runElevated(String exePath, List<String> args) async {
    String psQuote(String s) => "'${s.replaceAll("'", "''")}'";
    final argList = args.map(psQuote).join(',');
    final command =
        'Start-Process -FilePath ${psQuote(exePath)} '
        '-ArgumentList @($argList) -Verb RunAs -WindowStyle Hidden -Wait';
    final result = await Process.run('powershell.exe', [
      '-NoProfile',
      '-NonInteractive',
      '-Command',
      command,
    ]);
    if (result.exitCode != 0) {
      throw Exception('Elevated WireGuard command failed: ${result.stderr}');
    }
  }

  void _setState(VpnState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void dispose() {
    _handshakePoll?.cancel();
    _stateController.close();
  }
}
