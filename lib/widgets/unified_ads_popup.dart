import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/services/admob_service.dart';
import '../shared/providers/theme_provider.dart';

/// Unified Ads Popup for all scenarios
/// Replaces: BuySubscriptionAdsPopup, PremiumServerUnlockAdsPopup, RewardVideoPopup, PremiumServerUnlockPopup
class UnifiedAdsPopup extends ConsumerStatefulWidget {
  /// Callback when action is taken
  /// - 'all_ads_watched': User watched all required ads
  /// - 'subscribe_clicked': User clicked subscribe button
  final Future<void> Function(String action) onAction;

  /// Optional callback when popup is closed
  final VoidCallback? onClosed;

  /// Custom text to display (from admin panel)
  final String? customText;

  /// Number of ads to show (1, 2, or 3)
  /// Default: 3
  final int adCount;

  /// Title text for popup (default based on adCount)
  final String? title;

  /// Subtitle text
  final String? subtitle;

  /// Show "Or Go Premium" button (yellow button)
  final bool showSubscribeButton;

  const UnifiedAdsPopup({
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
  ConsumerState<UnifiedAdsPopup> createState() => _UnifiedAdsPopupState();
}

class _UnifiedAdsPopupState extends ConsumerState<UnifiedAdsPopup> {
  late List<bool> _watchingVideo;
  late List<bool> _videoShowingAd;
  late List<RewardedAd?> _rewardedAds;
  late List<bool> _canWatchVideo;

  @override
  void initState() {
    print('🎬 POPUP INIT START'); // Using print() instead of debugPrint
    super.initState();
    debugPrint('\n🎬 === UnifiedAdsPopup.initState() STARTED ===');
    debugPrint('   AdCount: ${widget.adCount}');

    _watchingVideo = List.filled(widget.adCount, false);
    _videoShowingAd = List.filled(widget.adCount, false);
    _rewardedAds = List.filled(widget.adCount, null);
    _canWatchVideo = List.filled(widget.adCount, true);

    debugPrint('   ✅ Lists initialized');

    // Load all ads
    debugPrint('   🎬 Starting to load ${widget.adCount} ads...');
    for (int i = 0; i < widget.adCount; i++) {
      debugPrint('   📺 About to call _loadRewardedAd($i)...');
      _loadRewardedAd(i);
      debugPrint('   📺 _loadRewardedAd($i) returned');
    }
    debugPrint(
      '✅ UnifiedAdsPopup.initState() COMPLETED - all load calls made\n',
    );
  }

  @override
  void dispose() {
    for (var ad in _rewardedAds) {
      ad?.dispose();
    }
    super.dispose();
  }

  /// Load rewarded ad for specific index
  void _loadRewardedAd(int index) {
    try {
      print('📺 LOADING AD $index'); // Using print()
      debugPrint('\n📺 Ad $index: Starting load...');
      debugPrint('   Ad Unit ID: ${AdMobService.instance.rewardedAdUnitId}');

      setState(() {
        _videoShowingAd[index] = true;
      });

      debugPrint('   📺 Ad $index: Calling RewardedAd.load()...');

      RewardedAd.load(
        adUnitId: AdMobService.instance.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            print('✅ AD $index LOADED'); // Using print()
            debugPrint('✅ Ad $index: onAdLoaded callback FIRED');
            if (mounted && index < _rewardedAds.length) {
              debugPrint('✅ Ad $index: LOADED successfully');
              setState(() {
                _rewardedAds[index] = ad;
                _videoShowingAd[index] = false;
              });
              debugPrint('✅ Ad $index: Stored in state, ready to watch');
            } else {
              debugPrint(
                '⚠️ Ad $index: mounted=$mounted, index valid=${index < _rewardedAds.length}',
              );
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint('❌ Ad $index: onAdFailedToLoad callback FIRED');
            debugPrint('❌ Ad $index: FAILED to load - Error: $error');
            if (mounted && index < _videoShowingAd.length) {
              setState(() {
                _videoShowingAd[index] = false;
              });
            }
          },
        ),
      );

      debugPrint(
        '   📺 Ad $index: RewardedAd.load() call completed (async in progress)',
      );
    } catch (e, st) {
      debugPrint('❌ Exception in _loadRewardedAd($index): $e');
      debugPrint('   Stack: $st');
      if (mounted && index < _videoShowingAd.length) {
        setState(() {
          _videoShowingAd[index] = false;
        });
      }
    }
  }

  /// Handle video reward for specific video
  Future<void> _handleVideoReward(int videoIndex) async {
    try {
      debugPrint(
        '\n📺 Ad $videoIndex: ========== HANDLING WATCH REQUEST ==========',
      );
      debugPrint(
        '   canWatch=${_canWatchVideo[videoIndex]}, watching=${_watchingVideo[videoIndex]}, ready=${_rewardedAds[videoIndex] != null}',
      );

      if (!_canWatchVideo[videoIndex]) {
        debugPrint('   ⚠️ Video already watched');
        _showErrorSnackBar('This video has already been watched.');
        return;
      }

      final ad = _rewardedAds[videoIndex];
      if (ad == null) {
        debugPrint('   ⚠️ Ad not loaded yet');
        _showErrorSnackBar('Ad not ready yet. Please try again.');
        return;
      }

      setState(() {
        _watchingVideo[videoIndex] = true;
      });
      debugPrint('   ✅ Ad $videoIndex showing to user...');

      // CRITICAL: Set callbacks BEFORE showing the ad
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) async {
          debugPrint('   ⬅️ Ad $videoIndex dismissed (no reward)');
          ad.dispose();
          if (mounted && videoIndex < _watchingVideo.length) {
            setState(() {
              _watchingVideo[videoIndex] = false;
            });
          }
          // Reload ad
          _loadRewardedAd(videoIndex);
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          debugPrint('   ❌ Ad $videoIndex failed to show: $error');
          ad.dispose();
          if (mounted && videoIndex < _watchingVideo.length) {
            setState(() {
              _watchingVideo[videoIndex] = false;
            });
          }
          _showErrorSnackBar('Failed to show ad: $error');
          _loadRewardedAd(videoIndex);
        },
      );

      debugPrint('   ✅ Callbacks registered, now showing ad...');

      // NOW show the ad after callbacks are set
      await ad.show(
        onUserEarnedReward: (ad, reward) async {
          print('🎬 REWARD FIRED FOR AD $videoIndex'); // Using print()
          debugPrint(
            '\n🎬 Ad $videoIndex: ========== REWARD EARNED ==========',
          );
          debugPrint(
            '   Reward type: ${reward.type}, Amount: ${reward.amount}',
          );

          // Mark video as watched
          if (mounted && videoIndex < _canWatchVideo.length) {
            setState(() {
              _canWatchVideo[videoIndex] = false;
            });
            debugPrint('   ✅ Ad $videoIndex marked as watched');
          }

          // Check if all videos are watched
          debugPrint(
            '   📊 Current watch status: ${_canWatchVideo.map((e) => e ? "pending" : "watched").toList()}',
          );
          bool allWatched = _canWatchVideo.every((element) => element == false);
          debugPrint('   📊 All watched check: $allWatched');

          if (allWatched) {
            print('✅ ALL ADS WATCHED - CALLING onAction'); // Using print()
            debugPrint('\n✅✅✅ ALL ADS WATCHED (Count: ${widget.adCount}) ✅✅✅');
            debugPrint('   Calling parent onAction callback...\n');

            try {
              await widget.onAction('all_ads_watched');
              debugPrint('✅ Parent onAction completed successfully');
            } catch (e, st) {
              debugPrint('❌ Error in onAction: $e');
              debugPrint('   Stack: $st');
            }

            // Close popup after a small delay
            if (mounted) {
              await Future.delayed(const Duration(milliseconds: 200));
              if (mounted) {
                debugPrint('🔚 Closing popup...');
                Navigator.of(context).pop(true);
              }
            }
          } else {
            debugPrint(
              '   ⏳ Waiting for more ads... (${_canWatchVideo.where((e) => e).length} remaining)',
            );
          }
        },
      );
    } catch (e, st) {
      if (mounted && videoIndex < _watchingVideo.length) {
        setState(() {
          _watchingVideo[videoIndex] = false;
        });
      }
      debugPrint('❌ Exception in _handleVideoReward($videoIndex): $e');
      debugPrint('   Stack trace: $st');
      _showErrorSnackBar('Error displaying ad. Please try again.');
    }
  }

  /// Show error snackbar
  void _showErrorSnackBar(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Build a single video button
  Widget _buildVideoButton(int index, bool isDarkMode, Color themeColor) {
    final canWatch = _canWatchVideo[index];
    final isWatching = _watchingVideo[index];
    final isLoading = _videoShowingAd[index];
    final adReady = _rewardedAds[index] != null;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: !canWatch || isWatching || !adReady
            ? null
            : () async {
                await _handleVideoReward(index);
              },
        style: ElevatedButton.styleFrom(
          backgroundColor: !canWatch ? Colors.grey : themeColor,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          disabledBackgroundColor: Colors.grey,
        ),
        child: !canWatch
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check, size: 18),
                  SizedBox(width: 8),
                  Text('Watched'),
                ],
              )
            : isWatching
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('Watching...'),
                ],
              )
            : isLoading
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2,
                    ),
                  ),
                  SizedBox(width: 8),
                  Text('Loading...'),
                ],
              )
            : !adReady
            ? const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.cloud_off, size: 18),
                  SizedBox(width: 8),
                  Text('Ad Not Ready'),
                ],
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.play_circle, size: 18),
                  const SizedBox(width: 8),
                  Text('Watch Ad ${index + 1}/${widget.adCount}'),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('\n🎬 UnifiedAdsPopup.build() called');
    debugPrint(
      '   _canWatchVideo: ${_canWatchVideo.map((e) => e ? "pending" : "watched").toList()}',
    );
    debugPrint(
      '   _rewardedAds loaded: ${_rewardedAds.map((e) => e != null ? "✓" : "✗").toList()}',
    );

    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeColor = ref.watch(themeColorProvider);
    final textColor = isDarkMode ? Colors.white : Colors.black87;

    // Generate default title if not provided
    String title = widget.title ?? 'Watch ${widget.adCount} Ads to Unlock';

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: isDarkMode ? Colors.grey[900] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header with close button
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                // Close button (X)
                GestureDetector(
                  onTap: () {
                    if (widget.onClosed != null) {
                      widget.onClosed!();
                    }
                    Navigator.of(context).pop(false);
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, color: textColor, size: 24),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Header Icon
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.2),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.tv, color: themeColor, size: 32),
            ),
            const SizedBox(height: 16),

            // Subtitle
            if (widget.subtitle != null)
              Text(
                widget.subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              )
            else if (widget.customText != null)
              Text(
                widget.customText!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            if (widget.subtitle != null || widget.customText != null)
              const SizedBox(height: 24),

            // Progress indicator
            if (widget.adCount > 1)
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  widget.adCount,
                  (index) => Container(
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: !_canWatchVideo[index] ? Colors.green : themeColor,
                      border: Border.all(color: themeColor, width: 2),
                    ),
                    child: Center(
                      child: !_canWatchVideo[index]
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 20,
                            )
                          : Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            if (widget.adCount > 1) const SizedBox(height: 24),

            // Video buttons
            ...List.generate(
              widget.adCount,
              (index) => Column(
                children: [
                  _buildVideoButton(index, isDarkMode, themeColor),
                  if (index < widget.adCount - 1) const SizedBox(height: 12),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Subscribe Button (if enabled)
            if (widget.showSubscribeButton)
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    try {
                      debugPrint('🛒 Subscribe button clicked');
                      await widget.onAction('subscribe_clicked');
                      debugPrint('🛒 Parent handled subscribe action');
                    } catch (e) {
                      debugPrint('❌ Error in subscribe action: $e');
                    }
                  },
                  icon: const Icon(Icons.shopping_cart),
                  label: const Text('Or Go Premium'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.yellow,
                    foregroundColor: Colors.black87,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
