import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ============================================================
// LEVELPLAY SERVICE
// ============================================================
// Unity LevelPlay / IronSource ad service.
//
// Supports:
//   • Rewarded Ads
//   • Interstitial Ads
//   • VPN Disconnect Interstitial
//
// Interstitial flow:
//
//   VPN disconnected
//        ↓
//   check isAdReady()
//        ↓
//   READY → show immediately
//        ↓
//   NOT READY → loadAd()
//        ↓
//   onAdLoaded()
//        ↓
//   show automatically
//
// Premium users do not receive ads.
// ============================================================


// ============================================================
// REWARDED CALLBACKS
// ============================================================

class LevelPlayRewardedCallbacks {
  final VoidCallback? onOpened;
  final VoidCallback? onClosed;

  final void Function(
      String rewardName,
      int rewardAmount,
      )? onRewarded;

  final void Function(
      String errorMessage,
      )? onShowFailed;

  final void Function(
      bool available,
      )? onAvailabilityChanged;

  const LevelPlayRewardedCallbacks({
    this.onOpened,
    this.onClosed,
    this.onRewarded,
    this.onShowFailed,
    this.onAvailabilityChanged,
  });
}


// ============================================================
// REWARDED LISTENER
// ============================================================

class _RewardedListener
    implements LevelPlayRewardedAdListener {
  final LevelPlayService _service;

  _RewardedListener(this._service);

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    debugPrint(
      '[LevelPlay] ✅ Rewarded ad loaded: ${adInfo.adId}',
    );

    _service._isRewardedVideoAvailable = true;

    _service
        ._rewardedCallbacks
        ?.onAvailabilityChanged
        ?.call(true);
  }

  @override
  void onAdLoadFailed(
      LevelPlayAdError error,
      ) {
    debugPrint(
      '[LevelPlay] ❌ Rewarded load failed: '
          '${error.errorCode} – ${error.errorMessage}',
    );

    _service._isRewardedVideoAvailable = false;

    _service
        ._rewardedCallbacks
        ?.onAvailabilityChanged
        ?.call(false);
  }

  @override
  void onAdDisplayed(
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] 🎬 Rewarded ad displayed',
    );

    _service
        ._rewardedCallbacks
        ?.onOpened
        ?.call();
  }

  @override
  void onAdDisplayFailed(
      LevelPlayAdError error,
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] ❌ Rewarded display failed: '
          '${error.errorCode} – ${error.errorMessage}',
    );

    _service._isRewardedVideoAvailable = false;

    _service
        ._rewardedCallbacks
        ?.onShowFailed
        ?.call(
      '${error.errorCode}: ${error.errorMessage}',
    );

    // Preload next rewarded ad.
    _service._rewardedAd?.loadAd();
  }

  @override
  void onAdClosed(
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] 🔒 Rewarded ad closed',
    );

    _service._isRewardedVideoAvailable = false;

    _service
        ._rewardedCallbacks
        ?.onClosed
        ?.call();

    // Preload next rewarded ad.
    _service._rewardedAd?.loadAd();
  }

  @override
  void onAdClicked(
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] 🖱️ Rewarded ad clicked',
    );
  }

  @override
  void onAdInfoChanged(
      LevelPlayAdInfo adInfo,
      ) {}

  @override
  void onAdRewarded(
      LevelPlayReward reward,
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] 🎁 Rewarded! '
          '${reward.amount} ${reward.name}',
    );

    _service
        ._rewardedCallbacks
        ?.onRewarded
        ?.call(
      reward.name,
      reward.amount,
    );
  }
}


// ============================================================
// INTERSTITIAL LISTENER
// ============================================================

