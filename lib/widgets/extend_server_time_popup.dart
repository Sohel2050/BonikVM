import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/level_play_service.dart';
import '../shared/providers/theme_provider.dart';

/// Bottom-sheet used when a free VPN connection has expired.
/// Every successfully rewarded LevelPlay video adds [durationMinutes].
class ExtendServerTimePopup extends ConsumerStatefulWidget {
  final String serverName;
  final int adCount;
  final int durationMinutes;
  final Future<void> Function(int adIndex) onAdWatched;
  final Future<void> Function() onSubscriptionPressed;

  const ExtendServerTimePopup({
    super.key,
    required this.serverName,
    required this.onAdWatched,
    required this.onSubscriptionPressed,
    this.adCount =3,
    this.durationMinutes = 45,
  });

  @override
  ConsumerState<ExtendServerTimePopup> createState() =>
      _ExtendServerTimePopupState();
}

class _ExtendServerTimePopupState extends ConsumerState<ExtendServerTimePopup> {
  late final List<bool> _watched;
  int? _activeSlot;
  bool _adReady = false;
  bool _showingAd = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _watched = List<bool>.filled(widget.adCount, false);
    LevelPlayService.instance.setRewardedCallbacks(
      LevelPlayRewardedCallbacks(
        onOpened: () {
          if (mounted) setState(() => _showingAd = true);
        },
        onClosed: () {
          if (mounted) setState(() => _showingAd = false);
          _refreshReady();
        },
        onRewarded: (_, __) => _handleReward(),
        onShowFailed: (error) {
          if (!mounted) return;
          setState(() {
            _showingAd = false;
            _activeSlot = null;
          });
          _snack('Ad could not be shown. Please try again.');
        },
        onAvailabilityChanged: (ready) {
          if (mounted) setState(() => _adReady = ready);
        },
      ),
    );
    _refreshReady();
  }

  Future<void> _refreshReady() async {
    final ready = await LevelPlayService.instance.checkRewardedVideoAvailable();
    if (mounted) setState(() => _adReady = ready);
  }

  Future<void> _watch(int index) async {
    if (_watched[index] || _showingAd || _activeSlot != null || _closing) return;

    final ready = await LevelPlayService.instance.checkRewardedVideoAvailable();
    if (!ready) {
      if (mounted) setState(() => _adReady = false);
      _snack('Video is loading. Please try again in a moment.');
      return;
    }

    setState(() {
      _activeSlot = index;
      _adReady = true;
    });

    await LevelPlayService.instance.showRewardedVideo(
      placementName: 'extend_server_time',
    );
  }

  Future<void> _handleReward() async {
    final index = _activeSlot;
    if (index == null || _watched[index]) return;

    setState(() {
      _watched[index] = true;
      _activeSlot = null;
    });

    try {
      await widget.onAdWatched(index);
    } catch (e) {
      debugPrint('ExtendServerTime reward callback error: $e');
    }

    if (!mounted) return;
    if (_watched.every((item) => item)) {
      setState(() => _closing = true);
      await Future.delayed(const Duration(milliseconds: 350));
      if (mounted) Navigator.of(context).pop(true);
    } else {
      await _refreshReady();
    }
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }

  @override
  void dispose() {
    LevelPlayService.instance.clearRewardedCallbacks();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(themeColorProvider);
    final bg = isDark ? const Color(0xFF101827) : Colors.white;
    final card = isDark ? const Color(0xFF162734) : const Color(0xFFF4F7F5);
    final text = isDark ? Colors.white : const Color(0xFF17212B);
    final secondary = isDark ? Colors.white70 : Colors.black54;
    final completed = _watched.where((v) => v).length;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: bg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 42,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: .45),
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              Row(
                children: [
                  Container(
                    width: 54,
                    height: 54,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: .12),
                      borderRadius: BorderRadius.circular(17),
                    ),
                    child: Icon(Icons.lock_clock_rounded, color: accent, size: 29),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Extend Server Time', style: TextStyle(color: text, fontSize: 20, fontWeight: FontWeight.w800)),
                        const SizedBox(height: 3),
                        Text(widget.serverName, style: TextStyle(color: secondary, fontSize: 13)),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: _closing ? null : () => Navigator.of(context).pop(false),
                    icon: Icon(Icons.close_rounded, color: secondary, size: 28),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: accent.withValues(alpha: .16)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded, color: accent, size: 23),
                    const SizedBox(width: 11),
                    Expanded(
                      child: Text(
                        'Watch ${widget.adCount} short videos to unlock temporary access. Each video adds ${widget.durationMinutes} minutes.',
                        style: TextStyle(color: accent, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: List.generate(widget.adCount, (i) {
                  return Expanded(
                    child: Container(
                      height: 5,
                      margin: EdgeInsets.only(right: i == widget.adCount - 1 ? 0 : 7),
                      decoration: BoxDecoration(
                        color: _watched[i] ? accent : Colors.grey.withValues(alpha: .22),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('$completed/${widget.adCount} videos watched', style: TextStyle(color: secondary, fontSize: 12)),
              ),
              const SizedBox(height: 15),
              ...List.generate(widget.adCount, (i) {
                final done = _watched[i];
                final loading = _activeSlot == i || (_showingAd && _activeSlot == i);
                return Container(
                  margin: const EdgeInsets.only(bottom: 11),
                  decoration: BoxDecoration(
                    color: card,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: done ? accent : accent.withValues(alpha: .72), width: 1.7),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: done || loading ? null : () => _watch(i),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                      child: Row(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              color: done ? accent.withValues(alpha: .15) : accent.withValues(alpha: .10),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(done ? Icons.check_rounded : Icons.play_arrow_rounded, color: accent, size: 26),
                          ),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('AD-${i + 1}', style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)),
                                const SizedBox(height: 4),
                                Text(done ? 'Time added successfully' : '+ ${widget.durationMinutes} Minutes', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w700)),
                              ],
                            ),
                          ),
                          if (loading)
                            SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: accent))
                          else
                            Text(done ? 'Watched' : (_adReady ? 'Watch Now' : 'Loading...'), style: TextStyle(color: done ? accent : text, fontSize: 13, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                );
              }),
              const SizedBox(height: 6),
              Container(height: 1, color: Colors.grey.withValues(alpha: .25)),
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                height: 58,
                child: ElevatedButton.icon(
                  onPressed: _closing ? null : () async {
                    // onSubscriptionPressed already closes this sheet
                    // (pop(false)) and pushes '/premium' itself — do not
                    // pop again here, or it will immediately pop the
                    // freshly-pushed premium screen off the stack.
                    await widget.onSubscriptionPressed();
                  },
                  icon: const Icon(Icons.shopping_bag_rounded),
                  label: const Text('BUY SUBSCRIPTION', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.white,
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
