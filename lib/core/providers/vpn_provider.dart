import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import 'package:permission_handler/permission_handler.dart';
import '../api/api_service.dart';

enum VpnState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
  denied,
}

class VpnNotifier extends StateNotifier<VpnState> {
  VpnNotifier() : super(VpnState.disconnected);

  OpenVPN? _openVPNEngine;
  WireGuard? _wireGuardEngine;
  VpnServer? _currentServer;
  VpnStatus? _vpnStatus;
  WireGuardStatus? _wgVpnStatus;
  String? _vpnStage;

  VpnServer? get currentServer => _currentServer;
  VpnStatus? get vpnStatus => _vpnStatus;
  WireGuardStatus? get wgVpnStatus => _wgVpnStatus;
  String? get vpnStage => _vpnStage;

  bool get isConnected =>
      _vpnStage?.toLowerCase() == VPNStage.connected.name.toLowerCase() ||
      _vpnStage?.toLowerCase() == WGStage.connected.name.toLowerCase();

  Future<void> initialize() async {
    // Request notification permission as required by VPN plugins
    try {
      final notificationStatus = await Permission.notification.status;
      if (!notificationStatus.isGranted) {
        await Permission.notification.request();
      }
    } catch (e) {}

    // Initialize OpenVPN engine
    _openVPNEngine = OpenVPN(
      onVpnStageChanged: _onVpnStageChanged,
      onVpnStatusChanged: _onVpnStatusChanged,
    );

    _openVPNEngine!.initialize(
      lastStatus: _onVpnStatusChanged,
      lastStage: (stage) => _onVpnStageChanged(stage, stage.name),
    );

    // Initialize WireGuard engine
    _wireGuardEngine = WireGuard(
      onVpnStageChanged: _onWireGuardStageChanged,
      onVpnStatusChanged: _onWireGuardStatusChanged,
    );

    _wireGuardEngine!.initialize(
      lastStatus: _onWireGuardStatusChanged,
      lastStage: (stage) => _onWireGuardStageChanged(stage, stage.name),
    );
  }

  void _onVpnStatusChanged(VpnStatus? status) {
    _vpnStatus = status;
  }

  void _onWireGuardStatusChanged(WireGuardStatus? status) {
    _wgVpnStatus = status;
  }

  void _onVpnStageChanged(VPNStage stage, String rawStage) {
    _vpnStage = rawStage;

    switch (stage) {
      case VPNStage.connecting:
      case VPNStage.prepare:
        state = VpnState.connecting;
        break;
      case VPNStage.connected:
        state = VpnState.connected;
        break;
      case VPNStage.disconnected:
        state = VpnState.disconnected;
        break;
      case VPNStage.error:
        state = VpnState.error;
        break;
      case VPNStage.denied:
        state = VpnState.denied;
        break;
      default:
        break;
    }
  }

  void _onWireGuardStageChanged(WGStage stage, String rawStage) {
    _vpnStage = rawStage;

    switch (stage) {
      case WGStage.preparing:
      case WGStage.connecting:
        state = VpnState.connecting;
        break;
      case WGStage.connected:
        state = VpnState.connected;
        break;
      case WGStage.disconnected:
        state = VpnState.disconnected;
        break;
      case WGStage.error:
        state = VpnState.error;
        break;
      case WGStage.denied:
        state = VpnState.denied;
        break;
      default:
        break;
    }
  }

  Future<void> connect(VpnServer server) async {
    if (_openVPNEngine == null || _wireGuardEngine == null) {
      await initialize();
    }

    _currentServer = server;
    state = VpnState.connecting;

    // DEBUG: Log protocol detection
    print('🔍 VPN Protocol Detection:');
    print('   Server: ${server.name}');
    print('   vpnProtocolType: "${server.vpnProtocolType}"');
    print('   supportsWireGuard: ${server.supportsWireGuard}');
    print('   supportsOpenVPN: ${server.supportsOpenVPN}');

    // Check protocol type and route to appropriate connection method
    if (server.vpnProtocolType == 'wireguard') {
      print('✅ Detected WireGuard - using WireGuard engine');
      await _connectWireGuard(server);
    } else {
      print('✅ Detected OpenVPN - using OpenVPN engine');
      await _connectOpenVPN(server);
    }
  }

  /// Connect using WireGuard protocol
  Future<void> _connectWireGuard(VpnServer server) async {
    try {
      final serverId = int.tryParse(server.id) ?? 0;
      final config = await ApiService.instance.getServerConfig(serverId);

      if (config.isEmpty) {
        throw Exception('WireGuard configuration not available');
      }

      // Connect using WireGuard engine
      print('Connecting to WireGuard server: ${server.name}');
      await _wireGuardEngine!.connect(config, server.name);
    } catch (e) {
      print('WireGuard connection error: $e');
      state = VpnState.error;
      rethrow;
    }
  }

  /// Connect using OpenVPN protocol
  Future<void> _connectOpenVPN(VpnServer server) async {
    String config;
    try {
      // Get config directly using server ID
      final serverId = int.tryParse(server.id) ?? 0;

      config = await ApiService.instance.getServerConfig(serverId);

      if (config.isNotEmpty) {
        // Config has essential VPN directives
      }
    } catch (e) {
      config = '';
    }

    // Fallback to basic config if API config is empty or invalid
    if (config.isEmpty || !_isValidConfig(config)) {
      config = _createBasicConfig(server);
    }

    String? filteredConfig;
    try {
      filteredConfig = await OpenVPN.filteredConfig(config);
    } catch (e) {
      filteredConfig = config;
    }

    try {
      await _openVPNEngine!.connect(
        filteredConfig ?? config,
        server.name,
        certIsRequired: false, // More reliable for app bundle
        username: server.vpnUsername.isNotEmpty ? server.vpnUsername : null,
        password: server.vpnPassword.isNotEmpty ? server.vpnPassword : null,
        bypassPackages: [], // Empty for better compatibility
      );
    } catch (e) {
      state = VpnState.error;
      rethrow;
    }
  }

  /// Validate if config has essential VPN directives
  bool _isValidConfig(String config) {
    return config.contains('client') &&
        config.contains('remote') &&
        config.contains('dev tun') &&
        config.length > 100; // Minimum reasonable config size
  }

  String _createBasicConfig(VpnServer server) {
    // Create a basic OpenVPN config for the server
    return '''client
dev tun
proto ${server.protocol.toLowerCase()}
remote ${server.ip} ${server.port}
resolv-retry infinite
nobind
persist-key
persist-tun
verb 3
pull
redirect-gateway def1
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4
remote-cert-tls server
comp-lzo
''';
  }

  void disconnect() {
    // Disconnect from active protocol
    if (_currentServer?.vpnProtocolType == 'wireguard' &&
        _wireGuardEngine != null) {
      _wireGuardEngine!.disconnect();
    } else if (_openVPNEngine != null) {
      _openVPNEngine!.disconnect();
    }
    state = VpnState.disconnecting;
  }

  Future<bool> quickConnect() async {
    try {
      final servers = await ApiService.instance.getServers();
      if (servers.isEmpty) return false;

      final freeServers = servers
          .where((s) => !s.premium && s.isActive)
          .toList();
      if (freeServers.isEmpty) return false;

      await connect(freeServers.first);
      return true;
    } catch (e) {
      return false;
    }
  }
}

final vpnProvider = StateNotifierProvider<VpnNotifier, VpnState>((ref) {
  return VpnNotifier();
});

final currentServerProvider = StateProvider<VpnServer?>((ref) {
  return ref.watch(vpnProvider.notifier).currentServer;
});
