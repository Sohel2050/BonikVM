import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api/api_service.dart';
import 'api_cache_service.dart';

// ==================== AD CONFIG MODELS ====================
NativeAd? _nativeAd;
bool _isNativeReady = false;
/// Model to hold ad configuration for a server
class AdConfig {
  final int serverId;
  final String serverName;
  final bool isPremium;
  final bool enableAds;
  final bool enablePremiumAds;
  final int premiumUnlockDuration;
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
    final adsData = json['ads'] as List? ?? [];

    return AdConfig(
      serverId: json['server_id'] ?? 0,
      serverName: json['server_name'] ?? 'Unknown',
      isPremium: json['is_premium'] ?? false,
      enableAds: json['enable_ads'] ?? true,
      enablePremiumAds: json['enable_premium_ads'] ?? true,
      premiumUnlockDuration:
      json['premium_unlock_duration'] ?? 20,
      ads: adsData
          .map(
            (ad) => AdReward.fromJson(
          ad as Map<String, dynamic>,
        ),
      )
          .toList(),
    );
  }
}

/// Model for individual ad reward
class AdReward {
  final int id;
  final int duration;
  final int durationSeconds;

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

  // ==================== AD UNIT IDS ====================

  String? _bannerAdUnitId;
  String? _interstitialAdUnitId;
  String? _rewardedAdUnitId;
  String? _nativeAdUnitId;
  String? _appOpenAdUnitId;

  // ==================== TEST AD UNIT IDS ====================

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

  // ==================== AD OBJECTS ====================

  BannerAd? _bannerAd;
  InterstitialAd? _interstitialAd;
  RewardedAd? _rewardedAd;
  NativeAd? _nativeAd;
  AppOpenAd? _appOpenAd;

  // ==================== CONTROL FLAGS ====================

  bool _adsEnabled = false;
  bool _userIsPremium = false;

  bool _isInterstitialReady = false;
  bool _isRewardedReady = false;
  bool _isNativeReady = false;
  bool _isAppOpenReady = false;

  // ==================== ADMIN SETTINGS ====================

  bool _bannerAdsEnabled = true;
  bool _interstitialAdsEnabled = true;
  bool _rewardedAdsEnabled = true;
  bool _nativeAdsEnabled = true;
  bool _appOpenAdsEnabled = true;

  // ==================== FREQUENCY CONTROLS ====================

  int _appOpenAdFrequencyHours = 1;
  int _interstitialAdFrequencyMinutes = 5;

  DateTime? _lastAppOpenAdShown;
  DateTime? _lastInterstitialAdShown;

  // ==================== AD TIMING CONTROLS ====================

  int _initialDelaySeconds = 300;
  int _cooldownSeconds = 180;
  int _interstitialTriggerCount = 3;

  bool _hideAdsForPremium = true;

  DateTime? _appLaunchTime;
  DateTime? _lastAdShown;

  int _actionCounter = 0;

  // ==================== APP OPEN PROTECTION ====================

  bool _isShowingAppOpenAd = false;

  // ==================== PRELOAD TIMER ====================

  Timer? _preloadTimer;

  // ==================== AD CONFIG CACHE ====================

  final Map<int, AdConfig> _adConfigCache = {};

  // ==================== INITIALIZE ====================

  Future<void> initialize() async {
    try {
      _appLaunchTime = DateTime.now();

      print(
        '[AdMob] App launched at: $_appLaunchTime',
      );

      await MobileAds.instance.initialize();

      _loadCachedSettings();

      unawaited(_initializeInBackground());
    } catch (e) {
      print('[AdMob] Initialization error: $e');
    }
  }

  // ==================== LOAD DEFAULT IDS ====================

  void _loadCachedSettings() {
    _bannerAdUnitId = _testBannerAdUnitId;
    _interstitialAdUnitId =
        _testInterstitialAdUnitId;
    _rewardedAdUnitId = _testRewardedAdUnitId;
    _nativeAdUnitId = _testNativeAdUnitId;
    _appOpenAdUnitId = _testAppOpenAdUnitId;
  }

