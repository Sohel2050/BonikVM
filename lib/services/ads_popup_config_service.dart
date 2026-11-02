import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/config/app_config.dart';
import 'reward_video_service.dart';

/// Used ONLY when the admin panel value has never been received on this
/// device (first launch while offline). One single fallback for the whole app.
const int kFallbackAdRewardMinutes = 5;

int _asInt(dynamic v, int fallback) {
  if (v is num) return v.toInt();
  if (v is String) {
    final s = v.trim();
    return int.tryParse(s) ?? double.tryParse(s)?.toInt() ?? fallback;
  }
  return fallback;
}

/// Keeps an admin-panel number inside a sane range (0 or 999 can't break UI).
int _clamped(dynamic v, int fallback, int min, int max) {
  final n = _asInt(v, fallback);
  return n < min ? min : (n > max ? max : n);
}

bool _asBool(dynamic v, bool fallback) {
  if (v is bool) return v;
  if (v is num) return v != 0;
  if (v is String) {
    final s = v.trim().toLowerCase();
    if (s == 'true' || s == '1') return true;
    if (s == 'false' || s == '0') return false;
  }
  return fallback;
}

/// Configuration for ads popup from admin panel
class AdsPopupConfig {
  final bool enableBuySubscriptionPrompt;
  final String buySubscriptionText;
  final int adRewardDuration; // Minutes per ad for free time extension
  final bool enablePremiumUnlock;
  final int premiumUnlockDurationMinutes;
  final String premiumUnlockText;
  final int premiumUnlockAdCount;
  final int extendTimeAdCount;

  AdsPopupConfig({
    required this.enableBuySubscriptionPrompt,
    required this.buySubscriptionText,
    required this.adRewardDuration,
    required this.enablePremiumUnlock,
    required this.premiumUnlockDurationMinutes,
    required this.premiumUnlockText,
    this.premiumUnlockAdCount = 1,
    this.extendTimeAdCount = 3,
  });

  factory AdsPopupConfig.fromJson(Map<String, dynamic> json) {
    final reward = _asInt(json['ad_reward_duration'], kFallbackAdRewardMinutes);
    return AdsPopupConfig(
      enableBuySubscriptionPrompt:
          _asBool(json['enable_buy_subscription_prompt'], true),
      buySubscriptionText: (json['buy_subscription_text'] as String?) ??
          'Watch ads to extend your free time or subscribe for unlimited access',
      adRewardDuration: reward > 0 ? reward : kFallbackAdRewardMinutes,
      enablePremiumUnlock: _asBool(json['enable_premium_unlock_ads'], true),
      premiumUnlockDurationMinutes:
          _clamped(json['premium_unlock_duration_minutes'], 5, 1, 100000),
      premiumUnlockText: (json['premium_unlock_text'] as String?) ??
          'Watch an ad to unlock this premium server',
      // Admin-panel controlled (1..10 ads). Used only if the server hasn't
      // set them yet: 1 ad for premium unlock, 3 ads for extending time.
      premiumUnlockAdCount: _clamped(json['premium_unlock_ad_count'], 1, 1, 10),
      extendTimeAdCount: _clamped(json['extend_time_ad_count'], 3, 1, 10),
    );
  }

  Map<String, dynamic> toJson() => {
        'enable_buy_subscription_prompt': enableBuySubscriptionPrompt,
        'buy_subscription_text': buySubscriptionText,
        'ad_reward_duration': adRewardDuration,
        'enable_premium_unlock_ads': enablePremiumUnlock,
        'premium_unlock_duration_minutes': premiumUnlockDurationMinutes,
        'premium_unlock_text': premiumUnlockText,
        'premium_unlock_ad_count': premiumUnlockAdCount,
        'extend_time_ad_count': extendTimeAdCount,
      };

  factory AdsPopupConfig.defaultConfig() {
    return AdsPopupConfig(
      enableBuySubscriptionPrompt: true,
      buySubscriptionText:
          'Watch ads to extend your free time or subscribe for unlimited access',
      adRewardDuration: kFallbackAdRewardMinutes,
      enablePremiumUnlock: true,
      premiumUnlockDurationMinutes: 5,
      premiumUnlockText: 'Watch an ad to unlock this premium server',
      premiumUnlockAdCount: 1,
      extendTimeAdCount: 3,
    );
  }
}

