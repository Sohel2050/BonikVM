import 'dart:async';
import '../api/api_service.dart';

/// Base interface for VPN tunnel managers
abstract class TunnelManager {
  /// Current connection state stream
  Stream<VpnState> get stateStream;

  /// Current VPN state
  VpnState get currentState;

  /// Current connected server
  VpnServer? get currentServer;

  /// Initialize the tunnel manager
  Future<void> initialize();

  /// Connect to a VPN server
  Future<bool> connectToServer(VpnServer server);

  /// Disconnect from current VPN
  Future<bool> disconnect();

  /// Check if VPN permission is granted (Android)
  Future<bool> isVpnPermissionGranted();

  /// Request VPN permission (Android)
  Future<bool> requestVpnPermission();

  /// Dispose resources
  void dispose();
}

/// VPN connection states
enum VpnState {
  disconnected,
  connecting,
  connected,
  disconnecting,
  error,
  denied,
  authenticating,
  waitConnection,
  reconnecting,
}

