import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';

class VpnStatePersistenceService {
  static const String _vpnConnectionKey = 'vpn_connection_state';
  static const String _vpnServerKey = 'vpn_selected_server';
  static const String _vpnStartTimeKey = 'vpn_start_time';
  static const String _premiumTimeLeftKey = 'premium_time_left';
  static const String _connectionDurationKey = 'connection_duration';

  static final VpnStatePersistenceService _instance =
      VpnStatePersistenceService._internal();
  factory VpnStatePersistenceService() => _instance;
  VpnStatePersistenceService._internal();

  Future<void> saveVpnState({
    required bool isConnected,
    required VpnServer? server,
    required DateTime? startTime,
    required Duration? premiumTimeLeft,
    required Duration? connectionDuration,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.setBool(_vpnConnectionKey, isConnected);

    if (server != null) {
      await prefs.setString(_vpnServerKey, jsonEncode(server.toJson()));
    }

    if (startTime != null) {
      await prefs.setInt(_vpnStartTimeKey, startTime.millisecondsSinceEpoch);
    }

    if (premiumTimeLeft != null) {
      await prefs.setInt(_premiumTimeLeftKey, premiumTimeLeft.inMilliseconds);
    }

    if (connectionDuration != null) {
      await prefs.setInt(
        _connectionDurationKey,
        connectionDuration.inMilliseconds,
      );
    }

    print(
      'VPN state saved: connected=$isConnected, server=${server?.name}, timeLeft=${premiumTimeLeft?.inMinutes}m',
    );
  }

  Future<Map<String, dynamic>?> loadVpnState() async {
    final prefs = await SharedPreferences.getInstance();

    final isConnected = prefs.getBool(_vpnConnectionKey) ?? false;
    final serverJson = prefs.getString(_vpnServerKey);
    final startTimeMillis = prefs.getInt(_vpnStartTimeKey);
    final premiumTimeLeftMillis = prefs.getInt(_premiumTimeLeftKey);
    final connectionDurationMillis = prefs.getInt(_connectionDurationKey);

    VpnServer? server;
    DateTime? startTime;
    Duration? premiumTimeLeft;
    Duration? connectionDuration;

    if (serverJson != null) {
      try {
        server = VpnServer.fromJson(jsonDecode(serverJson));
      } catch (e) {
        print('Error decoding server data: $e');
      }
    }

    if (startTimeMillis != null) {
      startTime = DateTime.fromMillisecondsSinceEpoch(startTimeMillis);
    }

    if (premiumTimeLeftMillis != null) {
      premiumTimeLeft = Duration(milliseconds: premiumTimeLeftMillis);
    }

    if (connectionDurationMillis != null) {
      connectionDuration = Duration(milliseconds: connectionDurationMillis);
    }

    print(
      'VPN state loaded: connected=$isConnected, server=${server?.name}, timeLeft=${premiumTimeLeft?.inMinutes}m',
    );

    return {
      'isConnected': isConnected,
      'server': server,
      'startTime': startTime,
      'premiumTimeLeft': premiumTimeLeft,
      'connectionDuration': connectionDuration,
    };
  }

  Future<void> clearVpnState() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_vpnConnectionKey);
    await prefs.remove(_vpnServerKey);
    await prefs.remove(_vpnStartTimeKey);
    await prefs.remove(_premiumTimeLeftKey);
    await prefs.remove(_connectionDurationKey);

    print('VPN state cleared');
  }

  Future<bool> checkBackgroundVpnStatus() async {
    try {
      // Note: openvpn_flutter doesn't provide a direct way to check current VPN state
      // For now, we'll rely on the persisted state and assume VPN may still be running
      // in background. This is safer for preventing premium bypass.
      print('Background VPN status check: relying on persisted state');
      return false; // Return false to use persisted state logic
    } catch (e) {
      print('Error checking background VPN status: $e');
      return false;
    }
  }

  Future<void> syncVpnStateWithBackground() async {
    try {
      final backgroundActive = await checkBackgroundVpnStatus();
      final savedState = await loadVpnState();

      if (backgroundActive && !(savedState?['isConnected'] ?? false)) {
        print(
          'Background VPN active but app state shows disconnected - syncing state',
        );
        // VPN is running in background but app doesn't know about it
        // This shouldn't happen with proper state management, but handle it
        await saveVpnState(
          isConnected: true,
          server: savedState?['server'],
          startTime: savedState?['startTime'] ?? DateTime.now(),
          premiumTimeLeft: savedState?['premiumTimeLeft'],
          connectionDuration: savedState?['connectionDuration'],
        );
      } else if (!backgroundActive && (savedState?['isConnected'] ?? false)) {
        print(
          'App state shows connected but background VPN not active - clearing state',
        );
        await clearVpnState();
      }
    } catch (e) {
      print('Error syncing VPN state: $e');
    }
  }

  Future<Duration> getTotalConnectionTime() async {
    final savedState = await loadVpnState();
    return savedState?['connectionDuration'] ?? Duration.zero;
  }

  Future<void> updateConnectionDuration(Duration duration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_connectionDurationKey, duration.inMilliseconds);
  }
}