/// Service to manage ads popup configuration
class AdsPopupConfigService {
  static final AdsPopupConfigService _instance =
      AdsPopupConfigService._internal();
  factory AdsPopupConfigService() => _instance;
  AdsPopupConfigService._internal();

  static const String _prefsKey = 'ads_popup_config_last_good_v1';

  AdsPopupConfig? _cachedConfig;
  DateTime? _lastFetchTime;
  Future<AdsPopupConfig>? _inFlight;

  /// Cache duration (2 minutes — short so admin changes apply quickly)
  static const Duration _cacheDuration = Duration(minutes: 2);

  /// Fetch ads popup configuration from backend.
  ///
  /// Order of truth: fresh cache -> server -> last config received from the
  /// server (memory, then disk) -> built-in fallback. So if the network
  /// hiccups, the app keeps using the LAST ADMIN VALUE instead of a
  /// hardcoded number.
  Future<AdsPopupConfig> getAdsPopupConfig({bool forceRefresh = false}) async {
    if (!forceRefresh && _cachedConfig != null && _lastFetchTime != null) {
      if (DateTime.now().difference(_lastFetchTime!) < _cacheDuration) {
        debugPrint('✅ Using cached ads popup config');
        return _cachedConfig!;
      }
    }

    // Many widgets ask at the same time: share ONE request.
    final running = _inFlight;
    if (running != null) return running;

    final future = _fetchWithFallback();
    _inFlight = future;
    try {
      return await future;
    } finally {
      _inFlight = null;
    }
  }

  Future<AdsPopupConfig> _fetchWithFallback() async {
    final fetched = await _fetchFromApi();
    if (fetched != null) {
      _cachedConfig = fetched;
      _lastFetchTime = DateTime.now();
      _applyToRewardTracker(fetched);
      await _persist(fetched);
      debugPrint(
          '✅ Ads popup config fetched (ad_reward_duration=${fetched.adRewardDuration})');
      return fetched;
    }

    // Server unreachable: keep the last admin value. _lastFetchTime is left
    // untouched so the next call tries the server again.
    if (_cachedConfig != null) {
      debugPrint('⚠️ Using stale in-memory ads popup config');
      return _cachedConfig!;
    }
    final saved = await _loadPersisted();
    if (saved != null) {
      _cachedConfig = saved;
      _applyToRewardTracker(saved);
      debugPrint('⚠️ Using last saved ads popup config from disk');
      return saved;
    }
    debugPrint('❌ No ads popup config available, using built-in fallback');
    return AdsPopupConfig.defaultConfig();
  }

  /// The daily "videos watched" tracker follows the admin panel too, instead
  /// of its own fixed 3 videos / 5 minutes.
  void _applyToRewardTracker(AdsPopupConfig cfg) {
    RewardVideoService().applyAdminConfig(
      maxVideos: cfg.extendTimeAdCount,
      minutesPerVideo: cfg.adRewardDuration,
    );
  }

  Future<AdsPopupConfig?> _fetchFromApi() async {
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
      if (response.statusCode != 200) return null;

      final data = response.data;
      Map<String, dynamic>? adsPopupData;
      if (data is Map<String, dynamic>) {
        // Direct format
        final direct = data['ads_popup'];
        if (direct is Map) adsPopupData = Map<String, dynamic>.from(direct);

        // Or nested format
        if (adsPopupData == null) {
          final nested = data['data'];
          if (nested is Map && nested['ads_popup'] is Map) {
            adsPopupData = Map<String, dynamic>.from(nested['ads_popup'] as Map);
          }
        }
      }
      if (adsPopupData == null) return null;
      return AdsPopupConfig.fromJson(adsPopupData);
    } catch (e) {
      debugPrint('⚠️ Error fetching ads popup config: $e');
      return null;
    }
  }

  Future<void> _persist(AdsPopupConfig cfg) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, jsonEncode(cfg.toJson()));
    } catch (e) {
      debugPrint('⚠️ Could not save ads popup config: $e');
    }
  }

  Future<AdsPopupConfig?> _loadPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return null;
      final map = jsonDecode(raw);
      if (map is Map) {
        return AdsPopupConfig.fromJson(Map<String, dynamic>.from(map));
      }
    } catch (e) {
      debugPrint('⚠️ Could not read saved ads popup config: $e');
    }
    return null;
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
