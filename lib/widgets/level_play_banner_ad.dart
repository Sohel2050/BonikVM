import 'package:flutter/material.dart';
import 'package:ironsource_mediation/ironsource_mediation.dart';
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

  LevelPlayBannerAd({
    super.key,
    required this.adUnitId,
    LevelPlayAdSize? adSize,
    this.placementName,
  }) : adSize = adSize ?? LevelPlayAdSize.BANNER;

  @override
  State<LevelPlayBannerAd> createState() => _LevelPlayBannerAdState();
}

class _LevelPlayBannerAdState extends State<LevelPlayBannerAd>
    implements LevelPlayBannerAdViewListener {
  // GlobalKey is required by LevelPlayBannerAdView to call loadAd() / destroy()
  late final GlobalKey<LevelPlayBannerAdViewState> _bannerKey;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _bannerKey = GlobalKey<LevelPlayBannerAdViewState>();
  }

  @override
  void dispose() {
    _bannerKey.currentState?.destroy();
    super.dispose();
  }

  void _onPlatformViewCreated() {
    if (!LevelPlayService.instance.isInitialized) return;
    _bannerKey.currentState?.loadAd();
  }

  // ---- LevelPlayBannerAdViewListener ----

  @override
  void onAdLoaded(LevelPlayAdInfo adInfo) {
    debugPrint('[LevelPlayBannerAd] Loaded: ${adInfo.adId}');
    if (mounted) setState(() {});
  }

  @override
  void onAdLoadFailed(LevelPlayAdError error) {
    debugPrint(
      '[LevelPlayBannerAd] Load failed: ${error.errorCode} – ${error.errorMessage}',
    );
    if (mounted) setState(() => _failed = true);
  }

  @override
  void onAdDisplayed(LevelPlayAdInfo adInfo) {}

  @override
  void onAdDisplayFailed(LevelPlayAdInfo adInfo, LevelPlayAdError error) {}

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
    if (_failed) return const SizedBox.shrink();

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
