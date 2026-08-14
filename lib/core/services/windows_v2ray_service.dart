import 'dart:async';
import 'dart:io';

import 'vpn_state.dart';

/// Windows V2Ray/Xray backend.
///
/// Unlike OpenVPN/WireGuard, this does not create a TUN adapter — it runs
/// `xray.exe` as a local SOCKS5 proxy (the JSON configs built by
/// `V2Ray.buildVlessConfig` etc. already declare a `socks` inbound on
/// 127.0.0.1:10808 — see axevpn_flutter's v2ray_engine.dart, which is pure
/// Dart with no native dependency, so those same builders are reused here
/// unchanged) and points the Windows system proxy at it. This is the same
/// approach mainstream V2Ray Windows clients (v2rayN, Qv2ray) use, and
/// crucially needs no elevation/UAC prompt.
///
/// Trade-off: only proxy-aware apps (browsers, most Windows apps) are
/// routed — raw sockets and apps that ignore the system proxy are not
/// covered, unlike a true TUN-based tunnel.
class WindowsV2RayService {
  static final WindowsV2RayService _instance =
      WindowsV2RayService._internal();
  factory WindowsV2RayService() => _instance;
  WindowsV2RayService._internal();

  static WindowsV2RayService get instance => _instance;

  static const int _socksPort = 10808;

  Process? _process;
  File? _configFile;
  VpnState _state = VpnState.disconnected;
  final _stateController = StreamController<VpnState>.broadcast();

  VpnState get state => _state;
  Stream<VpnState> get stateStream => _stateController.stream;

  String get _binDir {
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    return '$exeDir${Platform.pathSeparator}vpn_bin';
  }

  String get _xrayExe => '$_binDir${Platform.pathSeparator}xray.exe';

  bool get isAvailable => File(_xrayExe).existsSync();

  Future<bool> connect({required String configJson, required String name}) async {
    if (!isAvailable) {
      _setState(VpnState.error);
      throw Exception('xray.exe not found in $_binDir. See windows/vpn_bin/README.md.');
    }

    await disconnect();
    _setState(VpnState.connecting);

    final tempDir = await Directory.systemTemp.createTemp('axevpn_xray_');
    _configFile = File('${tempDir.path}${Platform.pathSeparator}xray.json');
    await _configFile!.writeAsString(configJson);

    try {
      _process = await Process.start(_xrayExe, [
        '-config',
        _configFile!.path,
      ], workingDirectory: _binDir);
    } catch (e) {
      _setState(VpnState.error);
      await _cleanup();
      return false;
    }

    unawaited(
      _process!.exitCode.then((code) async {
        if (_state == VpnState.connected || _state == VpnState.connecting) {
          _setState(VpnState.error);
        }
        await _clearSystemProxy();
      }),
    );

    // Confirm the local SOCKS listener actually came up before declaring
    // success, then route system traffic through it.
    var connected = false;
    for (var attempt = 0; attempt < 20; attempt++) {
      try {
        final socket = await Socket.connect(
          '127.0.0.1',
          _socksPort,
          timeout: const Duration(milliseconds: 500),
        );
        socket.destroy();
        connected = true;
        break;
      } catch (_) {
        await Future.delayed(const Duration(milliseconds: 250));
      }
    }

    if (!connected) {
      _setState(VpnState.error);
      _process?.kill();
      _process = null;
      await _cleanup();
      return false;
    }

    await _setSystemProxy('127.0.0.1:$_socksPort');
    _setState(VpnState.connected);
    return true;
  }

  Future<void> disconnect() async {
    if (_process == null) {
      _setState(VpnState.disconnected);
      return;
    }
    _setState(VpnState.disconnecting);
    try {
      _process?.kill(ProcessSignal.sigterm);
    } catch (_) {}
    _process = null;
    await _clearSystemProxy();
    await _cleanup();
    _setState(VpnState.disconnected);
  }

  Future<void> _cleanup() async {
    try {
      final dir = _configFile?.parent;
      if (dir != null && await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
    _configFile = null;
  }

  /// System proxy is per-user (HKCU), so this doesn't need elevation.
  Future<void> _setSystemProxy(String proxyAddress) async {
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '1', '/f']);
    await Process.run('reg', ['add', key, '/v', 'ProxyServer', '/t', 'REG_SZ', '/d', proxyAddress, '/f']);
    // SOCKS proxies shouldn't be applied to loopback/local addresses.
    await Process.run('reg', [
      'add', key, '/v', 'ProxyOverride', '/t', 'REG_SZ', '/d', '<local>', '/f',
    ]);
  }

  Future<void> _clearSystemProxy() async {
    const key = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings';
    await Process.run('reg', ['add', key, '/v', 'ProxyEnable', '/t', 'REG_DWORD', '/d', '0', '/f']);
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