  // ==================== BACKGROUND INITIALIZATION ====================

  Future<void> _initializeInBackground() async {
    try {
      await _checkAdSettings().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );

      if (!_adsEnabled || _userIsPremium) {
        return;
      }

      await _loadAdMobIds().timeout(
        const Duration(seconds: 5),
        onTimeout: () {},
      );

      _loadAppOpenAd();
      _loadInterstitialAd();
      _loadRewardedAd();

      _scheduleAdPreloading();
    } catch (e) {
      print(
        '[AdMob] Background initialization error: $e',
      );
    }
  }

  // ==================== CHECK AD SETTINGS ====================

  Future<void> _checkAdSettings() async {
    try {
      final prefs =
      await SharedPreferences.getInstance();

      _userIsPremium =
          prefs.getBool('is_premium') ?? false;

      try {
        const cacheKey = 'admob_admin_settings';

        final cacheService = ApiCacheService();

        Map<String, dynamic>? cachedSettings =
        await cacheService.getCachedResponse(
          cacheKey,
          maxAge: const Duration(minutes: 15),
        );

        Map<String, dynamic> adminSettings;

        if (cachedSettings != null) {
          adminSettings = cachedSettings;
        } else {
          adminSettings =
          await ApiService.instance
              .getAdmobSettings();

          await cacheService.cacheResponse(
            cacheKey,
            adminSettings,
          );
        }

        _adsEnabled =
            adminSettings['ads_enabled'] ?? true;

        _bannerAdsEnabled =
            adminSettings['banner_ads_enabled'] ??
                true;

        _interstitialAdsEnabled =
            adminSettings[
            'interstitial_ads_enabled'] ??
                true;

        _rewardedAdsEnabled =
            adminSettings['rewarded_ads_enabled'] ??
                true;

        _nativeAdsEnabled =
            adminSettings['native_ads_enabled'] ??
                true;

        _appOpenAdsEnabled =
            adminSettings['app_open_ads_enabled'] ??
                true;

        _appOpenAdFrequencyHours =
            adminSettings[
            'app_open_ad_frequency_hours'] ??
                1;

        _interstitialAdFrequencyMinutes =
            adminSettings[
            'interstitial_ad_frequency_minutes'] ??
                5;

        _initialDelaySeconds =
            adminSettings['initial_delay_seconds'] ??
                300;

        _cooldownSeconds =
            adminSettings['cooldown_seconds'] ??
                180;

        _interstitialTriggerCount =
            adminSettings[
            'interstitial_trigger_count'] ??
                3;

        _hideAdsForPremium =
            adminSettings[
            'hide_ads_for_premium'] ??
                true;

        print(
          '[AdMob] Timing settings loaded:',
        );

        print(
          'Initial delay: $_initialDelaySeconds',
        );

        print(
          'Cooldown: $_cooldownSeconds',
        );

        print(
          'Trigger count: $_interstitialTriggerCount',
        );

        print(
          'Hide premium: $_hideAdsForPremium',
        );
      } catch (e) {
        print(
          '[AdMob] Admin settings error: $e',
        );
      }
    } catch (e) {
      _adsEnabled = true;
      _userIsPremium = false;

      print(
        '[AdMob] Settings fallback: $e',
      );
    }
  }

  // ==================== REFRESH SETTINGS ====================

  Future<void> refreshAdSettings() async {
    await _checkAdSettings();

    if (!_adsEnabled || _userIsPremium) {
      _disposeAllAds();
      return;
    }

    await _loadAdMobIds();

    _loadInterstitialAd();
    _loadRewardedAd();
    _loadAppOpenAd();
  }

  // ==================== LOAD AD IDS ====================

  Future<void> _loadAdMobIds() async {
    try {
      const cacheKey = 'admob_ad_ids';

      final cacheService = ApiCacheService();

      final cachedData =
      await cacheService.getCachedResponse(
        cacheKey,
        maxAge: const Duration(minutes: 10),
      );

      dynamic adConfig;

      if (cachedData != null) {
        adConfig = _AdConfigFromCache(
          cachedData,
        );
      } else {
        adConfig =
        await ApiService.instance.getAdIds();

        await cacheService.cacheResponse(
          cacheKey,
          {
            'banner_android':
            adConfig.bannerAndroid,
            'banner_ios':
            adConfig.bannerIos,
            'interstitial_android':
            adConfig.interstitialAndroid,
            'interstitial_ios':
            adConfig.interstitialIos,
            'rewarded_android':
            adConfig.rewardedAndroid,
            'rewarded_ios':
            adConfig.rewardedIos,
            'native_android':
            adConfig.nativeAndroid,
            'native_ios':
            adConfig.nativeIos,
            'app_open_android':
            adConfig.appOpenAndroid,
            'app_open_ios':
            adConfig.appOpenIos,
          },
        );
      }

      if (Platform.isAndroid) {
        _bannerAdUnitId =
        adConfig.bannerAndroid.isNotEmpty
            ? adConfig.bannerAndroid
            : _testBannerAdUnitId;

        _interstitialAdUnitId =
        adConfig.interstitialAndroid
            .isNotEmpty
            ? adConfig.interstitialAndroid
            : _testInterstitialAdUnitId;

        _rewardedAdUnitId =
        adConfig.rewardedAndroid.isNotEmpty
            ? adConfig.rewardedAndroid
            : _testRewardedAdUnitId;

        _nativeAdUnitId =
        adConfig.nativeAndroid.isNotEmpty
            ? adConfig.nativeAndroid
            : _testNativeAdUnitId;

        _appOpenAdUnitId =
        adConfig.appOpenAndroid.isNotEmpty
            ? adConfig.appOpenAndroid
            : _testAppOpenAdUnitId;
      } else {
        _bannerAdUnitId =
        adConfig.bannerIos.isNotEmpty
            ? adConfig.bannerIos
            : _testBannerAdUnitId;

        _interstitialAdUnitId =
        adConfig.interstitialIos.isNotEmpty
            ? adConfig.interstitialIos
            : _testInterstitialAdUnitId;

        _rewardedAdUnitId =
        adConfig.rewardedIos.isNotEmpty
            ? adConfig.rewardedIos
            : _testRewardedAdUnitId;

        _nativeAdUnitId =
        adConfig.nativeIos.isNotEmpty
            ? adConfig.nativeIos
            : _testNativeAdUnitId;

        _appOpenAdUnitId =
        adConfig.appOpenIos.isNotEmpty
            ? adConfig.appOpenIos
            : _testAppOpenAdUnitId;
      }

      print('[AdMob] Ad IDs loaded successfully.');
    } catch (e) {
      print(
        '[AdMob] Failed to load Ad IDs: $e',
      );

      _bannerAdUnitId = _testBannerAdUnitId;
      _interstitialAdUnitId =
          _testInterstitialAdUnitId;
      _rewardedAdUnitId = _testRewardedAdUnitId;
      _nativeAdUnitId = _testNativeAdUnitId;
      _appOpenAdUnitId =
          _testAppOpenAdUnitId;
    }
  }

  // ==================== AD UNIT GETTERS ====================

  String get bannerAdUnitId =>
      _bannerAdUnitId ?? _testBannerAdUnitId;

  String get interstitialAdUnitId =>
      _interstitialAdUnitId ??
          _testInterstitialAdUnitId;

  String get rewardedAdUnitId =>
      _rewardedAdUnitId ??
          _testRewardedAdUnitId;

  String get nativeAdUnitId =>
      _nativeAdUnitId ?? _testNativeAdUnitId;

  String get appOpenAdUnitId =>
      _appOpenAdUnitId ??
          _testAppOpenAdUnitId;

  // ==================== BANNER AD ====================

  BannerAd createBannerAd({
    required Function(Ad) onAdLoaded,
    required Function(
        Ad,
        LoadAdError,
        ) onAdFailedToLoad,
  }) {
    if (!_adsEnabled ||
        _userIsPremium ||
        !_bannerAdsEnabled) {
      return BannerAd(
        adUnitId: _testBannerAdUnitId,
        size: AdSize.banner,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (Ad ad) {},
          onAdFailedToLoad:
              (Ad ad, LoadAdError error) {
            ad.dispose();
          },
        ),
      );
    }

    return BannerAd(
      adUnitId: bannerAdUnitId,
      size: AdSize.banner,
      request: const AdRequest(),
      listener: BannerAdListener(
        onAdLoaded: onAdLoaded,
        onAdFailedToLoad:
        onAdFailedToLoad,
        onAdOpened: (Ad ad) {},
        onAdClosed: (Ad ad) {},
      ),
    );
  }

  // ==================== INTERSTITIAL ====================

  void _loadInterstitialAd() {
    if (!_adsEnabled ||
        _userIsPremium ||
        !_interstitialAdsEnabled) {
      return;
    }

    if (_isInterstitialReady) {
      return;
    }

    InterstitialAd.load(
      adUnitId: interstitialAdUnitId,
      request: const AdRequest(),
      adLoadCallback:
      InterstitialAdLoadCallback(
        onAdLoaded: (InterstitialAd ad) {
          _interstitialAd = ad;
          _isInterstitialReady = true;

          print(
            '[AdMob] Interstitial ad loaded.',
          );
        },
        onAdFailedToLoad:
            (LoadAdError error) {
          _interstitialAd = null;
          _isInterstitialReady = false;

          print(
            '[AdMob] Interstitial failed: $error',
          );
        },
      ),
    );
  }

  // ==================== AD TIMING ====================

  bool _canShowAd() {
    if (_appLaunchTime != null) {
      final timeSinceLaunch =
      DateTime.now()
          .difference(_appLaunchTime!);

      if (timeSinceLaunch.inSeconds <
          _initialDelaySeconds) {
        return false;
      }
    }

    if (_lastAdShown != null) {
      final timeSinceLastAd =
      DateTime.now()
          .difference(_lastAdShown!);

      if (timeSinceLastAd.inSeconds <
          _cooldownSeconds) {
        return false;
      }
    }

    return true;
  }

  // ==================== ACTION COUNTER ====================

  void incrementActionCounter() {
    _actionCounter++;

    print(
      '[AdMob] Action counter: '
          '$_actionCounter/$_interstitialTriggerCount',
    );
  }

  // ==================== SHOW INTERSTITIAL ====================

  void showInterstitialAd({
    Function()? onAdClosed,
  }) {
    print(
      '[AdMob] showInterstitialAd called',
    );

    if (!_adsEnabled ||
        !_interstitialAdsEnabled) {
      return;
    }

    if (_userIsPremium &&
        _hideAdsForPremium) {
      return;
    }

    if (!_canShowAd()) {
      return;
    }

    if (_actionCounter <
        _interstitialTriggerCount) {
      return;
    }

    if (_lastInterstitialAdShown != null) {
      final elapsed =
      DateTime.now().difference(
        _lastInterstitialAdShown!,
      );

      if (elapsed.inMinutes <
          _interstitialAdFrequencyMinutes) {
        return;
      }
    }

    if (_isInterstitialReady &&
        _interstitialAd != null) {
      final ad = _interstitialAd!;

      _interstitialAd = null;
      _isInterstitialReady = false;

      _lastInterstitialAdShown =
          DateTime.now();

      _lastAdShown = DateTime.now();

      _actionCounter = 0;

      ad.fullScreenContentCallback =
          FullScreenContentCallback(
            onAdDismissedFullScreenContent:
                (InterstitialAd ad) {
              ad.dispose();

              _loadInterstitialAd();

              onAdClosed?.call();
            },
            onAdFailedToShowFullScreenContent:
                (
                InterstitialAd ad,
                AdError error,
                ) {
              ad.dispose();

              _loadInterstitialAd();

              onAdClosed?.call();
            },
          );

      ad.show();
    } else {
      _loadInterstitialAd();
    }
  }

  // ==================== CONNECTION INTERSTITIAL ====================

  void showConnectionInterstitialAd({
    Function()? onAdClosed,
  }) {
    if (!_adsEnabled ||
        !_interstitialAdsEnabled) {
      return;
    }

    if (_userIsPremium &&
        _hideAdsForPremium) {
      return;
    }

    if (!_canShowAd()) {
      return;
    }

    if (_isInterstitialReady &&
        _interstitialAd != null) {
      final ad = _interstitialAd!;

      _interstitialAd = null;
      _isInterstitialReady = false;

      _lastInterstitialAdShown =
          DateTime.now();

      _lastAdShown = DateTime.now();

      _actionCounter = 0;

      ad.fullScreenContentCallback =
          FullScreenContentCallback(
            onAdDismissedFullScreenContent:
                (InterstitialAd ad) {
              ad.dispose();

              _loadInterstitialAd();

              onAdClosed?.call();
            },
            onAdFailedToShowFullScreenContent:
                (
                InterstitialAd ad,
                AdError error,
                ) {
              ad.dispose();

              _loadInterstitialAd();

              onAdClosed?.call();
            },
          );

      ad.show();
    } else {
      _loadInterstitialAd();
    }
  }

  // ==================== REWARDED AD ====================

  void _loadRewardedAd() {
    if (!_adsEnabled ||
        _userIsPremium ||
        !_rewardedAdsEnabled) {
      return;
    }

    if (_isRewardedReady) {
      return;
    }

    RewardedAd.load(
      adUnitId: rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback:
      RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _rewardedAd = ad;
          _isRewardedReady = true;

          print(
            '[AdMob] Rewarded ad loaded.',
          );
        },
        onAdFailedToLoad:
            (LoadAdError error) {
          _rewardedAd = null;
          _isRewardedReady = false;

          print(
            '[AdMob] Rewarded failed: $error',
          );
        },
      ),
    );
  }

  void showRewardedAd({
    required Function(
        AdWithoutView,
        RewardItem,
        ) onUserEarnedReward,
    Function()? onAdClosed,
  }) {
    if (!_adsEnabled ||
        _userIsPremium ||
        !_rewardedAdsEnabled) {
      return;
    }

    if (_isRewardedReady &&
        _rewardedAd != null) {
      final ad = _rewardedAd!;

      _rewardedAd = null;
      _isRewardedReady = false;

      ad.fullScreenContentCallback =
          FullScreenContentCallback(
            onAdDismissedFullScreenContent:
                (RewardedAd ad) {
              ad.dispose();

              _loadRewardedAd();

              onAdClosed?.call();
            },
            onAdFailedToShowFullScreenContent:
                (
                RewardedAd ad,
                AdError error,
                ) {
              ad.dispose();

              _loadRewardedAd();

              onAdClosed?.call();
            },
          );

      ad.show(
        onUserEarnedReward:
        onUserEarnedReward,
      );
    } else {
      _loadRewardedAd();
    }
  }

  // ==================== NATIVE AD ====================

  NativeAd createNativeAd({
    required Function(Ad) onAdLoaded,
    required Function(Ad, LoadAdError) onAdFailedToLoad,
  }) {
    // Check admin settings
    if (!_adsEnabled ||
        _userIsPremium ||
        !_nativeAdsEnabled) {
      return NativeAd(
        adUnitId: 'disabled',
        request: const AdRequest(),
        listener: NativeAdListener(
          onAdLoaded: (Ad ad) {},
          onAdFailedToLoad: (Ad ad, LoadAdError error) {
            onAdFailedToLoad(ad, error);
          },
        ),
        nativeTemplateStyle: NativeTemplateStyle(
          templateType: TemplateType.medium,
        ),
      );
    }
    NativeAd? _nativeAd;
    bool _isNativeReady = false;
    final nativeAd = NativeAd(
      adUnitId: nativeAdUnitId,
      request: const AdRequest(),
      listener: NativeAdListener(
        onAdLoaded: (Ad ad) {
          if (ad is NativeAd) {
            _nativeAd = ad;
            _isNativeReady = true;

            print('[AdMob] Native ad loaded.');

            if (areNativeAdsEnabled) {
              onAdLoaded(ad);
            }
          }
        },

        onAdFailedToLoad: (Ad ad, LoadAdError error) {
          print('[AdMob] Native ad failed: $error');

          _isNativeReady = false;

          ad.dispose();

          onAdFailedToLoad(ad, error);
        },

        onAdOpened: (Ad ad) {
          print('[AdMob] Native ad opened.');
        },

        onAdClosed: (Ad ad) {
          print('[AdMob] Native ad closed.');
        },
      ),

      nativeTemplateStyle: NativeTemplateStyle(
        templateType: TemplateType.medium,
      ),
    );

    return nativeAd;
  }

  // ==================== APP OPEN AD ====================

  void _loadAppOpenAd() {
    if (!_adsEnabled ||
        _userIsPremium ||
        !_appOpenAdsEnabled) {
      return;
    }

    if (_isAppOpenReady) {
      return;
    }

    AppOpenAd.load(
      adUnitId: appOpenAdUnitId,
      request: const AdRequest(),
      adLoadCallback:
      AppOpenAdLoadCallback(
        onAdLoaded: (AppOpenAd ad) {
          _appOpenAd = ad;
          _isAppOpenReady = true;

          print(
            '[AdMob] App Open ad loaded.',
          );
        },
        onAdFailedToLoad:
            (LoadAdError error) {
          _appOpenAd = null;
          _isAppOpenReady = false;

          print(
            '[AdMob] App Open failed: $error',
          );
        },
      ),
    );
  }

  void showAppOpenAd({
    Function()? onAdClosed,
  }) {
    print(
      '[AdMob] showAppOpenAd called',
    );

    if (!_adsEnabled ||
        _userIsPremium ||
        !_appOpenAdsEnabled) {
      return;
    }

    if (!_canShowAd()) {
      return;
    }

    if (_isShowingAppOpenAd) {
      return;
    }

    if (_lastAppOpenAdShown != null) {
      final elapsed =
      DateTime.now().difference(
        _lastAppOpenAdShown!,
      );

      if (elapsed.inHours <
          _appOpenAdFrequencyHours) {
        return;
      }
    }

    if (_isAppOpenReady &&
        _appOpenAd != null) {
      final ad = _appOpenAd!;

      _appOpenAd = null;
      _isAppOpenReady = false;

      _isShowingAppOpenAd = true;

      _lastAppOpenAdShown =
          DateTime.now();

      _lastAdShown =
          DateTime.now();

      ad.fullScreenContentCallback =
          FullScreenContentCallback(
            onAdDismissedFullScreenContent:
                (AppOpenAd ad) {
              _isShowingAppOpenAd = false;

              ad.dispose();

              _loadAppOpenAd();

              onAdClosed?.call();
            },
            onAdFailedToShowFullScreenContent:
                (
                AppOpenAd ad,
                AdError error,
                ) {
              _isShowingAppOpenAd = false;

              ad.dispose();

              _loadAppOpenAd();

              onAdClosed?.call();
            },
            onAdShowedFullScreenContent:
                (AppOpenAd ad) {},
          );

      ad.show();
    } else {
      _loadAppOpenAd();
    }
  }

  // ==================== PRELOAD ====================

  void preloadRewardedAd() {
    if (!_isRewardedReady) {
      _loadRewardedAd();
    }
  }

  void ensureRewardedAdReady() {
    if (!_isRewardedReady) {
      _loadRewardedAd();
    }
  }

  void ensureInterstitialAdReady() {
    if (!_isInterstitialReady) {
      _loadInterstitialAd();
    }
  }

  // ==================== READY GETTERS ====================

  bool get isInterstitialReady =>
      _isInterstitialReady &&
          _interstitialAdsEnabled &&
          _adsEnabled &&
          !_userIsPremium;

  bool get isRewardedReady =>
      _isRewardedReady &&
          _rewardedAdsEnabled &&
          _adsEnabled &&
          !_userIsPremium;

  bool get isNativeReady =>
      _isNativeReady &&
          _nativeAdsEnabled &&
          _adsEnabled &&
          !_userIsPremium;

  NativeAd? get nativeAd => _nativeAd;

  bool get isAppOpenReady {
    if (!_isAppOpenReady ||
        !_appOpenAdsEnabled ||
        !_adsEnabled ||
        _userIsPremium ||
        _isShowingAppOpenAd) {
      return false;
    }

    if (_lastAppOpenAdShown != null) {
      final elapsed =
      DateTime.now().difference(
        _lastAppOpenAdShown!,
      );

      if (elapsed.inHours <
          _appOpenAdFrequencyHours) {
        return false;
      }
    }

    return true;
  }

  bool get areBannerAdsEnabled =>
      _bannerAdsEnabled &&
          _adsEnabled &&
          !_userIsPremium;

  bool get areNativeAdsEnabled =>
      _nativeAdsEnabled &&
          _adsEnabled &&
          !_userIsPremium;

  // ==================== APP OPEN AVAILABILITY ====================

  String get nextAppOpenAdAvailability {
    if (!_appOpenAdsEnabled ||
        !_adsEnabled ||
        _userIsPremium) {
      return 'Disabled';
    }

    if (_lastAppOpenAdShown == null) {
      return 'Available now';
    }

    final elapsed =
    DateTime.now().difference(
      _lastAppOpenAdShown!,
    );

    final remainingMinutes =
        (_appOpenAdFrequencyHours * 60) -
            elapsed.inMinutes;

    if (remainingMinutes <= 0) {
      return 'Available now';
    }

    final hours =
        remainingMinutes ~/ 60;

    final minutes =
        remainingMinutes % 60;

    return 'Available in ${hours}h ${minutes}m';
  }

  // ==================== FREQUENCY RESET ====================

  void resetFrequencyRestrictions() {
    _lastAppOpenAdShown = null;
    _lastInterstitialAdShown = null;
    _lastAdShown = null;
  }

  // ==================== DISPOSE ====================

  void _disposeAllAds() {
    _bannerAd?.dispose();
    _bannerAd = null;

    _interstitialAd?.dispose();
    _interstitialAd = null;
    _isInterstitialReady = false;

    _rewardedAd?.dispose();
    _rewardedAd = null;
    _isRewardedReady = false;

    _nativeAd?.dispose();
    _nativeAd = null;
    _isNativeReady = false;

    _appOpenAd?.dispose();
    _appOpenAd = null;
    _isAppOpenReady = false;
  }

  void dispose() {
    _bannerAd?.dispose();
    _interstitialAd?.dispose();
    _rewardedAd?.dispose();

    _nativeAd?.dispose();
    _nativeAd = null;
    _isNativeReady = false;

    _appOpenAd?.dispose();
  }

  // ==================== PERIODIC PRELOADING ====================

  void _scheduleAdPreloading() {
    _preloadTimer?.cancel();

    _preloadTimer = Timer.periodic(
      const Duration(seconds: 30),
          (timer) {
        if (!_adsEnabled ||
            _userIsPremium) {
          return;
        }

        if (!_isInterstitialReady) {
          _loadInterstitialAd();
        }

        if (!_isRewardedReady) {
          _loadRewardedAd();
        }

        if (!_isAppOpenReady) {
          _loadAppOpenAd();
        }
      },
    );
  }

  // ==================== SERVER AD CONFIG ====================

  Future<AdConfig?> getAdConfig(
      dynamic serverId,
      ) async {
    final serverIdInt =
    serverId is String
        ? int.tryParse(serverId) ?? 0
        : serverId is int
        ? serverId
        : 0;

    try {
      if (_adConfigCache
          .containsKey(serverIdInt)) {
        return _adConfigCache[
        serverIdInt];
      }

      try {
        final response =
        await ApiService.instance
            .getAdConfig(
          serverIdInt,
        );

        if (response['success'] == true &&
            response['data'] != null) {
          final config =
          AdConfig.fromJson(
            response['data']
            as Map<String, dynamic>,
          );

          _adConfigCache[
          serverIdInt] = config;

          print(
            '✅ Ad config fetched for '
                'server $serverIdInt',
          );

          return config;
        }

        print(
          '❌ Failed to fetch ad config: '
              '${response['message']}',
        );

        return _getDefaultAdConfig(
          serverIdInt,
        );
      } catch (e) {
        print(
          '❌ Network error fetching '
              'ad config: $e',
        );

        return _getDefaultAdConfig(
          serverIdInt,
        );
      }
    } catch (e) {
      print(
        '❌ Error fetching ad config: $e',
      );

      return _getDefaultAdConfig(
        serverIdInt,
      );
    }
  }

  // ==================== DEFAULT SERVER CONFIG ====================

  AdConfig _getDefaultAdConfig(
      int serverId,
      ) {
    return AdConfig(
      serverId: serverId,
      serverName: 'Default Server',
      premiumUnlockDuration: 20,
      ads: [
        AdReward(
          id: 1,
          duration: 5,
          durationSeconds: 300,
        ),
        AdReward(
          id: 2,
          duration: 10,
          durationSeconds: 600,
        ),
        AdReward(
          id: 3,
          duration: 20,
          durationSeconds: 1200,
        ),
      ],
    );
  }

  // ==================== CACHE ====================

  void clearAdConfigCache() {
    _adConfigCache.clear();
  }

  void clearServerAdConfigCache(
      dynamic serverId,
      ) {
    final serverIdInt =
    serverId is String
        ? int.tryParse(serverId) ?? 0
        : serverId is int
        ? serverId
        : 0;

    _adConfigCache.remove(
      serverIdInt,
    );
  }

  // ==================== AD DURATION ====================

  int getAdDurationSeconds(
      dynamic serverId,
      int adIndex,
      ) {
    final serverIdInt =
    serverId is String
        ? int.tryParse(serverId) ?? 0
        : serverId is int
        ? serverId
        : 0;

    final config =
    _adConfigCache[serverIdInt];

    if (config != null &&
        adIndex >= 0 &&
        adIndex < config.ads.length) {
      return config
          .ads[adIndex]
          .durationSeconds;
    }

    const defaults = [
      300,
      600,
      1200,
    ];

    if (adIndex >= 0 &&
        adIndex < defaults.length) {
      return defaults[adIndex];
    }

    return 300;
  }

  // ==================== PREMIUM UNLOCK ====================

  Future<int>
  getPremiumUnlockDurationSeconds(
      dynamic serverId,
      ) async {
    final config =
    await getAdConfig(
      serverId,
    );

    if (config != null) {
      return config
          .premiumUnlockDuration *
          60;
    }

    return 1200;
  }
}

// ==================== CACHED AD CONFIG ====================

class _AdConfigFromCache {
  final Map<String, dynamic> _data;

  _AdConfigFromCache(
      this._data,
      );

  String get bannerAndroid =>
      _data['banner_android'] ?? '';

  String get bannerIos =>
      _data['banner_ios'] ?? '';

  String get interstitialAndroid =>
      _data['interstitial_android'] ?? '';

  String get interstitialIos =>
      _data['interstitial_ios'] ?? '';

  String get rewardedAndroid =>
      _data['rewarded_android'] ?? '';

  String get rewardedIos =>
      _data['rewarded_ios'] ?? '';

  String get nativeAndroid =>
      _data['native_android'] ?? '';

  String get nativeIos =>
      _data['native_ios'] ?? '';

  String get appOpenAndroid =>
      _data['app_open_android'] ?? '';

  String get appOpenIos =>
      _data['app_open_ios'] ?? '';
}