import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/level_play_service.dart';
import '../shared/providers/theme_provider.dart';

/// Backwards-compatible popup API, now powered exclusively by Unity LevelPlay.
class UnifiedAdsPopupSimple extends ConsumerStatefulWidget {
  final Future<void> Function(String action) onAction;
  final VoidCallback? onClosed;
  final String? customText;
  final int adCount;
  final String? title;
  final String? subtitle;
  final bool showSubscribeButton;

  const UnifiedAdsPopupSimple({
    super.key,
    required this.onAction,
    this.onClosed,
    this.customText,
    this.adCount = 3,
    this.title,
    this.subtitle,
    this.showSubscribeButton = true,
  });

  @override
  ConsumerState<UnifiedAdsPopupSimple> createState() =>
      _UnifiedAdsPopupSimpleState();
}

class _UnifiedAdsPopupSimpleState extends ConsumerState<UnifiedAdsPopupSimple> {
  late final List<bool> _watched;
  int? _active;
  bool _ready = false;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _watched = List<bool>.filled(widget.adCount, false);
    LevelPlayService.instance.setRewardedCallbacks(
      LevelPlayRewardedCallbacks(
        onOpened: () {
          if (mounted) setState(() => _showing = true);
        },
        onClosed: () {
          if (mounted) setState(() => _showing = false);
          _refresh();
        },
        onRewarded: (_, __) => _rewardActive(),
        onShowFailed: (_) {
          if (!mounted) return;
          setState(() {
            _showing = false;
            _active = null;
          });
          _snack('Ad could not be shown. Please try again.');
        },
        onAvailabilityChanged: (value) {
          if (mounted) setState(() => _ready = value);
        },
      ),
    );
    _refresh();
  }

  Future<void> _refresh() async {
    final ready = await LevelPlayService.instance.checkRewardedVideoAvailable();
    if (mounted) setState(() => _ready = ready);
  }

  Future<void> _showAd(int index) async {
    if (_watched[index] || _active != null || _showing) return;
    final ready = await LevelPlayService.instance.checkRewardedVideoAvailable();
    if (!ready) {
      if (mounted) setState(() => _ready = false);
      _snack('Ad is loading. Please try again in a moment.');
      return;
    }
    setState(() => _active = index);
    await LevelPlayService.instance.showRewardedVideo(
      placementName: 'unified_rewarded',
    );
  }

  Future<void> _rewardActive() async {
    final index = _active;
    if (index == null || _watched[index]) return;

    setState(() {
      _watched[index] = true;
      _active = null;
    });

    await widget.onAction('ad_watched');

    if (!mounted) return;
    if (_watched.every((v) => v)) {
      await widget.onAction('all_ads_watched');
      if (mounted) Navigator.of(context).pop(true);
    } else {
      await _refresh();
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
    widget.onClosed?.call();
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
    final count = _watched.where((v) => v).length;

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(color: bg, borderRadius: const BorderRadius.vertical(top: Radius.circular(28))),
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 18),
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(width: 42, height: 4, margin: const EdgeInsets.only(bottom: 18), decoration: BoxDecoration(color: Colors.grey.withValues(alpha: .45), borderRadius: BorderRadius.circular(10))),
            Row(children: [
              Container(width: 54, height: 54, decoration: BoxDecoration(color: accent.withValues(alpha: .12), borderRadius: BorderRadius.circular(17)), child: Icon(Icons.play_circle_fill_rounded, color: accent, size: 29)),
              const SizedBox(width: 14),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(widget.title ?? 'WATCH ADS TO ACCESS', style: TextStyle(color: text, fontSize: 19, fontWeight: FontWeight.w900)), if (widget.subtitle != null) ...[const SizedBox(height: 3), Text(widget.subtitle!, style: TextStyle(color: sub, fontSize: 13))]])),
              IconButton(onPressed: () => Navigator.of(context).pop(false), icon: Icon(Icons.close_rounded, color: sub, size: 28)),
            ]),
            const SizedBox(height: 16),
            Container(width: double.infinity, padding: const EdgeInsets.all(15), decoration: BoxDecoration(color: accent.withValues(alpha: .09), borderRadius: BorderRadius.circular(16)), child: Row(children: [Icon(Icons.info_outline_rounded, color: accent), const SizedBox(width: 10), Expanded(child: Text(widget.customText ?? 'Watch an ad to earn temporary access.', style: TextStyle(color: accent, fontSize: 13, height: 1.35, fontWeight: FontWeight.w600)))])),
            const SizedBox(height: 15),
            Row(children: List.generate(widget.adCount, (i) => Expanded(child: Container(height: 5, margin: EdgeInsets.only(right: i == widget.adCount - 1 ? 0 : 7), decoration: BoxDecoration(color: _watched[i] ? accent : Colors.grey.withValues(alpha: .22), borderRadius: BorderRadius.circular(10)))))),
            const SizedBox(height: 8),
            Align(alignment: Alignment.centerLeft, child: Text('$count/${widget.adCount} ads watched', style: TextStyle(color: sub, fontSize: 12))),
            const SizedBox(height: 15),
            ...List.generate(widget.adCount, (i) {
              final done = _watched[i];
              final loading = _active == i;
              return Container(
                margin: const EdgeInsets.only(bottom: 11),
                decoration: BoxDecoration(color: card, borderRadius: BorderRadius.circular(18), border: Border.all(color: done ? accent : accent.withValues(alpha: .72), width: 1.7)),
                child: InkWell(borderRadius: BorderRadius.circular(18), onTap: done || loading ? null : () => _showAd(i), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14), child: Row(children: [
                  Container(width: 46, height: 46, decoration: BoxDecoration(color: accent.withValues(alpha: .10), shape: BoxShape.circle), child: Icon(done ? Icons.check_rounded : Icons.play_arrow_rounded, color: accent, size: 26)),
                  const SizedBox(width: 13),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('VIDEO AD ${i + 1}', style: TextStyle(color: text, fontSize: 16, fontWeight: FontWeight.w800)), const SizedBox(height: 4), Text(done ? 'Completed' : 'Watch to earn access', style: TextStyle(color: accent, fontSize: 13, fontWeight: FontWeight.w700))])),
                  if (loading) SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: accent)) else Text(done ? 'Watched' : (_ready ? 'Watch' : 'Loading...'), style: TextStyle(color: done ? accent : text, fontSize: 13, fontWeight: FontWeight.w700)),
                ]))),
              );
            }),
            if (widget.showSubscribeButton) ...[
              const SizedBox(height: 5),
              SizedBox(width: double.infinity, height: 56, child: OutlinedButton.icon(onPressed: () async { await widget.onAction('subscribe_clicked'); if (mounted) Navigator.of(context).pop(true); }, icon: const Icon(Icons.currency_exchange), label: const Text('OR GO PREMIUM — NO ADS', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)), style: OutlinedButton.styleFrom(foregroundColor: accent, side: BorderSide(color: accent, width: 1.6), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17))))),
            ],
          ]),
        ),
      ),
    );
  }
}
