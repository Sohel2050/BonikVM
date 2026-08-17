import '../api/api_service.dart';

/// Simple test class to verify VPN API functionality
/// This can be called from your main app to test the fixes
class VpnApiTester {
  static Future<void> testVpnApi() async {
    try {
      // Initialize API service
      ApiService.instance.initialize();

      // Test 1: Get servers list

      final servers = await ApiService.instance.getServers();

      if (servers.isNotEmpty) {}

      // Test 2: Get best server

      final bestServer = await ApiService.instance.getBestServer();
      if (bestServer != null) {
      } else {}

      // Test 3: Get server config (if we have servers)
      if (servers.isNotEmpty) {
        final serverId = int.tryParse(servers.first.id) ?? 0;
        final config = await ApiService.instance.getServerConfig(serverId);
        if (config.isNotEmpty) {
        } else {}
      }
    } catch (e) {}
  }
}
