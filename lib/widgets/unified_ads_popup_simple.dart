import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/services/admob_service.dart';
import '../shared/providers/theme_provider.dart';

/// Simplified Unified Ads Popup
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
  late List<RewardedAd?> _ads;
  late List<bool> _adWatched; // tracks which ads have been watched
  int _rewardsEarned = 0;
  bool _allRewardsEarned = false;
  bool _isShowingAd = false;

  @override
  void initState() {
    super.initState();
    _ads = List.filled(widget.adCount, null);
    _adWatched = List.filled(widget.adCount, false);
    _loadAllAds();
  }

  void _loadAllAds() {
    for (int i = 0; i < widget.adCount; i++) {
      _loadAd(i);
    }
  }

  void _loadAd(int index) {
    RewardedAd.load(
      adUnitId: AdMobService.instance.rewardedAdUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          if (mounted) {
            setState(() {
              _ads[index] = ad;
            });
          }
        },
        onAdFailedToLoad: (error) {
        },
      ),
    );
  }

  Future<void> _showAd(int index) async {
    final ad = _ads[index];
    if (ad == null) {
      _showSnackBar('Ad not ready yet, please wait...');
      return;
    }
    if (_isShowingAd) {
      return;
    }

    _isShowingAd = true;
    bool rewardGrantedByCallback = false;

    // CRITICAL: Set fullScreenContentCallback BEFORE showing
    // This is needed to handle the SIMID JS error where onUserEarnedReward never fires
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdShowedFullScreenContent: (ad) {
      },
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        _isShowingAd = false;

        if (mounted) {
          setState(() {
            _ads[index] = null;
          });
        }

        // SIMID bug workaround: if reward callback didn't fire (JS error),
        // grant the reward on dismissal since the user watched the video
        if (!rewardGrantedByCallback && !_adWatched[index]) {
          _grantReward(index);
        }

        // Load next ad
        _loadAd(index);
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        _isShowingAd = false;
        if (mounted) {
          setState(() {
            _ads[index] = null;
          });
        }
        _loadAd(index);
        _showSnackBar('Ad failed to show, please try again');
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (ad, reward) {
          rewardGrantedByCallback = true;
          _grantReward(index);
        },
      );
    } catch (e) {
      _isShowingAd = false;
      _showSnackBar('Error showing ad');
    }
  }

  void _grantReward(int index) {
    if (_adWatched[index]) {
      return;
    }
    _adWatched[index] = true;

    if (mounted) {
      setState(() {
        _rewardsEarned++;
      });
    }


    // Fire per-ad callback immediately so server unlocks after EACH ad
    widget
        .onAction('ad_watched')
        .then((_) {
        })
        .catchError((e) {
        });

    if (_rewardsEarned >= widget.adCount) {
      _allRewardsEarned = true;
      _callUnlockCallback();
    }
  }

  Future<void> _callUnlockCallback() async {
    try {
      await widget.onAction('all_ads_watched');

      if (mounted) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      }
    } catch (e) {
      _showSnackBar('Error processing unlock');
    }
  }

  void _showSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  void dispose() {
    for (var ad in _ads) {
      ad?.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeColor = ref.watch(themeColorProvider);

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, MediaQuery.of(context).viewInsets.bottom + 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Title
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(Icons.lock_open_rounded, color: themeColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title ?? 'Unlock Premium',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: isDarkMode ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
              IconButton(
                icon: Icon(Icons.close, color: isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                onPressed: () => Navigator.pop(context, false),
              ),
            ],
          ),
          const SizedBox(height: 8),

            // Progress indicator
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Text(
                    'Watch ads to unlock',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  // Progress circles
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(widget.adCount, (i) {
                      final done = i < _rewardsEarned;
                      return Container(
                        margin: const EdgeInsets.symmetric(horizontal: 8),
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: done ? Colors.green : Colors.blue,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Ad buttons
            ...List.generate(widget.adCount, (i) {
              final done = i < _rewardsEarned;
              final loaded = _ads[i] != null;

              return Column(
                children: [
                  ElevatedButton(
                    onPressed: done
                        ? null
                        : (loaded && !_allRewardsEarned
                              ? () => _showAd(i)
                              : null),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: done ? Colors.green : themeColor,
                      disabledBackgroundColor: Colors.grey,
                      padding: const EdgeInsets.symmetric(
                        vertical: 12,
                        horizontal: 16,
                      ),
                      minimumSize: const Size(double.infinity, 48),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (done)
                          const Icon(Icons.check, size: 18)
                        else
                          const Icon(Icons.play_circle, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          done
                              ? 'Watched'
                              : 'Watch Ad ${i + 1}/${widget.adCount}',
                        ),
                      ],
                    ),
                  ),
                  if (i < widget.adCount - 1) const SizedBox(height: 8),
                ],
              );
            }),
            const SizedBox(height: 12),

            // Subscribe button
            if (widget.showSubscribeButton)
              ElevatedButton(
                onPressed: () async {
                  await widget.onAction('subscribe_clicked');
                  if (mounted) Navigator.pop(context, false);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  minimumSize: const Size(double.infinity, 48),
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.shopping_cart, size: 18),
                    SizedBox(width: 8),
                    Text('OR BUY SUBSCRIPTION'),
                  ],
                ),
              ),
          const SizedBox(height: 8),
          ],
        ),
      );
  }
}
