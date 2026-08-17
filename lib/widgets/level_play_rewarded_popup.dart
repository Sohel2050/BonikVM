import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/level_play_service.dart';
import '../shared/providers/theme_provider.dart';

/// A drop-in replacement / companion to [UnifiedAdsPopup] that uses the
/// Unity LevelPlay (IronSource) SDK instead of AdMob rewarded ads.
///
/// Usage is identical to [UnifiedAdsPopup]:
/// ```dart
/// showDialog(
///   context: context,
///   builder: (_) => LevelPlayRewardedPopup(
///     adCount: 3,
///     onAction: (action) async {
///       if (action == 'all_ads_watched') { /* grant access */ }
///     },
///   ),
/// );
/// ```
class LevelPlayRewardedPopup extends ConsumerStatefulWidget {
  /// Called when the popup reaches a terminal state:
  /// - `'all_ads_watched'` – user completed all required video ads
  /// - `'subscribe_clicked'` – user tapped the "Go Premium" button
  final Future<void> Function(String action) onAction;

  /// Optional callback when the dialog is dismissed without completing.
  final VoidCallback? onClosed;

  /// Number of rewarded videos to request (1–3). Default: 3.
  final int adCount;

  /// Optional custom title shown at the top of the popup.
  final String? title;

  /// Optional subtitle / instruction text.
  final String? subtitle;

  /// Whether to show the "Go Premium" shortcut button. Default: true.
  final bool showSubscribeButton;

  const LevelPlayRewardedPopup({
    super.key,
    required this.onAction,
    this.onClosed,
    this.adCount = 3,
    this.title,
    this.subtitle,
    this.showSubscribeButton = true,
  });

  @override
  ConsumerState<LevelPlayRewardedPopup> createState() =>
      _LevelPlayRewardedPopupState();
}

