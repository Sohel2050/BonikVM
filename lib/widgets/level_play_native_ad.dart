import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';

import '../core/services/level_play_service.dart';

/// A LevelPlay native-template placement. It waits for the asynchronous SDK
/// initialization callback before loading, avoiding invalid direct AdMob calls.
class LevelPlayNativeAdPlacement extends StatefulWidget {
  const LevelPlayNativeAdPlacement({
    super.key,
    this.height = 300,
    this.templateType = LevelPlayTemplateType.MEDIUM,
    this.placementName,
    this.maskColor,
  });

  final double height;
  final LevelPlayTemplateType templateType;
  final String? placementName;

  /// Color used to cover the SDK's own default (often black/grey) template
  /// background while the ad is loading. Pass the exact background color of
  /// whatever container/card wraps this widget, so the loading state blends
  /// in seamlessly instead of showing a mismatched-colored box. Falls back
  /// to the page's scaffold background color if not provided.
  final Color? maskColor;

  @override
  State<LevelPlayNativeAdPlacement> createState() => _LevelPlayNativeAdState();
}

class _LevelPlayNativeAdState extends State<LevelPlayNativeAdPlacement>
    with LevelPlayNativeAdListener {
  LevelPlayNativeAd? _nativeAd;
  bool _failed = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _nativeAd = LevelPlayNativeAd.builder()
        .withPlacementName(widget.placementName ?? '')
        .withListener(this)
        .build();
  }

  @override
  void dispose() {
    _nativeAd?.destroyAd();
    super.dispose();
  }

  void _loadWhenInitialized([int attempts = 0]) {
    if (!mounted || _failed) return;
    if (LevelPlayService.instance.isInitialized) {
      _nativeAd?.loadAd();
      return;
    }
    if (attempts < 120) {
      Future.delayed(const Duration(milliseconds: 250), () {
        _loadWhenInitialized(attempts + 1);
      });
    }
  }

  @override
  void onAdLoaded(LevelPlayNativeAd nativeAd, AdInfo adInfo) {
    debugPrint('[LevelPlayNativeAd] Loaded');
    if (mounted) setState(() => _loaded = true);
  }

  @override
  void onAdLoadFailed(LevelPlayNativeAd nativeAd, IronSourceError error) {
    debugPrint(
      '[LevelPlayNativeAd] Load failed: ${error.errorCode} – ${error.message}',
    );
    if (mounted) setState(() => _failed = true);
  }

  @override
  void onAdImpression(LevelPlayNativeAd nativeAd, AdInfo adInfo) {}

  @override
  void onAdClicked(LevelPlayNativeAd nativeAd, AdInfo adInfo) {}

  @override
  Widget build(BuildContext context) {
    if (_failed) return const SizedBox.shrink();
    return SizedBox(
      // Keep a real platform-view size during the load. A zero-sized Android
      // platform view may never be attached, which prevents its load callback.
      height: widget.height,
      width: double.infinity,
      child: Stack(
        children: [
          LevelPlayNativeAdView(
            height: widget.height,
            width: MediaQuery.sizeOf(context).width,
            nativeAd: _nativeAd,
            templateType: widget.templateType,
            onPlatformViewCreated: _loadWhenInitialized,
          ),
          // The native ad template renders its own default black/grey
          // background while loading (this comes from the SDK's own
          // platform-view layout, not something Flutter can style
          // directly). Cover it with the surrounding page's own
          // background color until the ad actually has content, so the
          // space looks clean/blank instead of a dark placeholder box —
          // then reveal it once onAdLoaded fires. The platform view keeps
          // its real size underneath the whole time, so it still attaches
          // and loads normally.
          if (!_loaded)
            IgnorePointer(
              child: Container(
                color:
                widget.maskColor ??
                    Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
        ],
      ),
    );
  }
}
