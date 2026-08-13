import 'package:flutter/foundation.dart';
import 'api_service.dart';

/// Model to hold ad configuration for a server
class AdConfig {
  final int serverId;
  final String serverName;
  final List<AdReward> ads;

  AdConfig({
    required this.serverId,
    required this.serverName,
    required this.ads,
  });

  factory AdConfig.fromJson(Map<String, dynamic> json) {
    final adsData = json['ads'] as List<dynamic>? ?? [];
    return AdConfig(
      serverId: json['server_id'] ?? 0,
      serverName: json['server_name'] ?? 'Unknown',
      ads: adsData
          .map((ad) => AdReward.fromJson(ad as Map<String, dynamic>))
          .toList(),
    );
  }
}

/// Model for individual ad reward
class AdReward {
  final int id;
  final int duration; // in minutes
  final int durationSeconds; // in seconds

  AdReward({
    required this.id,
    required this.duration,
    required this.durationSeconds,
  });

  factory AdReward.fromJson(Map<String, dynamic> json) {
    return AdReward(
      id: json['id'] ?? 0,
      duration: json['duration'] ?? 5,
      durationSeconds: json['duration_seconds'] ?? 300,
    );
  }
}

/// Service to manage ad configurations
class AdConfigService {
  /// Cache for ad configurations (serverId -> AdConfig)
  static final Map<int, AdConfig> _cache = {};

  /// Fetch ad configuration for a specific server
  static Future<AdConfig?> getAdConfig(dynamic serverId) async {
    try {
      // Convert to int if string
      final serverIdInt = serverId is String
          ? int.tryParse(serverId) ?? 0
          : serverId as int;

      // Check cache first
      if (_cache.containsKey(serverIdInt)) {
        return _cache[serverIdInt];
      }

      // Fetch from API
      final response = await ApiService.get(
        '/v1/servers/ads?id=$serverIdInt',
        includeAuth: false,
      );

      if (response['success'] == true && response['data'] != null) {
        final adConfig = AdConfig.fromJson(response['data']);
        // Cache the result
        _cache[serverIdInt] = adConfig;
        debugPrint('✅ Ad config fetched for server $serverIdInt');
        return adConfig;
      } else {
        debugPrint('❌ Failed to fetch ad config: ${response['message']}');
        return null;
      }
    } catch (e) {
      debugPrint('❌ Error fetching ad config: $e');
      final serverIdInt = serverId is String
          ? int.tryParse(serverId) ?? 0
          : serverId as int;
      return _getDefaultAdConfig(serverIdInt);
    }
  }

  /// Get default ad configuration (fallback values)
  static AdConfig _getDefaultAdConfig(int serverId) {
    return AdConfig(
      serverId: serverId,
      serverName: 'Default Server',
      ads: [
        AdReward(id: 1, duration: 5, durationSeconds: 300),
        AdReward(id: 2, duration: 10, durationSeconds: 600),
        AdReward(id: 3, duration: 20, durationSeconds: 1200),
      ],
    );
  }

  /// Clear cache
  static void clearCache() {
    _cache.clear();
  }

  /// Clear specific server cache
  static void clearServerCache(dynamic serverId) {
    final serverIdInt = serverId is String
        ? int.tryParse(serverId) ?? 0
        : serverId as int;
    _cache.remove(serverIdInt);
  }

  /// Get ad reward duration in seconds for a specific ad
  static int getAdDurationSeconds(dynamic serverId, int adIndex) {
    final serverIdInt = serverId is String
        ? int.tryParse(serverId) ?? 0
        : serverId as int;
    if (_cache.containsKey(serverIdInt)) {
      final config = _cache[serverIdInt];
      if (adIndex < config!.ads.length) {
        return config.ads[adIndex].durationSeconds;
      }
    }
    // Return default values
    const defaults = [300, 600, 1200]; // 5, 10, 20 minutes in seconds
    return adIndex < defaults.length ? defaults[adIndex] : 300;
  }
}
