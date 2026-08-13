import 'package:vpn_master/core/api/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../core/services/admob_service.dart';
import '../core/localization/app_localizations.dart';
import '../shared/providers/theme_provider.dart';
import '../core/services/vpn_state.dart';

/// Callback for when video is watched for premium server unlock
typedef OnPremiumVideoWatched = Future<void> Function(int videoIndex);
typedef OnPremiumSubscriptionPressed = Future<void> Function();

/// Premium Server Unlock Popup - Shows 3 ad options to temporarily unlock premium server
class PremiumServerUnlockPopup extends ConsumerStatefulWidget {
  /// Server being unlocked
  final VpnServer server;

  /// Called when user watches a video
  final OnPremiumVideoWatched onVideoWatched;

  /// Called when user clicks subscribe
  final OnPremiumSubscriptionPressed onSubscriptionPressed;

  /// Which videos can still be watched (0-indexed)
  final List<bool> canWatchVideo;

  /// Current watched count
  final int watchedCount;

  /// Total available videos per day
  final int maxVideos;

  /// Minutes added per ad watch (from API config)
  final int durationMinutes;

  const PremiumServerUnlockPopup({
    super.key,
    required this.server,
    required this.onVideoWatched,
    required this.onSubscriptionPressed,
    required this.canWatchVideo,
    this.watchedCount = 0,
    this.maxVideos = 3,
    this.durationMinutes = 5,
  });

  @override
  ConsumerState<PremiumServerUnlockPopup> createState() =>
      _PremiumServerUnlockPopupState();
}

