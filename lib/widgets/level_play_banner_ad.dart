import 'dart:async';

import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import '../core/services/level_play_service.dart';

/// A widget that loads and displays a LevelPlay (IronSource) banner ad using
/// the new MADU [LevelPlayBannerAdView] widget API.
///
/// Pass your banner ad unit ID from the LevelPlay dashboard.
///
/// Example usage (bottom of scaffold body):
/// ```dart
/// Column(
///   children: [
///     Expanded(child: /* your content */),
///     LevelPlayBannerAd(adUnitId: 'your_banner_ad_unit_id'),
///   ],
/// )
/// ```
class LevelPlayBannerAd extends StatefulWidget {
  /// Banner ad unit ID from the LevelPlay dashboard.
  final String adUnitId;

  /// Banner ad size. Defaults to [LevelPlayAdSize.BANNER] (320×50).
  final LevelPlayAdSize adSize;

  /// Optional placement name configured in the LevelPlay dashboard.
  final String? placementName;

  /// Called when the banner fails to load/display so the parent can
  /// collapse its own container (no empty coloured strip left behind).
  final VoidCallback? onFailed;

  LevelPlayBannerAd({
    super.key,
    required this.adUnitId,
    LevelPlayAdSize? adSize,
    this.placementName,
    this.onFailed,
  }) : adSize = adSize ?? LevelPlayAdSize.BANNER;

  @override
  State<LevelPlayBannerAd> createState() => _LevelPlayBannerAdState();
}

class _LevelPlayBannerAdState extends State<LevelPlayBannerAd>
    implements LevelPlayBannerAdViewListener {
  // GlobalKey is required by LevelPlayBannerAdView to call loadAd() / destroy()
  late final GlobalKey<LevelPlayBannerAdViewState> _bannerKey;
  bool _failed = false;
  bool _loaded = false;
  int _retries = 0;
  Timer? _loadTimeout;
  Timer? _retryTimer;

  /// Extra load attempts after the network answers "no fill / load failed".
  static const int _maxRetries = 3;

  /// Time for SDK start-up + the first network answer.
  static const Duration _firstLoadWindow = Duration(seconds: 15);

  /// Time for each retry before giving up.
  static const Duration _retryWindow = Duration(seconds: 10);

  /// Pause before a retry.
  static const Duration _retryDelay = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _bannerKey = GlobalKey<LevelPlayBannerAdViewState>();

    if (widget.adUnitId.isEmpty) {
      // Admin panel has no ad unit for this slot: collapse, nothing to load.
      _failed = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onFailed?.call();
      });
      return;
    }

    _loadTimeout = Timer(_firstLoadWindow, _onLoadTimeout);
  }

  void _onLoadTimeout() {
    if (!mounted || _loaded || _failed) return;
    _giveUp();
  }

  void _giveUp() {
    _loadTimeout?.cancel();
    _retryTimer?.cancel();
    if (!mounted || _failed) return;
    setState(() => _failed = true);
    widget.onFailed?.call();
  }

  void _scheduleRetry() {
    if (!mounted || _failed) return;
    if (_retries >= _maxRetries) {
      _giveUp();
      return;
    }
    _retries++;
    _loaded = false;
    _loadTimeout?.cancel();
    _retryTimer?.cancel();
    _retryTimer = Timer(_retryDelay, () {
      if (!mounted || _failed || _loaded) return;
      _loadTimeout = Timer(_retryWindow, _onLoadTimeout);
      _bannerKey.currentState?.loadAd();
    });
  }

  @override
  void dispose() {
    _loadTimeout?.cancel();
    _retryTimer?.cancel();
    _bannerKey.currentState?.destroy();
    super.dispose();
  }

  void _onPlatformViewCreated() {
    _loadWhenInitialized();
  }

  void _loadWhenInitialized([int attempts = 0]) {
    if (!mounted || _failed) return;
    if (LevelPlayService.instance.isInitialized) {
      _bannerKey.currentState?.loadAd();
      return;
    }

    // LevelPlay initialization completes through a native callback. A banner
    // platform view can be created first, so wait for that callback instead of
    // silently abandoning the only load request.
    if (attempts < 120) {
      Future.delayed(const Duration(milliseconds: 250), () {
        _loadWhenInitialized(attempts + 1);
      });
    }
  }

  // ---- LevelPlayBannerAdViewListener ----

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    debugPrint('[LevelPlayBannerAd] Loaded: ${adInfo.adId}');
    _loaded = true;
    _loadTimeout?.cancel();
    _retryTimer?.cancel();
    if (mounted) setState(() {});
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    debugPrint(
      '[LevelPlayBannerAd] Load failed (try ${_retries + 1}): '
      '${error.errorCode} – ${error.errorMessage}',
    );
    _scheduleRetry();
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) {
    debugPrint(
      '[LevelPlayBannerAd] Display failed: '
      '${error.errorCode} – ${error.errorMessage}',
    );
    _scheduleRetry();
  }

  @override
  void onAdClicked(LevelPlayAdInfo adInfo) {}

  @override
  void onAdExpanded(LevelPlayAdInfo adInfo) {}

  @override
  void onAdCollapsed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdLeftApplication(LevelPlayAdInfo adInfo) {}

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    if (_failed || !LevelPlayService.instance.adsEnabledByAdmin) {
      return const SizedBox.shrink();
    }

    return SizedBox(
      height: widget.adSize.height.toDouble(),
      child: LevelPlayBannerAdView(
        key: _bannerKey,
        adUnitId: widget.adUnitId,
        adSize: widget.adSize,
        placementName: widget.placementName,
        listener: this,
        onPlatformViewCreated: _onPlatformViewCreated,
      ),
    );
  }
}
