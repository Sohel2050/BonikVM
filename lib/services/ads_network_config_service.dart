import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/config/app_config.dart';
import '../core/services/level_play_service.dart';

/// LevelPlay values chosen in Admin > Ads Settings > Unity LevelPlay.
/// Any empty value means "not set in admin" and the app keeps its built-in
/// (.env) value, so a missing/partial admin config can never break ads.
class LevelPlayRemoteConfig {
  final String androidAppKey;
  final String iosAppKey;
  final String rewardedAdUnitId;
  final String interstitialAdUnitId;
  final String bannerAdUnitId;
  final String nativeAdUnitId;

  const LevelPlayRemoteConfig({
    this.androidAppKey = '',
    this.iosAppKey = '',
    this.rewardedAdUnitId = '',
    this.interstitialAdUnitId = '',
    this.bannerAdUnitId = '',
    this.nativeAdUnitId = '',
  });
}

/// Reads the `ads` block of /api/v1/app-config. The last good response is
/// cached, so ad keys are available instantly at the next app start and a
/// slow or failed request never delays or breaks startup.
class AdsNetworkConfigService {
  AdsNetworkConfigService._();

  static const String _cacheKey = 'ads_network_config_v1';

  /// Returns [remote] if it is non-empty, otherwise [fallback].
  static String? pick(String? remote, String? fallback) =>
      (remote != null && remote.trim().isNotEmpty) ? remote.trim() : fallback;

  /// LevelPlay config from the cache (null if nothing cached yet).
  static Future<LevelPlayRemoteConfig?> cachedLevelPlay() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw == null || raw.isEmpty) return null;
      return _levelPlayFrom(jsonDecode(raw));
    } catch (e) {
      debugPrint('AdsNetworkConfig: cache read failed: $e');
      return null;
    }
  }

  /// Downloads the latest `ads` block and caches it for the next start.
  static Future<void> refresh() async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'Accept': 'application/json',
            'X-API-Token': AppConfig.apiKey,
          },
        ),
      );
      final res = await dio.get('/api/v1/app-config');
      final data = res.data;
      if (res.statusCode == 200 && data is Map && data['ads'] is Map) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_cacheKey, jsonEncode(data['ads']));
        debugPrint('AdsNetworkConfig: refreshed');
      }
    } catch (e) {
      debugPrint('AdsNetworkConfig: refresh failed: $e');
    }
  }

  // ------------------------------------------------------------------
  // Interstitial timing (Admin > Ads Settings > Ad Display Timing), seconds
  // ------------------------------------------------------------------

  static const String _timingCacheKey = 'ad_timing_config_v1';

  static void _applyTiming(Map data) {
    int? asInt(dynamic v) => v == null ? null : int.tryParse(v.toString());
    LevelPlayService.instance.applyAdTiming(
      initialDelaySeconds: asInt(data['initial_delay_seconds']),
      cooldownSeconds: asInt(data['cooldown_seconds']),
      triggerCount: asInt(data['interstitial_trigger_count']),
    );
  }

  /// Applies the last saved timing instantly (call before ads can show).
  static Future<void> applyCachedAdTiming() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_timingCacheKey);
      if (raw == null || raw.isEmpty) return;
      final data = jsonDecode(raw);
      if (data is Map) _applyTiming(data);
    } catch (e) {
      debugPrint('AdsNetworkConfig: timing cache read failed: $e');
    }
  }

  /// Fetches the latest timing from the server, applies and caches it.
  static Future<void> syncAdTiming() async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'Accept': 'application/json',
            'X-API-Token': AppConfig.apiKey,
          },
        ),
      );
      final res = await dio.get('/api/v1/get-ad-settings');
      final data = res.data;
      if (res.statusCode == 200 && data is Map) {
        final timing = <String, dynamic>{
          'initial_delay_seconds': data['initial_delay_seconds'],
          'cooldown_seconds': data['cooldown_seconds'],
          'interstitial_trigger_count': data['interstitial_trigger_count'],
        };
        _applyTiming(timing);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_timingCacheKey, jsonEncode(timing));
      }
    } catch (e) {
      debugPrint('AdsNetworkConfig: timing sync failed: $e');
    }
  }

  static LevelPlayRemoteConfig? _levelPlayFrom(dynamic ads) {
    if (ads is! Map) return null;
    // Admin picks ONE active network; LevelPlay values apply only if it is
    // LevelPlay. Otherwise the app keeps its built-in (.env) LevelPlay setup.
    if (ads['primary_network']?.toString() != 'levelplay') return null;
    final nets = ads['networks'];
    if (nets is! Map) return null;
    final lp = nets['levelplay'];
    if (lp is! Map) return null;

    final os = Platform.isIOS ? 'ios' : 'android';

    String unit(String name) {
      final v = lp[name];
      return (v is Map ? v[os] : null)?.toString().trim() ?? '';
    }

    String appKey(String platform) {
      final v = lp['app_key'];
      return (v is Map ? v[platform] : null)?.toString().trim() ?? '';
    }

    return LevelPlayRemoteConfig(
      androidAppKey: appKey('android'),
      iosAppKey: appKey('ios'),
      rewardedAdUnitId: unit('rewarded'),
      interstitialAdUnitId: unit('interstitial'),
      bannerAdUnitId: unit('banner'),
      nativeAdUnitId: unit('native'),
    );
  }
}
