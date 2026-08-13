import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';
import '../providers/subscription_provider.dart';

// State provider for banner visibility (resets on app restart)
final subscriptionBannerVisibleProvider = StateProvider<bool>((ref) => true);

class SubscriptionBanner extends ConsumerWidget {
  const SubscriptionBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final subscription = ref.watch(subscriptionProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isBannerVisible = ref.watch(subscriptionBannerVisibleProvider);

    // Don't show if not premium, no subscription data, or user closed it
    if (!subscription.isPremium ||
        subscription.subscription == null ||
        !isBannerVisible) {
      return const SizedBox.shrink();
    }

    final expiresAt = subscription.expiresAt;
    final isLifetime = subscription.isLifetime;
    final displayName = subscription.displayName;

    String message;
    Color backgroundColor;
    Color textColor;
    IconData icon;

    if (isLifetime) {
      message = '$displayName - Lifetime Access';
      backgroundColor = isDarkMode
          ? const Color(0xFF059669)
          : const Color(0xFF10B981);
      textColor = Colors.white;
      icon = Icons.workspace_premium;
    } else if (expiresAt != null) {
      final now = DateTime.now();
      final daysRemaining = expiresAt.difference(now).inDays;
      final dateFormat = DateFormat('MMM dd, yyyy');

      if (daysRemaining < 0) {
        // Expired
        message =
            'Your subscription expired on ${dateFormat.format(expiresAt)}';
        backgroundColor = isDarkMode
            ? const Color(0xFF991B1B)
            : const Color(0xFFEF4444);
        textColor = Colors.white;
        icon = Icons.error_outline;
      } else if (daysRemaining == 0) {
        // Expires today
        message = 'Your subscription expires today!';
        backgroundColor = isDarkMode
            ? const Color(0xFFEA580C)
            : const Color(0xFFF97316);
        textColor = Colors.white;
        icon = Icons.warning_amber_rounded;
      } else if (daysRemaining <= 7) {
        // Expires soon
        message =
            'Your subscription expires in $daysRemaining day${daysRemaining > 1 ? 's' : ''}';
        backgroundColor = isDarkMode
            ? const Color(0xFFEA580C)
            : const Color(0xFFF97316);
        textColor = Colors.white;
        icon = Icons.access_time;
      } else {
        // Active subscription
        message = 'Premium Active until ${dateFormat.format(expiresAt)}';
        backgroundColor = isDarkMode
            ? const Color(0xFF059669)
            : const Color(0xFF10B981);
        textColor = Colors.white;
        icon = Icons.check_circle_outline;
      }
    } else {
      // Has premium but no expiry date
      message = 'Premium Active';
      backgroundColor = isDarkMode
          ? const Color(0xFF059669)
          : const Color(0xFF10B981);
      textColor = Colors.white;
      icon = Icons.verified;
    }

    return FadeInDown(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: backgroundColor.withValues(alpha: 0.3),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                message,
                style: TextStyle(
                  color: textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            if (expiresAt != null && !isLifetime)
              IconButton(
                icon: Icon(Icons.refresh, color: textColor, size: 20),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(),
                onPressed: () {
                  ref.read(subscriptionProvider.notifier).refresh();
                },
                tooltip: 'Refresh subscription',
              ),
            // Close button (banner will show again on next app start)
            IconButton(
              icon: Icon(Icons.close, color: textColor, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: () {
                ref.read(subscriptionBannerVisibleProvider.notifier).state =
                    false;
              },
              tooltip: 'Close',
            ),
          ],
        ),
      ),
    );
  }
}
