import '../api/api_service.dart';
import '../services/vpn_service.dart';

class ConnectionDebugger {
  static Future<void> debugConnection() async {
    try {
      // Step 1: Test API connection

      final servers = await ApiService.instance.getServers();

      if (servers.isEmpty) {
        return;
      }

      // Step 2: Test server config fetch
      final testServer = servers.first;
      final serverId = int.tryParse(testServer.id) ?? 0;
      await ApiService.instance.getServerConfig(serverId);

      // Step 3: Test VPN service initialization

      await VpnService.instance.initialize();

      // Step 4: Simulate connection attempt
    } catch (e, stackTrace) {}
  }
}
