import 'package:flutter/material.dart';
import 'unified_ads_popup_simple.dart';

/// Backwards-compatible name for the old popup.
/// All rewarded ads are now handled by Unity LevelPlay.
class UnifiedAdsPopup extends UnifiedAdsPopupSimple {
  const UnifiedAdsPopup({
    super.key,
    required super.onAction,
    super.onClosed,
    super.customText,
    super.adCount,
    super.title,
    super.subtitle,
    super.showSubscribeButton,
  });
}
