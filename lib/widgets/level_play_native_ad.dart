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
  });

  final double height;
  final LevelPlayTemplateType templateType;
  final String? placementName;

  @override
  State<LevelPlayNativeAdPlacement> createState() => _LevelPlayNativeAdState();
}

class _LevelPlayNativeAdState extends State<LevelPlayNativeAdPlacement>
    with LevelPlayNativeAdListener {
  LevelPlayNativeAd? _nativeAd;
  bool _failed = false;

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
      child: LevelPlayNativeAdView(
        height: widget.height,
        width: MediaQuery.sizeOf(context).width,
        nativeAd: _nativeAd,
        templateType: widget.templateType,
        onPlatformViewCreated: _loadWhenInitialized,
      ),
    );
  }
}