class _InterstitialListener
    implements LevelPlayInterstitialAdListener {
  final LevelPlayService _service;

  _InterstitialListener(this._service);

  @override
  void onAdLoaded(
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] ✅ Interstitial loaded: '
          '${adInfo.adId}',
    );

    _service._isInterstitialReady = true;

    // Show a queued VPN transition interstitial immediately after load.
    final pendingPlacement = _service._pendingInterstitialPlacement;
    if (pendingPlacement != null) {
      _service._pendingInterstitialPlacement = null;
      _service._pendingDisconnectInterstitial = false;
      final stillConnected = _service.vpnConnectedCheck?.call() ?? true;
      if (pendingPlacement == 'vpn_connected' && !stillConnected) {
        debugPrint(
          '[LevelPlay] 🚫 Dropped queued interstitial: VPN is no longer connected',
        );
      } else {
        debugPrint('[LevelPlay] 🚦 Showing queued interstitial: $pendingPlacement');
        Future.microtask(() async {
          await _service.showInterstitial(
            placementName: pendingPlacement,
            bypassTiming: true,
          );
        });
      }
    } else if (_service._pendingDisconnectInterstitial) {
      _service._pendingDisconnectInterstitial = false;
      Future.microtask(() async {
        await _service.showInterstitial(
          placementName: 'vpn_disconnect',
          bypassTiming: true,
        );
      });
    }
  }

  @override
  void onAdLoadFailed(
      LevelPlayAdError error,
      ) {
    debugPrint(
      '[LevelPlay] ❌ Interstitial load failed: '
          '${error.errorCode} – ${error.errorMessage}',
    );

    _service._isInterstitialReady = false;

    // Do not keep a failed request pending.
    _service._pendingDisconnectInterstitial = false;
    _service._pendingInterstitialPlacement = null;
  }

  @override
  void onAdInfoChanged(
      LevelPlayAdInfo adInfo,
      ) {}

  @override
  void onAdDisplayed(
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] 🎬 Interstitial displayed',
    );

    _service._lastInterstitialShownAt = DateTime.now();
    _service._actionsSinceLastInterstitial = 0;
  }

  @override
  void onAdDisplayFailed(
      LevelPlayAdError error,
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] ❌ Interstitial display failed: '
          '${error.errorCode} – ${error.errorMessage}',
    );

    _service._isInterstitialReady = false;

    _service._pendingDisconnectInterstitial = false;

    // Preload next interstitial.
    _service._interstitialAd?.loadAd();
  }

  @override
  void onAdClicked(
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] 🖱️ Interstitial clicked',
    );
  }

  @override
  void onAdClosed(
      LevelPlayAdInfo adInfo,
      ) {
    debugPrint(
      '[LevelPlay] 🔒 Interstitial closed',
    );

    _service._isInterstitialReady = false;

    _service
        ._interstitialClosedCallback
        ?.call();

    // Preload next interstitial.
    _service._interstitialAd?.loadAd();
  }
}


// ============================================================
// LEVELPLAY INIT LISTENER
// ============================================================

class _InitListener
    implements LevelPlayInitListener {
  final LevelPlayService _service;

  _InitListener(this._service);

  @override
  void onInitFailed(
      LevelPlayInitError error,
      ) {
    debugPrint(
      '❌ [LevelPlay] Init failed: '
          '${error.errorCode} – ${error.errorMessage}',
    );

    _service._initialized = false;
  }

  @override
  void onInitSuccess(
      LevelPlayConfiguration configuration,
      ) {
    debugPrint(
      '✅ [LevelPlay] Init success',
    );

    _service._initialized = true;

    // Start loading ads.
    _service._preloadAds();
  }
}


// ============================================================
// LEVELPLAY SERVICE
// ============================================================

class LevelPlayService {
  // ==========================================================
  // SINGLETON
  // ==========================================================

  static final LevelPlayService _instance =
  LevelPlayService._internal();

  factory LevelPlayService() {
    return _instance;
  }

  LevelPlayService._internal();

  static LevelPlayService get instance {
    return _instance;
  }


  // ==========================================================
  // APP KEYS
  // ==========================================================

  static const String _fallbackAndroidAppKey =
      '275189f1d';

  static const String _fallbackIosAppKey =
      'YOUR_IOS_LEVELPLAY_APP_KEY';


