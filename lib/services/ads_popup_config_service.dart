import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../core/config/app_config.dart';

/// Configuration for ads popup from admin panel
class AdsPopupConfig {
  final bool enableBuySubscriptionPrompt;
  final String buySubscriptionText;
  final int adRewardDuration; // Minutes per ad for free time extension
  final bool enablePremiumUnlock;
  final int premiumUnlockDurationMinutes;
  final String premiumUnlockText;

  AdsPopupConfig({
    required this.enableBuySubscriptionPrompt,
    required this.buySubscriptionText,
    required this.adRewardDuration,
    required this.enablePremiumUnlock,
    required this.premiumUnlockDurationMinutes,
    required this.premiumUnlockText,
  });

  factory AdsPopupConfig.fromJson(Map<String, dynamic> json) {
    return AdsPopupConfig(
      enableBuySubscriptionPrompt:
          json['enable_buy_subscription_prompt'] ?? true,
      buySubscriptionText:
          json['buy_subscription_text'] ??
          'Watch ads to extend your free time or subscribe for unlimited access',
      adRewardDuration: json['ad_reward_duration'] ?? 5,
      enablePremiumUnlock: json['enable_premium_unlock_ads'] ?? true,
      premiumUnlockDurationMinutes:
          json['premium_unlock_duration_minutes'] ?? 5,
      premiumUnlockText:
          json['premium_unlock_text'] ??
          'Watch an ad to unlock this premium server',
    );
  }

  factory AdsPopupConfig.defaultConfig() {
    return AdsPopupConfig(
      enableBuySubscriptionPrompt: true,
      buySubscriptionText:
          'Watch ads to extend your free time or subscribe for unlimited access',
      adRewardDuration: 5,
      enablePremiumUnlock: true,
      premiumUnlockDurationMinutes: 5,
      premiumUnlockText: 'Watch an ad to unlock this premium server',
    );
  }
}

/// Service to manage ads popup configuration
class AdsPopupConfigService {
  static final AdsPopupConfigService _instance =
      AdsPopupConfigService._internal();
  factory AdsPopupConfigService() => _instance;
  AdsPopupConfigService._internal();

  AdsPopupConfig? _cachedConfig;
  DateTime? _lastFetchTime;

  /// Cache duration (2 minutes — short so admin changes apply quickly)
  static const Duration _cacheDuration = Duration(minutes: 2);

  /// Fetch ads popup configuration from backend
  Future<AdsPopupConfig> getAdsPopupConfig({bool forceRefresh = false}) async {
    try {
      // Check cache
      if (!forceRefresh && _cachedConfig != null && _lastFetchTime != null) {
        if (DateTime.now().difference(_lastFetchTime!).inMinutes <
            _cacheDuration.inMinutes) {
          debugPrint('✅ Using cached ads popup config');
          return _cachedConfig!;
        }
      }

      // Fetch from API using Dio directly
      try {
        final dio = Dio(
          BaseOptions(
            baseUrl: AppConfig.apiBaseUrl,
            connectTimeout: const Duration(seconds: 10),
            receiveTimeout: const Duration(seconds: 10),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-API-Token': AppConfig.apiKey,
            },
          ),
        );

        final response = await dio.get('/api/v1/app-config');

        if (response.statusCode == 200) {
          final data = response.data;

          // Handle different response formats
          Map<String, dynamic>? adsPopupData;

          if (data is Map<String, dynamic>) {
            // Direct format
            adsPopupData = data['ads_popup'] as Map<String, dynamic>?;

            // Or try nested format
            adsPopupData ??=
                data['data']?['ads_popup'] as Map<String, dynamic>?;
          }

          if (adsPopupData != null) {
            _cachedConfig = AdsPopupConfig.fromJson(adsPopupData);
            _lastFetchTime = DateTime.now();
            debugPrint('✅ Ads popup config fetched successfully');
            return _cachedConfig!;
          }
        }
      } catch (e) {
        debugPrint('⚠️ Error fetching from API: $e');
      }

      debugPrint('❌ Failed to fetch ads popup config, using default');
      return AdsPopupConfig.defaultConfig();
    } catch (e) {
      debugPrint('❌ Error fetching ads popup config: $e');
      return AdsPopupConfig.defaultConfig();
    }
  }

  /// Clear cached configuration
  void clearCache() {
    _cachedConfig = null;
    _lastFetchTime = null;
    debugPrint('🔄 Ads popup config cache cleared');
  }

  /// Get cached config without fetching
  AdsPopupConfig? getCachedConfig() => _cachedConfig;
}