class _PremiumServerUnlockPopupState
    extends ConsumerState<PremiumServerUnlockPopup> {
  late List<bool> _watchingVideo;
  late List<bool> _videoShowingAd;
  late List<RewardedAd?> _rewardedAds;

  @override
  void initState() {
    super.initState();
    _watchingVideo = List.filled(widget.maxVideos, false);
    _videoShowingAd = List.filled(widget.maxVideos, false);
    _rewardedAds = List.filled(widget.maxVideos, null);

    // Preload rewarded ads for all videos
    _preloadRewardedAds();
  }

  @override
  void dispose() {
    // Dispose all ads
    for (final ad in _rewardedAds) {
      ad?.dispose();
    }
    super.dispose();
  }

  /// Preload rewarded ads for all videos
  void _preloadRewardedAds() {
    for (int i = 0; i < widget.maxVideos; i++) {
      _loadRewardedAd(i);
    }
  }

  /// Load a single rewarded ad
  void _loadRewardedAd(int videoIndex) {
    try {
      RewardedAd.load(
        adUnitId: AdMobService.instance.rewardedAdUnitId,
        request: const AdRequest(),
        rewardedAdLoadCallback: RewardedAdLoadCallback(
          onAdLoaded: (ad) {
            if (mounted) {
              setState(() {
                _rewardedAds[videoIndex] = ad;
              });
              debugPrint('✅ Rewarded ad loaded for premium video $videoIndex');
            }
          },
          onAdFailedToLoad: (error) {
            debugPrint(
              '❌ Failed to load rewarded ad for premium video $videoIndex: $error',
            );
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ Error loading rewarded ad: $e');
    }
  }

  /// Handle video reward for premium server unlock
  Future<void> _handleVideoReward(int videoIndex) async {
    try {
      if (!widget.canWatchVideo[videoIndex]) {
        _showErrorSnackBar('This video has already been watched today.');
        return;
      }

      final ad = _rewardedAds[videoIndex];
      if (ad == null) {
        _showErrorSnackBar('Ad not ready yet. Please try again.');
        return;
      }

      setState(() {
        _watchingVideo[videoIndex] = true;
      });

      bool rewardGrantedByCallback = false;
      bool rewardProcessed = false;

      Future<void> processRewardOnce() async {
        if (rewardProcessed) return;
        rewardProcessed = true;

        debugPrint('✅ Processing reward for ad $videoIndex');

        // Notify parent that video was watched
        try {
          debugPrint('📞 Calling parent onVideoWatched($videoIndex)...');
          await widget.onVideoWatched(videoIndex);
          debugPrint('📞 Parent onVideoWatched completed');
        } catch (e) {
          debugPrint('❌ Error in onVideoWatched: $e');
        }

        // ✅ AUTO-DISMISS popup after watching ad so server can unlock
        debugPrint('📱 AUTO-DISMISSING popup with result=true');

        // Schedule pop on next frame to ensure context is valid
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            try {
              Navigator.of(context).pop(true);
              debugPrint('✅ Navigator.pop(true) executed');
            } catch (e) {
              debugPrint('❌ Error in Navigator.pop: $e');
            }
          }
        });
      }

      // Show the rewarded ad
      ad.fullScreenContentCallback = FullScreenContentCallback(
        onAdDismissedFullScreenContent: (ad) async {
          ad.dispose();
          setState(() {
            _watchingVideo[videoIndex] = false;
          });
          // Reload ad for potential future use
          _loadRewardedAd(videoIndex);

          // Fallback for SIMID / callback-miss cases.
          if (!rewardGrantedByCallback) {
            debugPrint(
              '⚠️ onUserEarnedReward did not fire for ad $videoIndex - applying fallback reward on dismiss',
            );
            await processRewardOnce();
          }
        },
        onAdFailedToShowFullScreenContent: (ad, error) {
          ad.dispose();
          setState(() {
            _watchingVideo[videoIndex] = false;
          });
          _showErrorSnackBar('Failed to show ad: $error');
          _loadRewardedAd(videoIndex);
        },
      );

      await ad.show(
        onUserEarnedReward: (ad, reward) async {
          // User watched the ad successfully
          debugPrint('✅ User earned reward for ad $videoIndex');
          rewardGrantedByCallback = true;
          await processRewardOnce();
        },
      );
    } catch (e) {
      setState(() {
        _watchingVideo[videoIndex] = false;
      });
      debugPrint('❌ Error showing rewarded ad for premium: $e');
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
  Widget _buildVideoButton(
    int index,
    bool isDarkMode,
    Color themeColor,
    Color textColor,
    Color secondaryTextColor,
  ) {
    final canWatch = widget.canWatchVideo[index];
    final isLoading = _videoShowingAd[index];
    final isWatching = _watchingVideo[index];
    final adReady = _rewardedAds[index] != null;

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: canWatch
              ? themeColor
              : (isDarkMode ? Colors.grey[700]! : Colors.grey[300]!),
          width: 2,
        ),
        color: canWatch
            ? themeColor.withValues(alpha: 0.1)
            : (isDarkMode ? Colors.grey[900] : Colors.grey[100]),
      ),
      child: InkWell(
        onTap: canWatch && adReady && !isWatching
            ? () => _handleVideoReward(index)
            : null,
        child: Column(
          children: [
            // Video title with loading indicator
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    'AD-${index + 1}',
                    style: TextStyle(
                      color: canWatch ? textColor : secondaryTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (isWatching || isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                      strokeWidth: 2,
                    ),
                  )
                else if (!canWatch)
                  const Icon(Icons.check_circle, color: Colors.green)
                else if (!adReady)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(themeColor),
                      strokeWidth: 2,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            // Reward info
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '+ ${widget.durationMinutes} ${widget.durationMinutes == 1 ? 'Minute' : 'Minutes'}',
                  style: TextStyle(
                    color: canWatch ? themeColor : secondaryTextColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  canWatch ? (adReady ? 'Watch Now' : 'Loading...') : 'Watched',
                  style: TextStyle(
                    color: canWatch ? textColor : secondaryTextColor,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final localizations = AppLocalizations.of(context);
    final remainingVideos = widget.maxVideos - widget.watchedCount;
    final allVideosWatched = remainingVideos <= 0;

    // Get theme colors from provider
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final themeColor = ref.watch(themeColorProvider);
    final backgroundColor = isDarkMode ? const Color(0xFF0F172A) : Colors.white;
    final surfaceColor = isDarkMode
        ? const Color(0xFF1E293B)
        : Colors.grey[100]!;
    final textColor = isDarkMode ? Colors.white : Colors.black87;
    final secondaryTextColor = isDarkMode
        ? (Colors.grey[400] ?? Colors.grey)
        : (Colors.grey[600] ?? Colors.grey);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
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
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.lock_outline, color: themeColor, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Extend Server Time',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      Text(
                        widget.server.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: secondaryTextColor,
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(context).pop(false),
                  child: Container(
                    decoration: BoxDecoration(
                      color: surfaceColor,
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(8),
                    child: Icon(Icons.close, color: textColor, size: 20),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Video buttons section (only show if videos remain)
            if (!allVideosWatched)
              Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: themeColor.withValues(alpha: 0.1),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: themeColor, size: 20),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Watch ${remainingVideos} video${remainingVideos > 1 ? 's' : ''} to unlock for temporary access',
                            style: TextStyle(color: themeColor, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Video options - AD-1, AD-2, AD-3
                  ...List.generate(
                    widget.maxVideos,
                    (index) => _buildVideoButton(
                      index,
                      isDarkMode,
                      themeColor,
                      textColor,
                      secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Divider
                  Container(
                    height: 1,
                    color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
                    margin: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ],
              ),

            // Subscribe button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: () async {
                  await widget.onSubscriptionPressed();
                  if (mounted) {
                    Navigator.of(context).pop(true);
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: themeColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 4,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: const [
                    Icon(Icons.shopping_bag, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Text(
                      'Upgrade',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Status text (if all videos watched)
            if (allVideosWatched)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  'Daily video limit reached. Upgrade to Premium for unlimited access.',
                  style: TextStyle(
                    color: secondaryTextColor,
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Show premium server unlock bottom sheet
Future<bool> showPremiumServerUnlockPopup({
  required BuildContext context,
  required VpnServer server,
  required OnPremiumVideoWatched onVideoWatched,
  required OnPremiumSubscriptionPressed onSubscriptionPressed,
  required List<bool> canWatchVideo,
  int watchedCount = 0,
  int maxVideos = 3,
  int durationMinutes = 5,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (BuildContext context) => PremiumServerUnlockPopup(
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