  // ==========================================================
  // AD UNIT IDS
  // ==========================================================

  static const String _fallbackRewardedUnitId =
      't2hf8dmp8kxo8hqp';

  static const String _fallbackInterstitialUnitId =
      'ecq5j5znboq5x54v';

  static const String _fallbackBannerUnitId =
      'hqe7skeqt5vp9csp';

  static const String _fallbackNativeUnitId =
      '52rdvpmf716zst8k';

  static const String _fallbackMrecUnitId =
      'y7so1eclk7uwq5fw';


  // ==========================================================
  // OTHER LEVELPLAY IDS
  // ==========================================================
  //
  // Native:
  // 52rdvpmf716zst8k
  //
  // Banner:
  // hqe7skeqt5vp9csp
  //
  // ==========================================================


  // ==========================================================
  // STATE
  // ==========================================================

  bool _initialized = false;

  bool _userIsPremium = false;

  // ==========================================================
  // INTERSTITIAL TIMING (Admin > Ads Settings > Ad Display Timing)
  // All durations are in SECONDS. Defaults keep the old behaviour
  // (no extra limits) until the settings arrive from the server.
  // ==========================================================

  /// Admin > Ads Settings: when every ad network is switched OFF there
  /// ("none"), passive ads (interstitial, banner, native, MREC) are hidden.
  /// Rewarded videos stay available because users start them on purpose
  /// (extra free time, unlock a server).
  bool _adsEnabledByAdmin = true;

  bool get adsEnabledByAdmin => _adsEnabledByAdmin;

  void setAdsEnabledByAdmin(bool enabled) {
    _adsEnabledByAdmin = enabled;
    debugPrint('[LevelPlay] Admin ads switch: ${enabled ? 'ON' : 'OFF'}');
  }

  final DateTime _launchedAt = DateTime.now();

  int _adInitialDelaySeconds = 0;

  int _adCooldownSeconds = 0;

  int _adTriggerCount = 1;

  DateTime? _lastInterstitialShownAt;

  int _actionsSinceLastInterstitial = 0;

  /// Called with the values from /api/v1/get-ad-settings.
  void applyAdTiming({
    int? initialDelaySeconds,
    int? cooldownSeconds,
    int? triggerCount,
  }) {
    if (initialDelaySeconds != null) {
      _adInitialDelaySeconds = initialDelaySeconds.clamp(0, 86400).toInt();
    }
    if (cooldownSeconds != null) {
      _adCooldownSeconds = cooldownSeconds.clamp(0, 86400).toInt();
    }
    if (triggerCount != null) {
      _adTriggerCount = triggerCount.clamp(1, 100).toInt();
    }
    debugPrint(
      '[LevelPlay] ⏱️ Ad timing: initial delay ${_adInitialDelaySeconds}s, '
      'cooldown ${_adCooldownSeconds}s, every $_adTriggerCount action(s)',
    );
  }

  /// Counts one user action (connect, disconnect, speed test...) and says
  /// whether an interstitial may be shown now. All three rules must pass:
  /// initial delay since app launch, cooldown since the last interstitial,
  /// and at least N actions since the last interstitial.
  bool _interstitialAllowedNow(String? placement) {
    _actionsSinceLastInterstitial++;
    final now = DateTime.now();

    final sinceLaunch = now.difference(_launchedAt).inSeconds;
    if (sinceLaunch < _adInitialDelaySeconds) {
      debugPrint(
        '[LevelPlay] ⏳ Interstitial skipped ($placement): initial delay '
        '$sinceLaunch/${_adInitialDelaySeconds}s',
      );
      return false;
    }

    final last = _lastInterstitialShownAt;
    if (last != null) {
      final sinceLast = now.difference(last).inSeconds;
      if (sinceLast < _adCooldownSeconds) {
        debugPrint(
          '[LevelPlay] ⏳ Interstitial skipped ($placement): cooldown '
          '$sinceLast/${_adCooldownSeconds}s',
        );
        return false;
      }
    }

    if (_actionsSinceLastInterstitial < _adTriggerCount) {
      debugPrint(
        '[LevelPlay] ⏳ Interstitial skipped ($placement): action '
        '$_actionsSinceLastInterstitial/$_adTriggerCount',
      );
      return false;
    }

    return true;
  }

