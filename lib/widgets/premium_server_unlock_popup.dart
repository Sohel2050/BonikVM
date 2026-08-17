import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_service.dart';
import '../core/services/level_play_service.dart';
import '../shared/providers/theme_provider.dart';

typedef OnPremiumVideoWatched = Future<void> Function(int videoIndex);
typedef OnPremiumSubscriptionPressed = Future<void> Function();

/// Premium server unlock popup using Unity LevelPlay rewarded ads only.
class PremiumServerUnlockPopup extends ConsumerStatefulWidget {
  final VpnServer server;
  final OnPremiumVideoWatched onVideoWatched;
  final OnPremiumSubscriptionPressed onSubscriptionPressed;
  final List<bool> canWatchVideo;
  final int watchedCount;
  final int maxVideos;
  final int durationMinutes;

  const PremiumServerUnlockPopup({
    super.key,
    required this.server,
    required this.onVideoWatched,
    required this.onSubscriptionPressed,
    required this.canWatchVideo,
    this.watchedCount = 0,
    this.maxVideos = 3,
    this.durationMinutes = 30,
  });

  @override
  ConsumerState<PremiumServerUnlockPopup> createState() =>
      _PremiumServerUnlockPopupState();
}

class _PremiumServerUnlockPopupState
    extends ConsumerState<PremiumServerUnlockPopup> {
  late final List<bool> _watched;
  int? _activeSlot;
  bool _adReady = false;
  bool _showingAd = false;

  @override
  void initState() {
    super.initState();
    _watched = List.generate(widget.maxVideos, (i) {
      final allowed = i < widget.canWatchVideo.length
          ? widget.canWatchVideo[i]
          : true;
      return !allowed;
    });

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
        onShowFailed: (_) {
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
    if (_watched[index] || _activeSlot != null || _showingAd) return;

    final ready = await LevelPlayService.instance.checkRewardedVideoAvailable();
    if (!ready) {
      if (mounted) setState(() => _adReady = false);
      _snack('Video is loading. Please try again in a moment.');
      return;
    }

    setState(() => _activeSlot = index);
    await LevelPlayService.instance.showRewardedVideo(
      placementName: 'premium_server_unlock',
    );
  }

  Future<void> _handleReward() async {
    final index = _activeSlot;
    if (index == null || _watched[index]) return;

    setState(() {
      _watched[index] = true;
      _activeSlot = null;
    });

    await widget.onVideoWatched(index);

    if (!mounted) return;
    if (_watched.every((v) => v)) {
      await Future.delayed(const Duration(milliseconds: 300));
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
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(themeColorProvider);
    final bg = dark ? const Color(0xFF101827) : Colors.white;
    final card = dark ? const Color(0xFF162734) : const Color(0xFFF4F7F5);
    final text = dark ? Colors.white : const Color(0xFF17212B);
    final sub = dark ? Colors.white70 : Colors.black54;
    final done = _watched.where((v) => v).length;

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
              Container(width: 42, height: 4, margin: const EdgeInsets.only(bottom: 18), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: .45), borderRadius: BorderRadius.circular(10))),
              Row(
                children: [
                  Container(width: 54, height: 54, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(17)), child: Icon(Icons.currency_exchange, color: accent, size: 29)),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('WATCH ADS TO ACCESS', style: TextStyle(color: text, fontSize: 19, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 3),
                    Text(widget.server.name, style: TextStyle(color: sub, fontSize: 13)),
                  ])),
                  IconButton(onPressed: () => Navigator.of(context).pop(false), icon: Icon(Icons.close_rounded, color: sub, size: 28)),
                ],
              ),
              const SizedBox(height: 17),
              Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 14), decoration: BoxDecoration(color: accent.withValues(alpha: .09), borderRadius: BorderRadius.circular(16), border: Border.all(color: accent.withValues(alpha: .16))), child: Row(children: [Icon(Icons.info_outline_rounded, color: accent, size: 23), const SizedBox(width: 11), Expanded(child: Text('Watch ${_watched.where((v) => !v).length} more video${_watched.where((v) => !v).length == 1 ? '' : 's'} to unlock this premium server.', style: TextStyle(color: accent, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600)))])),
              const SizedBox(height: 15),
              Row(children: List.generate(widget.maxVideos, (i) => Expanded(child: Container(height: 5, margin: EdgeInsets.only(right: i == widget.maxVideos - 1 ? 0 : 7), decoration: BoxDecoration(color: _watched[i] ? accent : Colors.grey.withValues(alpha: .22), borderRadius: BorderRadius.circular(10)))))),
              const SizedBox(height: 8),
              Align(alignment: Alignment.centerLeft, child: Text('$done/${widget.maxVideos} videos watched', style: TextStyle(color: sub, fontSize: 12))),
              const SizedBox(height: 15),
              ...List.generate(widget.maxVideos, (i) {
                final isDone = _watched[i];
                final loading = _activeSlot == i;
                return Container(
                  margin: const EdgeInsets.only(bottom: 11),
                  decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: isDone ? accent : accent.withValues(alpha: .72), width: 1.7)),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(18),
                    onTap: isDone || loading ? null : () => _watch(i),
                    child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                      Container(width: 46, height: 46, decoration: BoxDecoration(color: accent.withValues(alpha: .10), shape: BoxShape.circle), child: Icon(isDone ? Icons.check_rounded : Icons.play_arrow_rounded, color: accent, size: 26)),
                      const SizedBox(width: 13),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('VIDEO AD ${i + 1}', style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(isDone ? 'Access unlocked' : '+ ${widget.durationMinutes} Minutes', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w700))])),
                      if (loading || (_showingAd && loading)) SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: accent)) else Text(isDone ? 'Watched' : (_adReady ? 'Watch' : 'Loading...'), style: TextStyle(color: isDone ? accent : text, fontSize: 13, fontWeight: FontWeight.w700)),
                    ])),
                  ),
                );
              }),
              const SizedBox(height: 5),
              SizedBox(width: double.infinity, height: 56, child: OutlinedButton.icon(onPressed: () async { await widget.onSubscriptionPressed(); if (mounted) Navigator.of(context).pop(true); }, icon: const Icon(Icons.currency_exchange), label: const Text('OR GO PREMIUM — NO ADS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent, width: 1.6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))))),
            ],
          ),
        ),
      ),
    );
  }
}

Future<bool> showPremiumServerUnlockPopup({
  required BuildContext context,
  required VpnServer server,
  required OnPremiumVideoWatched onVideoWatched,
  required OnPremiumSubscriptionPressed onSubscriptionPressed,
  required List<bool> canWatchVideo,
  int watchedCount = 0,
  int maxVideos = 3,
  int durationMinutes = 30,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => PremiumServerUnlockPopup(
      server: server,
      onVideoWatched: onVideoWatched,
      onSubscriptionPressed: onSubscriptionPressed,
      canWatchVideo: canWatchVideo,
      watchedCount: watchedCount,
      maxVideos: maxVideos,
      durationMinutes: durationMinutes,
    ),
  );
  return result ?? false;
}
