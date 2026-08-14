import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_service.dart';
import 'api_cache_service.dart';

// ==================== AD CONFIG MODELS ====================

/// Model to hold ad configuration for a server
class AdConfig {
  final int serverId;
  final String serverName;
  final bool isPremium;
  final bool enableAds;
  final bool enablePremiumAds;
  final int premiumUnlockDuration; // in minutes
  final List<AdReward> ads;

  AdConfig({
    required this.serverId,
    required this.serverName,
    this.isPremium = false,
    this.enableAds = true,
    this.enablePremiumAds = true,
    required this.premiumUnlockDuration,
    required this.ads,
  });

  factory AdConfig.fromJson(Map<String, dynamic> json) {
    final adsData = json['ads'] as List<dynamic>? ?? [];
    return AdConfig(
      serverId: json['server_id'] ?? 0,
      serverName: json['server_name'] ?? 'Unknown',
      isPremium: json['is_premium'] ?? false,
      enableAds: json['enable_ads'] ?? true,
      enablePremiumAds: json['enable_premium_ads'] ?? true,
      premiumUnlockDuration: json['premium_unlock_duration'] ?? 20,
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

// ==================== AD MOB SERVICE ====================

class AdMobService {
  static final AdMobService _instance = AdMobService._internal();
  factory AdMobService() => _instance;
  AdMobService._internal();

  static AdMobService get instance => _instance;

  // Dynamic Ad Unit IDs from API
  String? _bannerAdUnitId;
  String? _interstitialAdUnitId;
  String? _rewardedAdUnitId;
  String? _nativeAdUnitId;
  String? _appOpenAdUnitId;

  // Fallback Test Ad Unit IDs
  static String get _testBannerAdUnitId =>
      'ca-app-pub-3940256099942544/6300978111';
  static String get _testInterstitialAdUnitId =>
      'ca-app-pub-3940256099942544/1033173712';
  static String get _testRewardedAdUnitId =>
      'ca-app-pub-3940256099942544/5224354917';
  static String get _testNativeAdUnitId =>
      'ca-app-pub-3940256099942544/2247696110';
  static String get _testAppOpenAdUnitId =>
      'ca-app-pub-3940256099942544/3419835294';

  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  NativeAd? _nativeAd;
  AppOpenAd? _appOpenAd;

  // Control flags
  bool _adsEnabled = true;
  bool _userIsPremium = false;

  bool _isInterstitialReady = false;
  bool _isRewardedReady = false;
  bool _isAppOpenReady = false;

  // Admin settings from API
  bool _bannerAdsEnabled = true;
  bool _interstitialAdsEnabled = true;
  bool _rewardedAdsEnabled = true;
  bool _nativeAdsEnabled = true;
  bool _appOpenAdsEnabled = true;

  // Frequency controls
  int _appOpenAdFrequencyHours = 1;
  int _interstitialAdFrequencyMinutes = 5;
  DateTime? _lastAppOpenAdShown;
  DateTime? _lastInterstitialAdShown;

  // NEW: Ad Timing Controls from Admin Panel
  int _initialDelaySeconds = 300; // 5 minutes default
  int _cooldownSeconds = 180; // 3 minutes default
  int _interstitialTriggerCount = 3; // After N actions
  bool _hideAdsForPremium = true;
  DateTime? _appLaunchTime;
  DateTime? _lastAdShown;
  int _actionCounter = 0;

  // App open ad protection
  bool _isShowingAppOpenAd = false;

  // Ad Configuration Cache (serverId -> AdConfig)
  final Map<int, AdConfig> _adConfigCache = {};

  Future<void> initialize() async {
    try {
      // Record app launch time for initial delay
      _appLaunchTime = DateTime.now();

      // Quick initialization - don't block startup for API calls
      await MobileAds.instance.initialize();

      // Load cached settings first (non-blocking)
      _loadCachedSettings();

      // Start async background tasks without blocking
      _initializeInBackground();
    } catch (e) {}
  }

  /// Load cached settings immediately (non-blocking)
  void _loadCachedSettings() {
    try {
      // Set defaults that work immediately
      _bannerAdUnitId = _testBannerAdUnitId;
      _interstitialAdUnitId = _testInterstitialAdUnitId;
      _rewardedAdUnitId = _testRewardedAdUnitId;
      _nativeAdUnitId = _testNativeAdUnitId;
      _appOpenAdUnitId = _testAppOpenAdUnitId;
    } catch (e) {}
  }

  /// Initialize background tasks asynchronously
  Future<void> _initializeInBackground() async {
    try {
      // Check admin settings and premium status first (with timeout)
      await _checkAdSettings().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return;
        },
      );

      if (!_adsEnabled || _userIsPremium) {
        return; // Skip ad loading
      }

      // Load AdMob IDs from API (with timeout)
      await _loadAdMobIds().timeout(
        const Duration(seconds: 5),
        onTimeout: () {
          return;
        },
      );

      // Load ads in background
      _loadAppOpenAd();
      _loadInterstitialAd();
      _loadRewardedAd();

      // Schedule periodic ad preloading
      _scheduleAdPreloading();
    } catch (e) {}
  }

  /// Check admin settings and user premium status
  Future<void> _checkAdSettings() async {
    try {
      // Check if user is premium
      final prefs = await SharedPreferences.getInstance();
      _userIsPremium = prefs.getBool('is_premium') ?? false;

      // Fetch admin settings from API with caching
      try {
        const cacheKey = 'admob_admin_settings';
        final cacheService = ApiCacheService();

        Map<String, dynamic>? cachedSettings = await cacheService
            .getCachedResponse(
              cacheKey,
              maxAge: const Duration(
                minutes: 15,
              ), // Cache admin settings for 15 minutes
            );

        Map<String, dynamic> adminSettings;

        if (cachedSettings != null) {
          adminSettings = cachedSettings;
        } else {
          adminSettings = await ApiService.instance.getAdmobSettings();

          // Cache the admin settings
          await cacheService.cacheResponse(cacheKey, adminSettings);
        }

        _adsEnabled = adminSettings['ads_enabled'] ?? true;
        _bannerAdsEnabled = adminSettings['banner_ads_enabled'] ?? true;
        _interstitialAdsEnabled =
            adminSettings['interstitial_ads_enabled'] ?? true;
        _rewardedAdsEnabled = adminSettings['rewarded_ads_enabled'] ?? true;
        _nativeAdsEnabled = adminSettings['native_ads_enabled'] ?? true;
        _appOpenAdsEnabled = adminSettings['app_open_ads_enabled'] ?? true;

        _appOpenAdFrequencyHours =
            adminSettings['app_open_ad_frequency_hours'] ?? 1;
        _interstitialAdFrequencyMinutes =
            adminSettings['interstitial_ad_frequency_minutes'] ?? 5;

        // Load new timing settings
        _initialDelaySeconds = adminSettings['initial_delay_seconds'] ?? 300;
        _cooldownSeconds = adminSettings['cooldown_seconds'] ?? 180;
        _interstitialTriggerCount =
            adminSettings['interstitial_trigger_count'] ?? 3;
        _hideAdsForPremium = adminSettings['hide_ads_for_premium'] ?? true;

      } catch (e) {
        // Keep default values if API fails
      }
    } catch (e) {
      // Default to showing ads if we can't check settings
      _adsEnabled = true;
      _userIsPremium = false;
    }
  }

  /// Re-check ad settings (call when app resumes)
  Future<void> refreshAdSettings() async {
    await _checkAdSettings();

    if (!_adsEnabled || _userIsPremium) {
      // Dispose all ads if they should be disabled
      _disposeAllAds();
    } else {
      // Re-initialize ads if they should be enabled
      await initialize();
    }
  }

  /// Dispose all loaded ads
  void _disposeAllAds() {
    _bannerAd?.dispose();
    _bannerAd = null;

    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isInterstitialReady = false;

    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isRewardedReady = false;

    _appOpenAd?.dispose();
    _appOpenAd = null;
    _isAppOpenReady = false;

    _nativeAd?.dispose();
    _nativeAd = null;
  }

  Future<void> _loadAdMobIds() async {
    // Debug builds always use Google's official test ad unit IDs, never
    // real ones from the backend — avoids serving live production ads
    // (and getting the AdMob account flagged for invalid traffic) while
    // developing/testing.
    if (kDebugMode) {
      _bannerAdUnitId = _testBannerAdUnitId;
      _interstitialAdUnitId = _testInterstitialAdUnitId;
      _rewardedAdUnitId = _testRewardedAdUnitId;
      _nativeAdUnitId = _testNativeAdUnitId;
      _appOpenAdUnitId = _testAppOpenAdUnitId;
      return;
    }

    try {
      // Check cache first to prevent rapid API calls
      const cacheKey = 'admob_ad_ids';
      final cacheService = ApiCacheService();

      Map<String, dynamic>? cachedData = await cacheService.getCachedResponse(
        cacheKey,
        maxAge: const Duration(minutes: 10), // Cache for 10 minutes
      );

      dynamic adConfig;

      if (cachedData != null) {
        // Create a mock config object from cached data
        adConfig = _AdConfigFromCache(cachedData);
      } else {
        adConfig = await ApiService.instance.getAdIds();

        // Cache the response
        await cacheService.cacheResponse(cacheKey, {
          'banner_android': adConfig.bannerAndroid,
          'banner_ios': adConfig.bannerIos,
          'interstitial_android': adConfig.interstitialAndroid,
          'interstitial_ios': adConfig.interstitialIos,
          'rewarded_android': adConfig.rewardedAndroid,
          'rewarded_ios': adConfig.rewardedIos,
          'native_android': adConfig.nativeAndroid,
          'native_ios': adConfig.nativeIos,
          'app_open_android': adConfig.appOpenAndroid,
          'app_open_ios': adConfig.appOpenIos,
        });
      }

      if (Platform.isAndroid) {
        _bannerAdUnitId = adConfig.bannerAndroid.isNotEmpty
            ? adConfig.bannerAndroid
            : _testBannerAdUnitId;
        _interstitialAdUnitId = adConfig.interstitialAndroid.isNotEmpty
            ? adConfig.interstitialAndroid
            : _testInterstitialAdUnitId;
        _rewardedAdUnitId = adConfig.rewardedAndroid.isNotEmpty
            ? adConfig.rewardedAndroid
            : _testRewardedAdUnitId;
        _nativeAdUnitId = adConfig.nativeAndroid.isNotEmpty
            ? adConfig.nativeAndroid
            : _testNativeAdUnitId;
        _appOpenAdUnitId = adConfig.appOpenAndroid.isNotEmpty
            ? adConfig.appOpenAndroid
            : _testAppOpenAdUnitId;
      } else {
        _bannerAdUnitId = adConfig.bannerIos.isNotEmpty
            ? adConfig.bannerIos
            : _testBannerAdUnitId;
        _interstitialAdUnitId = adConfig.interstitialIos.isNotEmpty
            ? adConfig.interstitialIos
            : _testInterstitialAdUnitId;
        _rewardedAdUnitId = adConfig.rewardedIos.isNotEmpty
            ? adConfig.rewardedIos
            : _testRewardedAdUnitId;
        _nativeAdUnitId = adConfig.nativeIos.isNotEmpty
            ? adConfig.nativeIos
            : _testNativeAdUnitId;
        _appOpenAdUnitId = adConfig.appOpenIos.isNotEmpty
            ? adConfig.appOpenIos
            : _testAppOpenAdUnitId;
      }
    } catch (e) {
      // Fallback to test IDs
      _bannerAdUnitId = _testBannerAdUnitId;
      _interstitialAdUnitId = _testInterstitialAdUnitId;
      _rewardedAdUnitId = _testRewardedAdUnitId;
      _nativeAdUnitId = _testNativeAdUnitId;
      _appOpenAdUnitId = _testAppOpenAdUnitId;
    }
  }

  // Getters for Ad Unit IDs
  String get bannerAdUnitId => _bannerAdUnitId ?? _testBannerAdUnitId;
  String get interstitialAdUnitId =>
      _interstitialAdUnitId ?? _testInterstitialAdUnitId;
  String get rewardedAdUnitId => _rewardedAdUnitId ?? _testRewardedAdUnitId;
  String get nativeAdUnitId => _nativeAdUnitId ?? _testNativeAdUnitId;
  String get appOpenAdUnitId => _appOpenAdUnitId ?? _testAppOpenAdUnitId;

  // Banner Ad
  BannerAd createBannerAd({
    required Function(Ad) onAdLoaded,
    required Function(Ad, LoadAdError) onAdFailedToLoad,
  }) {
    // Check admin settings
    if (!_adsEnabled || _userIsPremium || !_bannerAdsEnabled) {
      // Return a dummy banner that will fail to load
      return BannerAd(
        adUnitId: 'disabled',
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (ad) {}, // Do nothing
          onAdFailedToLoad: (ad, error) => onAdFailedToLoad(ad, error),
        ),
      );
    }

    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
        onAdOpened: (Ad ad) {}, // Remove debug logging
        onAdClosed: (Ad ad) {}, // Remove debug logging
      ),
    );
  }

  // Interstitial Ad
  void _loadInterstitialAd() {
    // Only load if enabled
    if (!_adsEnabled || _userIsPremium || !_interstitialAdsEnabled) {
      return;
    }

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isInterstitialReady = true;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isInterstitialReady = false;
        },
      ),
    );
  }

  /// Check if enough time has passed to show an ad
  bool _canShowAd() {
    // Check if initial delay has passed since app launch
    if (_appLaunchTime != null) {
      final timeSinceLaunch = DateTime.now().difference(_appLaunchTime!);
      if (timeSinceLaunch.inSeconds < _initialDelaySeconds) {
        return false;
      }
    } else {
    }

    // Check cooldown period since last ad
    if (_lastAdShown != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastAdShown!);
      if (timeSinceLastAd.inSeconds < _cooldownSeconds) {
        return false;
      }
    }

    return true;
  }

  /// Increment action counter for interstitial ad triggers
  void incrementActionCounter() {
    _actionCounter++;
  }

  void showInterstitialAd({Function()? onAdClosed}) {

    // Check admin settings and premium status
    if (!_adsEnabled || !_interstitialAdsEnabled) {
      return;
    }

    // Check if premium users should see ads
    if (_userIsPremium && _hideAdsForPremium) {
      return;
    }

    // Check timing delays
    if (!_canShowAd()) {
      final timeSinceLaunch = _appLaunchTime != null
          ? DateTime.now().difference(_appLaunchTime!).inSeconds
          : 0;
      final timeSinceLastAd = _lastAdShown != null
          ? DateTime.now().difference(_lastAdShown!).inSeconds
          : 999999;
      return;
    }

    // Check if enough actions have been performed
    if (_actionCounter < _interstitialTriggerCount) {
      return;
    }


    // Check old frequency control (keeping for compatibility)
    if (_lastInterstitialAdShown != null) {
      final timeSinceLastAd = DateTime.now().difference(
        _lastInterstitialAdShown!,
      );
      if (timeSinceLastAd.inMinutes < _interstitialAdFrequencyMinutes) {
        return;
      }
    }

    if (_isInterstitialReady && _interstitialAd != null) {
      _lastInterstitialAdShown = DateTime.now();
      _lastAdShown = DateTime.now();
      _actionCounter = 0; // Reset counter after showing ad

      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (InterstitialAd ad) {
          ad.dispose();
          _loadInterstitialAd(); // Load next ad
          onAdClosed?.call();
        },
        onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
          ad.dispose();
          _loadInterstitialAd(); // Load next ad
        },
      );
      _interstitialAd!.show();
      _isInterstitialReady = false;
    } else {}
  }

  /// Show an interstitial when VPN reaches connected state.
  /// This intentionally skips action-counter checks so connection events can
  /// trigger ads immediately when inventory is ready.
  void showConnectionInterstitialAd({Function()? onAdClosed}) {
    if (!_adsEnabled || !_interstitialAdsEnabled) {
      return;
    }

    if (_userIsPremium && _hideAdsForPremium) {
      return;
    }

    if (_isInterstitialReady && _interstitialAd != null) {
      _lastInterstitialAdShown = DateTime.now();
      _lastAdShown = DateTime.now();
      _actionCounter = 0;

      _interstitialAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (InterstitialAd ad) {
          ad.dispose();
          _loadInterstitialAd();
          onAdClosed?.call();
        },
        onAdFailedToShowFullScreenContent: (InterstitialAd ad, AdError error) {
          ad.dispose();
          _loadInterstitialAd();
        },
      );

      _interstitialAd!.show();
      _isInterstitialReady = false;
      return;
    }

    _loadInterstitialAd();
  }

  // Rewarded Ad
  void _loadRewardedAd() {
    // Only load if enabled
    if (!_adsEnabled || _userIsPremium || !_rewardedAdsEnabled) {
      return;
    }

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardedAd = ad;
          _isRewardedReady = true;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isRewardedReady = false;
        },
      ),
    );
  }

  void showRewardedAd({
    required Function(AdWithoutView, RewardItem) onUserEarnedReward,
    Function()? onAdClosed,
  }) {
    // Check admin settings
    if (!_adsEnabled || _userIsPremium || !_rewardedAdsEnabled) {
      return;
    }

    if (_isRewardedReady && _rewardedAd != null) {
      _rewardedAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (RewardedAd ad) {
          ad.dispose();
          _loadRewardedAd(); // Load next ad
          onAdClosed?.call();
        },
        onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
          ad.dispose();
          _loadRewardedAd(); // Load next ad
        },
      );
      _rewardedAd!.show(onUserEarnedReward: onUserEarnedReward);
      _isRewardedReady = false;
    } else {
      _loadRewardedAd();
    }
  }

  // Native Ad
  NativeAd createNativeAd({
    required Function(Ad) onAdLoaded,
    required Function(Ad, LoadAdError) onAdFailedToLoad,
  }) {
    // Check admin settings
    if (!_adsEnabled || _userIsPremium || !_nativeAdsEnabled) {
      // Return a dummy native ad that will fail to load
      return NativeAd(
        adUnitId: 'disabled',
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (ad) {}, // Do nothing
          onAdFailedToLoad: (ad, error) => onAdFailedToLoad(ad, error),
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
        ),
      );
    }

    return NativeAd(
      adUnitId: nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad: onAdFailedToLoad,
        onAdOpened: (Ad ad) {}, // Remove debug logging
        onAdClosed: (Ad ad) {}, // Remove debug logging
      ),
      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
      ),
    );
  }

  // App Open Ad
  void _loadAppOpenAd() {
    // Only load if enabled
    if (!_adsEnabled || _userIsPremium || !_appOpenAdsEnabled) {
      return;
    }

    AppOpenAd.load(
      adUnitId: appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback: AppOpenAdLoadCallback(
        onAdLoaded: (AppOpenAd ad) {
          _appOpenAd = ad;
          _isAppOpenReady = true;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _isAppOpenReady = false;
        },
      ),
    );
  }

  void showAppOpenAd({Function()? onAdClosed}) {

    // Check admin settings and premium status
    if (!_adsEnabled || _userIsPremium || !_appOpenAdsEnabled) {
      return;
    }

    // NEW: Check timing delays (same as interstitial)
    if (!_canShowAd()) {
      return;
    }

    // Prevent duplicate app open ads
    if (_isShowingAppOpenAd) {

      return;
    }

    // Check frequency control
    if (_lastAppOpenAdShown != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastAppOpenAdShown!);
      if (timeSinceLastAd.inHours < _appOpenAdFrequencyHours) {
        return;
      }
    }

    if (_isAppOpenReady && _appOpenAd != null) {
      _isShowingAppOpenAd = true;
      _lastAppOpenAdShown = DateTime.now();
      _lastAdShown = DateTime.now(); // Update shared cooldown timer

      _appOpenAd!.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (AppOpenAd ad) {
          _isShowingAppOpenAd = false;
          ad.dispose();
          _loadAppOpenAd(); // Load next ad
          onAdClosed?.call();
        },
        onAdFailedToShowFullScreenContent: (AppOpenAd ad, AdError error) {
          _isShowingAppOpenAd = false;
          ad.dispose();
          _loadAppOpenAd(); // Load next ad
        },
        onAdShowedFullScreenContent: (AppOpenAd ad) {},
      );
      _appOpenAd!.show();
      _isAppOpenReady = false;
    } else {}
  }

  // Preload rewarded ad for premium upgrade
  void preloadRewardedAd() {
    if (!_isRewardedReady) {
      _loadRewardedAd();
    }
  }

  // Check if interstitial is ready
  bool get isInterstitialReady =>
      _isInterstitialReady &&
      _interstitialAdsEnabled &&
      _adsEnabled &&
      !_userIsPremium;

  // Check if rewarded is ready
  bool get isRewardedReady =>
      _isRewardedReady && _rewardedAdsEnabled && _adsEnabled && !_userIsPremium;

  // Check if app open is ready (with frequency check)
  bool get isAppOpenReady {
    if (!_isAppOpenReady ||
        !_appOpenAdsEnabled ||
        !_adsEnabled ||
        _userIsPremium ||
        _isShowingAppOpenAd) {
      return false;
    }

    // Check frequency
    if (_lastAppOpenAdShown != null) {
      final timeSinceLastAd = DateTime.now().difference(_lastAppOpenAdShown!);
      if (timeSinceLastAd.inHours < _appOpenAdFrequencyHours) {
        return false;
      }
    }

    return true;
  }

  // Check if banner ads are enabled
  bool get areBannerAdsEnabled =>
      _bannerAdsEnabled && _adsEnabled && !_userIsPremium;

  // Check if native ads are enabled
  bool get areNativeAdsEnabled =>
      _nativeAdsEnabled && _adsEnabled && !_userIsPremium;

  // Get next app open ad availability
  String get nextAppOpenAdAvailability {
    if (!_appOpenAdsEnabled || !_adsEnabled || _userIsPremium) {
      return 'Disabled';
    }

    if (_lastAppOpenAdShown == null) {
      return 'Available now';
    }

    final timeSinceLastAd = DateTime.now().difference(_lastAppOpenAdShown!);
    final remainingHours = _appOpenAdFrequencyHours - timeSinceLastAd.inHours;

    if (remainingHours <= 0) {
      return 'Available now';
    }

    return 'Available in ${remainingHours}h ${60 - timeSinceLastAd.inMinutes % 60}m';
  }

  // Reset frequency restrictions (useful for testing or admin override)
  void resetFrequencyRestrictions() {
    _lastAppOpenAdShown = null;
    _lastInterstitialAdShown = null;
  }

  // Dispose all ads
  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();
    _nativeAd?.dispose();
    _appOpenAd?.dispose();
  }

  // Schedule periodic ad preloading to ensure ads are always available
  void _scheduleAdPreloading() {
    // Preload ads every 30 seconds to ensure availability
    Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isInterstitialReady) {
        _loadInterstitialAd();
      }
      if (!_isRewardedReady) {
        _loadRewardedAd();
      }
      if (!_isAppOpenReady) {
        _loadAppOpenAd();
      }
    });
  }

  // Force reload rewarded ad if needed
  void ensureRewardedAdReady() {
    if (!_isRewardedReady) {
      _loadRewardedAd();
    }
  }

  // Force reload interstitial ad if needed
  void ensureInterstitialAdReady() {
    if (!_isInterstitialReady) {
      _loadInterstitialAd();
    }
  }

  // ==================== AD CONFIG METHODS ====================

  /// Fetch ad configuration for a specific server
  Future<AdConfig?> getAdConfig(dynamic serverId) async {
    try {
      // Convert to int if string
      final serverIdInt = serverId is String
          ? int.tryParse(serverId) ?? 0
          : serverId as int;

      // Check cache first
      if (_adConfigCache.containsKey(serverIdInt)) {
        return _adConfigCache[serverIdInt];
      }

      // Fetch from API
      try {
        final response = await ApiService.instance.getAdConfig(serverIdInt);

        if (response['success'] == true && response['data'] != null) {
          final adConfig = AdConfig.fromJson(response['data']);
          // Cache the result
          _adConfigCache[serverIdInt] = adConfig;
          return adConfig;
        } else {
          return null;
        }
      } catch (e) {
        return _getDefaultAdConfig(serverIdInt);
      }
    } catch (e) {
      final serverIdInt = serverId is String
          ? int.tryParse(serverId) ?? 0
          : serverId as int;
      return _getDefaultAdConfig(serverIdInt);
    }
  }

  /// Get default ad configuration (fallback values)
  AdConfig _getDefaultAdConfig(int serverId) {
    return AdConfig(
      serverId: serverId,
      serverName: 'Default Server',
      premiumUnlockDuration: 20,
      ads: [
        AdReward(id: 1, duration: 5, durationSeconds: 300),
        AdReward(id: 2, duration: 10, durationSeconds: 600),
        AdReward(id: 3, duration: 20, durationSeconds: 1200),
      ],
    );
  }

  /// Clear cache
  void clearAdConfigCache() {
    _adConfigCache.clear();
  }

  /// Clear specific server cache
  void clearServerAdConfigCache(dynamic serverId) {
    final serverIdInt = serverId is String
        ? int.tryParse(serverId) ?? 0
        : serverId as int;
    _adConfigCache.remove(serverIdInt);
  }

  /// Get ad reward duration in seconds for a specific ad
  int getAdDurationSeconds(dynamic serverId, int adIndex) {
    final serverIdInt = serverId is String
        ? int.tryParse(serverId) ?? 0
        : serverId as int;
    if (_adConfigCache.containsKey(serverIdInt)) {
      final config = _adConfigCache[serverIdInt];
      if (adIndex < config!.ads.length) {
        return config.ads[adIndex].durationSeconds;
      }
    }
    // Return default values
    const defaults = [300, 600, 1200]; // 5, 10, 20 minutes in seconds
    return adIndex < defaults.length ? defaults[adIndex] : 300;
  }

  /// Get premium unlock duration in seconds for a server
  Future<int> getPremiumUnlockDurationSeconds(dynamic serverId) async {
    final config = await getAdConfig(serverId);
    if (config != null) {
      return config.premiumUnlockDuration * 60; // Convert to seconds
    }
    return 1200; // 20 minutes default
  }
}

/// Helper class to create ad config from cached data
class _AdConfigFromCache {
  final Map<String, dynamic> _data;

  _AdConfigFromCache(this._data);

  String get bannerAndroid => _data['banner_android'] ?? '';
  String get bannerIos => _data['banner_ios'] ?? '';
  String get interstitialAndroid => _data['interstitial_android'] ?? '';
  String get interstitialIos => _data['interstitial_ios'] ?? '';
  String get rewardedAndroid => _data['rewarded_android'] ?? '';
  String get rewardedIos => _data['rewarded_ios'] ?? '';
  String get nativeAndroid => _data['native_android'] ?? '';
  String get nativeIos => _data['native_ios'] ?? '';
  String get appOpenAndroid => _data['app_open_android'] ?? '';
  String get appOpenIos => _data['app_open_ios'] ?? '';
}