  bool _isRewardedVideoAvailable = false;

  bool _isInterstitialReady = false;

  // ==========================================================
  // IMPORTANT
  // ==========================================================
  // Used when VPN disconnects while interstitial is loading.
  //
  // Example:
  //
  // VPN disconnected
  //      ↓
  // Ad not ready
  //      ↓
  // loadAd()
  //      ↓
  // pending = true
  //      ↓
  // onAdLoaded()
  //      ↓
  // show ad
  // ==========================================================

  bool _pendingDisconnectInterstitial = false;

  // If a connect/disconnect transition happens while the interstitial is
  // loading, remember the placement and show it as soon as the ad loads.
  String? _pendingInterstitialPlacement;


  // ==========================================================
  // RUNTIME KEYS
  // ==========================================================

  String _androidAppKey =
      _fallbackAndroidAppKey;

  String _iosAppKey =
      _fallbackIosAppKey;

  String _rewardedAdUnitId =
      _fallbackRewardedUnitId;

  String _interstitialAdUnitId =
      _fallbackInterstitialUnitId;

  String _bannerAdUnitId = _fallbackBannerUnitId;

  String _nativeAdUnitId = _fallbackNativeUnitId;

  String _mrecAdUnitId = _fallbackMrecUnitId;

  /// Set by VpnService. Used to drop a queued 'vpn_connected' interstitial
  /// if the VPN is no longer connected when the ad finally loads.
  bool Function()? vpnConnectedCheck;


  // ==========================================================
  // MADU AD OBJECTS
  // ==========================================================

  LevelPlayRewardedAd? _rewardedAd;

  LevelPlayInterstitialAd? _interstitialAd;


  // ==========================================================
  // CALLBACKS
  // ==========================================================

  LevelPlayRewardedCallbacks?
  _rewardedCallbacks;

  VoidCallback?
  _interstitialClosedCallback;


  // ==========================================================
  // GETTERS
  // ==========================================================

  bool get isInitialized {
    return _initialized;
  }

  bool get isRewardedVideoAvailable {
    return _isRewardedVideoAvailable;
  }

  bool get isInterstitialReady {
    return _isInterstitialReady;
  }

  String get bannerAdUnitId => _bannerAdUnitId;

  String get nativeAdUnitId => _nativeAdUnitId;

  String get mrecAdUnitId => _mrecAdUnitId;


  // ==========================================================
  // INITIALIZE
  // ==========================================================

