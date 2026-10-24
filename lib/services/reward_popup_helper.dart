import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../shared/providers/app_providers.dart';
import '../core/localization/app_localizations.dart';
import '../core/api/api_service.dart';

/// Helper service to manage reward video popup lifecycle across screens
/// @deprecated This class is deprecated. Use UnifiedAdsPopup from widgets/unified_ads_popup.dart instead.
class RewardPopupHelper {
  /// Show reward video popup when free time expires
  /// @deprecated Use UnifiedAdsPopup instead
  static Future<void> showRewardPopupIfTimeExpired({
    required BuildContext context,
    required WidgetRef ref,
    required VpnServer? currentServer,
    required VoidCallback onTimeExtended,
    required VoidCallback onSubscriptionPressed,
    VoidCallback? onDismissed,
  }) async {
    debugPrint(
      '⚠️ showRewardPopupIfTimeExpired() is deprecated. Use UnifiedAdsPopup instead.',
    );
    // This method is deprecated and no longer functional
    return;
  }

  /// Check free time status and show appropriate UI
  static String getTimeStatusText({
    required FreeConnectionTimerState timerState,
    required AppLocalizations localizations,
  }) {
    if (timerState.isPremium) {
      return '👑 Unlimited';
    }

    if (!timerState.isActive) {
      if (timerState.timerExpired) {
        return '⏰ ${localizations.timeExpired}';
      }
      return '✅ Ready';
    }

    // Format remaining time
    final minutes = timerState.remainingSeconds ~/ 60;
    final seconds = timerState.remainingSeconds % 60;

    if (minutes > 0) {
      return '⏱️ ${minutes}m ${seconds}s';
    } else {
      return '⏱️ ${seconds}s';
    }
  }

  /// Get time status color
  static Color getTimeStatusColor({
    required FreeConnectionTimerState timerState,
  }) {
    if (timerState.isPremium) {
      return Colors.purple;
    }

    if (timerState.timerExpired) {
      return Colors.red;
    }

    if (!timerState.isActive) {
      return Colors.green;
    }

    final minutes = timerState.remainingSeconds ~/ 60;
    if (minutes <= 1) {
      return Colors.orange; // Warning
    }

    return Colors.cyan;
  }

  /// Get time status icon
  static IconData getTimeStatusIcon({
    required FreeConnectionTimerState timerState,
  }) {
    if (timerState.isPremium) {
      return Icons.star;
    }

    if (timerState.timerExpired) {
      return Icons.alarm_off;
    }

    if (!timerState.isActive) {
      return Icons.check_circle;
    }

    return Icons.hourglass_bottom;
  }

  /// Format time for display
  static String formatTime(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else if (minutes > 0) {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    } else {
      return '${secs}s';
    }
  }

  /// Check if should prompt for reward video
  static bool shouldPromptForReward({
    required FreeConnectionTimerState timerState,
    required bool isPremium,
  }) {
    return timerState.timerExpired && !isPremium && !timerState.isPremium;
  }
}
