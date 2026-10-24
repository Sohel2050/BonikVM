import 'package:flutter/foundation.dart';
import '../api/api_service.dart';

class PlayStoreDebugHelper {
  static void logBuildInfo() {
    final isPlayStore = !kDebugMode && kReleaseMode;
  }

  static Future<void> testApiConnection() async {
    try {
      // Test server list
      final servers = await ApiService.instance.getServers();

      if (servers.isNotEmpty) {
        // Test server config
        final serverId = int.tryParse(servers.first.id) ?? 0;
        final config = await ApiService.instance.getServerConfig(serverId);

        // Check certificates
        final hasCerts = config.contains('<ca>') && config.contains('<cert>');

        if (!hasCerts) {}
      }
    } catch (e) {}
  }

  static void logCertificateInfo() {}

  static void logNetworkHeaders() {
    final isPlayStore = !kDebugMode && kReleaseMode;
  }
}