  Future<void> initialize({
    String? androidAppKey,
    String? iosAppKey,
    String? rewardedAdUnitId,
    String? interstitialAdUnitId,
    String? bannerAdUnitId,
    String? nativeAdUnitId,
    String? mrecAdUnitId,
  }) async {
    try {
      // ------------------------------------------------------
      // Runtime config
      // ------------------------------------------------------

      if (androidAppKey != null &&
          androidAppKey.isNotEmpty) {
        _androidAppKey = androidAppKey;
      }

      if (iosAppKey != null &&
          iosAppKey.isNotEmpty) {
        _iosAppKey = iosAppKey;
      }

      if (rewardedAdUnitId != null &&
          rewardedAdUnitId.isNotEmpty) {
        _rewardedAdUnitId = rewardedAdUnitId;
      }

      if (interstitialAdUnitId != null &&
          interstitialAdUnitId.isNotEmpty) {
        _interstitialAdUnitId =
            interstitialAdUnitId;
      }

      if (bannerAdUnitId != null && bannerAdUnitId.isNotEmpty) {
        _bannerAdUnitId = bannerAdUnitId;
      }

      if (nativeAdUnitId != null && nativeAdUnitId.isNotEmpty) {
        _nativeAdUnitId = nativeAdUnitId;
      }

      if (mrecAdUnitId != null && mrecAdUnitId.isNotEmpty) {
        _mrecAdUnitId = mrecAdUnitId;
      }


      // ------------------------------------------------------
      // Premium check
      // ------------------------------------------------------

      final prefs =
      await SharedPreferences.getInstance();

      _userIsPremium =
          prefs.getBool('is_premium') ?? false;

      if (_userIsPremium) {
        debugPrint(
          '[LevelPlay] 👑 User is premium - '
              'skipping initialization',
        );

        return;
      }


      // ------------------------------------------------------
      // Adapter debug
      // ------------------------------------------------------

      if (kDebugMode) {
        await LevelPlay.setAdaptersDebug(true);
      }


      // ------------------------------------------------------
      // Rewarded object
      // ------------------------------------------------------

      _rewardedAd =
          LevelPlayRewardedAd(
            adUnitId: _rewardedAdUnitId,
          );

      _rewardedAd!.setListener(
        _RewardedListener(this),
      );


      // ------------------------------------------------------
      // Interstitial object
      // ------------------------------------------------------

      _interstitialAd =
          LevelPlayInterstitialAd(
            adUnitId: _interstitialAdUnitId,
          );

      _interstitialAd!.setListener(
        _InterstitialListener(this),
      );


      // ------------------------------------------------------
      // Platform app key
      // ------------------------------------------------------

      final activeAppKey =
      Platform.isAndroid
          ? _androidAppKey
          : _iosAppKey;


      debugPrint(
        '[LevelPlay] 🚀 Initializing SDK...',
      );

      debugPrint(
        '[LevelPlay] Platform: '
            '${Platform.isAndroid ? "Android" : "iOS"}',
      );


      // ------------------------------------------------------
      // LevelPlay init
      // ------------------------------------------------------

      await LevelPlay.init(
        initRequest:
        LevelPlayInitRequest
            .builder(activeAppKey)
            .build(),
        initListener:
        _InitListener(this),
      );
    } catch (e, stackTrace) {
      debugPrint(
        '❌ [LevelPlay] Initialization error: $e',
      );

      debugPrint(
        '[LevelPlay] StackTrace: $stackTrace',
      );
    }
  }


  // ==========================================================
  // PRELOAD ADS
  // ==========================================================

  void _preloadAds() {
    if (!_initialized) {
      debugPrint(
        '[LevelPlay] ⚠️ Cannot preload - '
            'SDK not initialized',
      );

      return;
    }

    if (_userIsPremium) {
      debugPrint(
        '[LevelPlay] 👑 Premium user - '
            'skipping preload',
      );

      return;
    }

    debugPrint(
      '[LevelPlay] 📥 Preloading rewarded ad...',
    );

    _rewardedAd?.loadAd();

    debugPrint(
      '[LevelPlay] 📥 Preloading interstitial...',
    );

    _interstitialAd?.loadAd();
  }


  // ==========================================================
  // REFRESH PREMIUM STATUS
  // ==========================================================

  Future<void> refreshPremiumStatus() async {
    try {
      final prefs =
      await SharedPreferences.getInstance();

      _userIsPremium =
          prefs.getBool('is_premium') ?? false;

      debugPrint(
        '[LevelPlay] Premium status: '
            '$_userIsPremium',
      );
    } catch (e) {
      debugPrint(
        '[LevelPlay] Premium status error: $e',
      );
    }
  }


  // ==========================================================
  // REWARDED CALLBACKS
  // ==========================================================

  void setRewardedCallbacks(
      LevelPlayRewardedCallbacks callbacks,
      ) {
    _rewardedCallbacks = callbacks;
  }


  void clearRewardedCallbacks() {
    _rewardedCallbacks = null;
  }


  // ==========================================================
  // CHECK REWARDED AVAILABILITY
  // ==========================================================

