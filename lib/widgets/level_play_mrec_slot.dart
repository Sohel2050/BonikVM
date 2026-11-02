import 'package:flutter/material.dart';
import 'package:unity_levelplay_mediation/unity_levelplay_mediation.dart';
import '../core/services/level_play_service.dart';
import 'level_play_banner_ad.dart';

/// MREC (300x250) banner slot used in place of a native ad.
///
/// - [background]/[borderColor] let the slot match its surroundings
///   (leave null for no fill, so it blends into the page).
/// - If the ad fails to load, the whole slot collapses (no empty box).
class LevelPlayMrecSlot extends StatefulWidget {
  final Color? background;
  final Color? borderColor;
  final double radius;
  final EdgeInsetsGeometry margin;

  const LevelPlayMrecSlot({
    super.key,
    this.background,
    this.borderColor,
    this.radius = 16,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<LevelPlayMrecSlot> createState() => _LevelPlayMrecSlotState();
}

class _LevelPlayMrecSlotState extends State<LevelPlayMrecSlot> {
  bool _visible = true;

  @override
  Widget build(BuildContext context) {
    final hidden = !_visible || !LevelPlayService.instance.adsEnabledByAdmin;
    // If the ad fails (about 5 seconds), the slot, including its margin, collapses
    // smoothly: no empty gap and no sudden jump of the content below.
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
      alignment: Alignment.topCenter,
      child: hidden
          ? const SizedBox(width: double.infinity)
          : Container(
              height: 250,
              margin: widget.margin,
              decoration: BoxDecoration(
                color: widget.background,
                borderRadius: BorderRadius.circular(widget.radius),
                border: widget.borderColor == null
                    ? null
                    : Border.all(color: widget.borderColor!),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(widget.radius),
                child: Center(
                  child: SizedBox(
                    width: 300,
                    height: 250,
                    child: LevelPlayBannerAd(
                      adUnitId: LevelPlayService.instance.mrecAdUnitId,
                      adSize: LevelPlayAdSize.MEDIUM_RECTANGLE,
                      onFailed: () {
                        if (mounted) setState(() => _visible = false);
                      },
                    ),
                  ),
                ),
              ),
            ),
    );
  }
}