class _LevelPlayRewardedPopupState
    extends ConsumerState<LevelPlayRewardedPopup> {
  // Track per-slot state
  late List<_SlotState> _slots;

  // Global availability from LevelPlay SDK
  bool _adAvailable = false;
  bool _isShowingAd = false;
  bool _actionFired = false;

  @override
  void initState() {
    super.initState();
    _slots = List.generate(widget.adCount, (i) => _SlotState(index: i));

    _setupLevelPlayCallbacks();
    _checkAvailability();
  }

  @override
  void dispose() {
    LevelPlayService.instance.clearRewardedCallbacks();
    super.dispose();
  }

  // ---- LevelPlay wiring ----

  void _setupLevelPlayCallbacks() {
    LevelPlayService.instance.setRewardedCallbacks(
      LevelPlayRewardedCallbacks(
        onOpened: _handleAdOpened,
        onClosed: _handleAdClosed,
        onRewarded: _handleAdRewarded,
        onShowFailed: _handleAdShowFailed,
        onAvailabilityChanged: _handleAvailabilityChanged,
      ),
    );
  }

  Future<void> _checkAvailability() async {
    final available = await LevelPlayService.instance
        .checkRewardedVideoAvailable();
    if (mounted) {
      setState(() => _adAvailable = available);
    }
  }

  // ---- Ad event handlers ----

  void _handleAdOpened() {
    if (!mounted) return;
    setState(() => _isShowingAd = true);
  }

  void _handleAdClosed() {
    if (!mounted) return;
    setState(() => _isShowingAd = false);
    // Refresh availability for the next slot
    _checkAvailability();
  }

  void _handleAdRewarded(String rewardName, int rewardAmount) {
    if (!mounted) return;

    // Find the first un-rewarded, in-progress slot
    final slotIndex = _slots.indexWhere((s) => s.isWatching && !s.isRewarded);
    if (slotIndex == -1) return;

    setState(() {
      _slots[slotIndex] = _slots[slotIndex].copyWith(
        isWatching: false,
        isRewarded: true,
      );
    });

    debugPrint(
      '[LevelPlayRewardedPopup] Slot $slotIndex rewarded: $rewardAmount $rewardName',
    );

    // Check if all required slots are rewarded
    final rewarded = _slots.where((s) => s.isRewarded).length;
    if (rewarded >= widget.adCount && !_actionFired) {
      _actionFired = true;
      _completeAll();
    }
  }

  void _handleAdShowFailed(String errorMessage) {
    if (!mounted) return;

    // Reset the in-progress slot
    final slotIndex = _slots.indexWhere((s) => s.isWatching);
    if (slotIndex != -1) {
      setState(() {
        _slots[slotIndex] = _slots[slotIndex].copyWith(isWatching: false);
      });
    }

    setState(() => _isShowingAd = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Ad failed to show. Please try again. ($errorMessage)'),
        backgroundColor: Colors.red.shade700,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  void _handleAvailabilityChanged(bool available) {
    if (!mounted) return;
    setState(() => _adAvailable = available);
  }

  // ---- Actions ----

  Future<void> _watchVideo(int slotIndex) async {
    if (_isShowingAd) return;
    if (_slots[slotIndex].isRewarded) return;

    setState(() {
      _slots[slotIndex] = _slots[slotIndex].copyWith(isWatching: true);
    });

    await LevelPlayService.instance.showRewardedVideo();
  }

  Future<void> _completeAll() async {
    await widget.onAction('all_ads_watched');
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _onSubscribeTapped() async {
    await widget.onAction('subscribe_clicked');
    if (mounted) Navigator.of(context).pop();
  }

  void _onClose() {
    widget.onClosed?.call();
    Navigator.of(context).pop();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final isDark = ref.watch(themeModeProvider) == ThemeMode.dark;
    final bgColor = isDark ? const Color(0xFF1A1A2E) : Colors.white;
    final cardColor = isDark
        ? const Color(0xFF16213E)
        : const Color(0xFFF5F5F5);
    final textColor = isDark ? Colors.white : Colors.black87;
    final subColor = isDark ? Colors.white60 : Colors.black54;

    final int rewardedCount = _slots.where((s) => s.isRewarded).length;
    final bool allDone = rewardedCount >= widget.adCount;

    final String titleText =
        widget.title ??
        (widget.adCount == 2
            ? 'Watch 1 Ad for Free Access'
            : 'Watch ${widget.adCount} Ads for Free Access');

    final String subtitleText =
        widget.subtitle ?? 'Watch short videos to unlock free VPN time.';

    return Dialog(
      backgroundColor: bgColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header row
            Row(
              children: [
                Expanded(
                  child: Text(
                    titleText,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: _onClose,
                  icon: Icon(Icons.close, color: subColor),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(subtitleText, style: TextStyle(color: subColor, fontSize: 13)),
            const SizedBox(height: 20),

            // Progress indicator
            _ProgressBar(
              total: widget.adCount,
              completed: rewardedCount,
              isDark: isDark,
            ),
            const SizedBox(height: 20),

            // Ad slots
            ...List.generate(widget.adCount, (i) {
              return _AdSlotTile(
                slot: _slots[i],
                adCount: widget.adCount,
                adAvailable: _adAvailable,
                isShowingAd: _isShowingAd,
                cardColor: cardColor,
                textColor: textColor,
                subColor: subColor,
                onWatch: () => _watchVideo(i),
              );
            }),

            const SizedBox(height: 20),

            // CTA button
            if (allDone)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _completeAll,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '🎉 Claim Free Access',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                ),
              )
            else if (!_adAvailable)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  '⏳ Loading ad… please wait',
                  style: TextStyle(color: subColor, fontSize: 13),
                ),
              ),

            // Subscribe shortcut
            if (widget.showSubscribeButton && !allDone) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _onSubscribeTapped,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.amber,
                    side: const BorderSide(color: Colors.amber),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    '👑 Or Go Premium – No Ads',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ---- Helper Data Class ----

class _SlotState {
  final int index;
  final bool isWatching;
  final bool isRewarded;

  const _SlotState({
    required this.index,
    this.isWatching = false,
    this.isRewarded = false,
  });

  _SlotState copyWith({bool? isWatching, bool? isRewarded}) => _SlotState(
    index: index,
    isWatching: isWatching ?? this.isWatching,
    isRewarded: isRewarded ?? this.isRewarded,
  );
}

// ---- Sub-widgets ----

class _ProgressBar extends StatelessWidget {
  final int total;
  final int completed;
  final bool isDark;

  const _ProgressBar({
    required this.total,
    required this.completed,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    final ratio = total == 0 ? 0.0 : completed / total;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: isDark ? Colors.white12 : Colors.black12,
            valueColor: AlwaysStoppedAnimation<Color>(
              completed == total ? Colors.green : Colors.cyan,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$completed / $total ads watched',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white54 : Colors.black45,
          ),
        ),
      ],
    );
  }
}

class _AdSlotTile extends StatelessWidget {
  final _SlotState slot;
  final int adCount;
  final bool adAvailable;
  final bool isShowingAd;
  final Color cardColor;
  final Color textColor;
  final Color subColor;
  final VoidCallback onWatch;

  const _AdSlotTile({
    required this.slot,
    required this.adCount,
    required this.adAvailable,
    required this.isShowingAd,
    required this.cardColor,
    required this.textColor,
    required this.subColor,
    required this.onWatch,
  });

  @override
  Widget build(BuildContext context) {
    final bool canTap =
        !slot.isRewarded && !slot.isWatching && adAvailable && !isShowingAd;

    Widget trailing;
    if (slot.isRewarded) {
      trailing = const Icon(Icons.check_circle, color: Colors.green, size: 28);
    } else if (slot.isWatching) {
      trailing = const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyan),
      );
    } else {
      trailing = ElevatedButton(
        onPressed: canTap ? onWatch : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.cyan,
          foregroundColor: Colors.black,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        child: const Text('Watch', style: TextStyle(fontSize: 13)),
      );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: slot.isRewarded
                  ? Colors.green.withValues(alpha: 0.2)
                  : Colors.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Center(
              child: Text(
                '${slot.index + 1}',
                style: TextStyle(
                  color: slot.isRewarded ? Colors.green : Colors.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Video Ad ${slot.index + 1}',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  slot.isRewarded
                      ? '✅ Completed'
                      : slot.isWatching
                      ? '⏳ Playing…'
                      : adAvailable
                      ? 'Tap Watch to earn your time'
                      : 'Loading ad…',
                  style: TextStyle(color: subColor, fontSize: 12),
                ),
              ],
            ),
          ),
          trailing,
        ],
      ),
    );
  }
}