  Future<bool>
  checkRewardedVideoAvailable() async {
    if (!_initialized ||
        _rewardedAd == null) {
      return false;
    }

    if (_userIsPremium) {
      return false;
    }

    try {
      final available =
      await _rewardedAd!.isAdReady();

      _isRewardedVideoAvailable =
          available;

      _rewardedCallbacks
          ?.onAvailabilityChanged
          ?.call(available);

      debugPrint(
        '[LevelPlay] Rewarded ready: '
            '$available',
      );

      return available;
    } catch (e) {
      debugPrint(
        '[LevelPlay] Rewarded readiness error: $e',
      );

      _isRewardedVideoAvailable = false;

      return false;
    }
  }


  // ==========================================================
  // SHOW REWARDED VIDEO
  // ==========================================================

  Future<void> showRewardedVideo({
    String? placementName,
  }) async {
    if (!_initialized ||
        _rewardedAd == null) {
      debugPrint(
        '[LevelPlay] ❌ Rewarded not initialized',
      );

      return;
    }

    if (_userIsPremium) {
      debugPrint(
        '[LevelPlay] 👑 Premium user - '
            'rewarded skipped',
      );

      return;
    }

    try {
      final available =
      await _rewardedAd!.isAdReady();

      debugPrint(
        '[LevelPlay] Rewarded actual ready: '
            '$available',
      );

      if (!available) {
        debugPrint(
          '[LevelPlay] ❌ Rewarded video not available',
        );

        _isRewardedVideoAvailable = false;

        _rewardedCallbacks
            ?.onShowFailed
            ?.call(
          'No ad available',
        );

        // Try to load next ad.
        await _rewardedAd!.loadAd();

        return;
      }

      _isRewardedVideoAvailable = true;

      debugPrint(
        '[LevelPlay] 🎬 Showing rewarded video',
      );

      await _rewardedAd!.showAd(
        placementName:
        placementName ?? '',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[LevelPlay] ❌ Rewarded show error: $e',
      );

      debugPrint(
        '[LevelPlay] StackTrace: $stackTrace',
      );

      _isRewardedVideoAvailable = false;

      _rewardedCallbacks
          ?.onShowFailed
          ?.call(
        e.toString(),
      );
    }
  }


  // ==========================================================
  // INTERSTITIAL CLOSED CALLBACK
  // ==========================================================

  void setInterstitialClosedCallback(
      VoidCallback? onClosed,
      ) {
    _interstitialClosedCallback =
        onClosed;
  }


  // ==========================================================
  // CHECK INTERSTITIAL READY
  // ==========================================================

  Future<bool>
  checkInterstitialReady() async {
    if (!_initialized ||
        _interstitialAd == null) {
      return false;
    }

    if (_userIsPremium) {
      return false;
    }

    try {
      final ready =
      await _interstitialAd!.isAdReady();

      _isInterstitialReady = ready;

      debugPrint(
        '[LevelPlay] Interstitial actual ready: '
            '$ready',
      );

      return ready;
    } catch (e) {
      debugPrint(
        '[LevelPlay] Interstitial readiness error: $e',
      );

      _isInterstitialReady = false;

      return false;
    }
  }


  // ==========================================================
  // SHOW NORMAL INTERSTITIAL
  // ==========================================================

  Future<void> showInterstitial({
    String? placementName,
    bool bypassTiming = false,
  }) async {
    if (!_initialized) {
      debugPrint(
        '[LevelPlay] ❌ Not initialized',
      );

      return;
    }

    if (_interstitialAd == null) {
      debugPrint(
        '[LevelPlay] ❌ Interstitial object is null',
      );

      return;
    }

    if (_userIsPremium) {
      debugPrint(
        '[LevelPlay] 👑 Premium user - '
            'interstitial skipped',
      );

      return;
    }

    // Admin timing rules (a queued ad that was already approved bypasses).
    if (!_adsEnabledByAdmin) {
      debugPrint('[LevelPlay] Interstitial skipped: ads switched OFF by admin');
      return;
    }

    if (!bypassTiming && !_interstitialAllowedNow(placementName)) {
      return;
    }

    try {
      // ------------------------------------------------------
      // Always use actual LevelPlay readiness.
      // ------------------------------------------------------

      final ready =
      await _interstitialAd!.isAdReady();

      debugPrint(
        '[LevelPlay] Interstitial actual ready: '
            '$ready',
      );

      if (!ready) {
        _isInterstitialReady = false;

        // Queue the placement so the VPN transition still gets its
        // interstitial once LevelPlay finishes loading the next ad.
        _pendingInterstitialPlacement = placementName ?? 'vpn_transition';

        debugPrint(
          '[LevelPlay] ⏳ Interstitial not ready - queued '
              '${_pendingInterstitialPlacement}',
        );

        await _interstitialAd!.loadAd();
        return;
      }

      _isInterstitialReady = true;

      debugPrint(
        '[LevelPlay] 🎬 Showing interstitial '
            '| placement: '
            '${placementName ?? "none"}',
      );

      await _interstitialAd!.showAd(
        placementName:
        placementName ?? '',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[LevelPlay] ❌ Interstitial show error: $e',
      );

      debugPrint(
        '[LevelPlay] StackTrace: $stackTrace',
      );

      _isInterstitialReady = false;
    }
  }


  // ==========================================================
  // VPN DISCONNECT INTERSTITIAL
  // ==========================================================
  //
  // THIS IS THE IMPORTANT METHOD FOR YOUR HOME SCREEN.
  //
  // If ad is ready:
  //
  //     show immediately
  //
  // If ad is NOT ready:
  //
  //     set pending = true
  //     load ad
  //     onAdLoaded()
  //     automatically show
  //
  // ==========================================================

  Future<void>
  showDisconnectInterstitial() async {
    if (!_initialized) {
      debugPrint(
        '[LevelPlay] ❌ Disconnect ad: '
            'SDK not initialized',
      );

      return;
    }

    if (_userIsPremium) {
      debugPrint(
        '[LevelPlay] 👑 Disconnect ad skipped - '
            'premium user',
      );

      return;
    }

    if (!_adsEnabledByAdmin) {
      return;
    }

    if (!_interstitialAllowedNow('vpn_disconnect')) {
      return;
    }

    if (_interstitialAd == null) {
      debugPrint(
        '[LevelPlay] ❌ Disconnect ad: '
            'interstitial is null',
      );

      return;
    }

    try {
      // ------------------------------------------------------
      // IMPORTANT:
      // Check actual LevelPlay state.
      // ------------------------------------------------------

      final ready =
      await _interstitialAd!.isAdReady();

      debugPrint(
        '[LevelPlay] 🔍 Disconnect interstitial ready: '
            '$ready',
      );

      // ------------------------------------------------------
      // READY
      // ------------------------------------------------------

      if (ready) {
        _isInterstitialReady = true;

        _pendingDisconnectInterstitial =
        false;

        debugPrint(
          '[LevelPlay] 🎬 Showing disconnect '
              'interstitial NOW',
        );

        await _interstitialAd!.showAd(
          placementName:
          'vpn_disconnect',
        );

        return;
      }

      // ------------------------------------------------------
      // NOT READY
      // ------------------------------------------------------

      _isInterstitialReady = false;

      _pendingDisconnectInterstitial =
      true;

      debugPrint(
        '[LevelPlay] ⏳ Disconnect interstitial '
            'not ready',
      );

      debugPrint(
        '[LevelPlay] 📥 Loading interstitial '
            'for disconnect...',
      );

      await _interstitialAd!.loadAd();
    } catch (e, stackTrace) {
      _pendingDisconnectInterstitial =
      false;

      debugPrint(
        '[LevelPlay] ❌ Disconnect interstitial '
            'error: $e',
      );

      debugPrint(
        '[LevelPlay] StackTrace: $stackTrace',
      );
    }
  }
}
