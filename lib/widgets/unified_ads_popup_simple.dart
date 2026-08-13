import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/services/level_play_service.dart';

import '../core/services/level_play_service.dart';

import '../shared/providers/theme_provider.dart';

/// Unified LevelPlay Rewarded Ads Popup.
///
/// IMPORTANT:
///
/// Reward is granted ONLY from LevelPlay's:
///     onAdRewarded()
///
/// Reward is NEVER granted from:
/// - onAdClosed()
/// - onAdDisplayed()
/// - onAdDisplayFailed()
///
/// This prevents accidental premium unlock when the
/// rewarded ad is closed without completing the reward.
class UnifiedAdsPopupSimple extends ConsumerStatefulWidget {
  /// Called for every successfully completed rewarded ad.
  ///
  /// Possible actions:
  ///
  /// 'ad_watched'
  /// 'all_ads_watched'
  /// 'subscribe_clicked'
  final Future Function(String action) onAction;

  /// Called when user manually closes popup.
  final VoidCallback? onClosed;

  /// Optional information text.
  final String? customText;

  /// Number of rewarded ads required.
  ///
  /// Example:
  /// adCount = 2
  ///
  /// User must successfully complete 2 rewarded ads.
  final int adCount;

  /// Popup title.
  final String? title;

  /// Popup subtitle.
  final String? subtitle;

  /// Whether "Go Premium" button is visible.
  final bool showSubscribeButton;

  const UnifiedAdsPopupSimple({
    super.key,
    required this.onAction,
    this.onClosed,
    this.customText,
    this.adCount = 2,
    this.title,
    this.subtitle,
    this.showSubscribeButton = true,
  });

  @override
  ConsumerState<UnifiedAdsPopupSimple> createState() =>
      _UnifiedAdsPopupSimpleState();
}

class _UnifiedAdsPopupSimpleState
    extends ConsumerState<UnifiedAdsPopupSimple> {
  // ---------------------------------------------------------------------------
  // STATE
  // ---------------------------------------------------------------------------

  late final List<bool> _adWatched;

  int _rewardsEarned = 0;

  bool _allRewardsEarned = false;

  /// Prevent multiple showRewardedVideo() calls.
  bool _isShowingAd = false;

  /// Whether LevelPlay currently reports a rewarded ad as ready.
  bool _isAdReady = false;

  /// Prevent duplicate callback processing.
  bool _rewardCallbackReceived = false;

  /// Prevent duplicate final callback.
  bool _finalCallbackCalled = false;

  /// LevelPlay service.
  final LevelPlayService _levelPlayService =
      LevelPlayService.instance;

  @override
  void initState() {
    super.initState();

    debugPrint(
      '════════════════════════════════════════════════════',
    );
    debugPrint('✅ UnifiedAdsPopupSimple INIT');
    debugPrint('   Ad count: ${widget.adCount}');
    debugPrint(
      '════════════════════════════════════════════════════',
    );

    final count = widget.adCount > 0 ? widget.adCount : 1;

    _adWatched = List<bool>.filled(
      count,
      false,
    );

    _setupLevelPlayCallbacks();

    _checkAdAvailability();
  }

  // ---------------------------------------------------------------------------
  // LEVELPLAY CALLBACKS
  // ---------------------------------------------------------------------------

  void _setupLevelPlayCallbacks() {
    debugPrint(
      '[Popup] Registering LevelPlay rewarded callbacks',
    );

    _levelPlayService.setRewardedCallbacks(
      LevelPlayRewardedCallbacks(
        onOpened: _onAdOpened,
        onClosed: _onAdClosed,
        onRewarded: _onAdRewarded,
        onShowFailed: _onAdShowFailed,
        onAvailabilityChanged: _onAdAvailabilityChanged,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // AD AVAILABILITY
  // ---------------------------------------------------------------------------

  Future<void> _checkAdAvailability() async {
    if (!mounted) {
      return;
    }

    debugPrint(
      '[Popup] Checking LevelPlay rewarded availability...',
    );

    try {
      final available =
      await _levelPlayService.checkRewardedVideoAvailable();

      if (!mounted) {
        return;
      }

      setState(() {
        _isAdReady = available;
      });

      debugPrint(
        '[Popup] Rewarded available: $available',
      );
    } catch (e, st) {
      debugPrint(
        '[Popup] ❌ Availability check failed: $e',
      );

      debugPrint(
        '[Popup] Stack trace: $st',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isAdReady = false;
      });
    }
  }

  void _onAdAvailabilityChanged(bool available) {
    debugPrint(
      '[Popup] LevelPlay availability changed: $available',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isAdReady = available;
    });
  }

  // ---------------------------------------------------------------------------
  // AD OPENED
  // ---------------------------------------------------------------------------

  void _onAdOpened() {
    debugPrint(
      '[Popup] 🎬 LevelPlay rewarded ad OPENED',
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _isShowingAd = true;
    });
  }

  // ---------------------------------------------------------------------------
  // AD REWARDED
  // ---------------------------------------------------------------------------

  void _onAdRewarded(
      String rewardName,
      int rewardAmount,
      ) {
    debugPrint(
      '════════════════════════════════════════════════════',
    );

    debugPrint(
      '[Popup] 🏆 LEVELPLAY REWARD RECEIVED',
    );

    debugPrint(
      '[Popup] Reward name: $rewardName',
    );

    debugPrint(
      '[Popup] Reward amount: $rewardAmount',
    );

    debugPrint(
      '════════════════════════════════════════════════════',
    );

    if (!mounted) {
      debugPrint(
        '[Popup] ⚠️ Widget no longer mounted.',
      );

      return;
    }

    // Prevent duplicate reward callback.
    if (_rewardCallbackReceived) {
      debugPrint(
        '[Popup] ⚠️ Duplicate reward callback ignored.',
      );

      return;
    }

    _rewardCallbackReceived = true;

    _grantReward();
  }

  // ---------------------------------------------------------------------------
  // GRANT REWARD
  // ---------------------------------------------------------------------------

  void _grantReward() {
    if (!mounted) {
      return;
    }

    final index = _getNextRewardIndex();

    if (index == -1) {
      debugPrint(
        '[Popup] ⚠️ No remaining reward slot.',
      );

      return;
    }

    if (_adWatched[index]) {
      debugPrint(
        '[Popup] ⚠️ Slot $index already rewarded.',
      );

      return;
    }

    _adWatched[index] = true;

    _rewardsEarned++;

    if (_rewardsEarned > widget.adCount) {
      _rewardsEarned = widget.adCount;
    }

    debugPrint(
      '[Popup] ✅ Reward accepted for slot $index',
    );

    debugPrint(
      '[Popup] Progress: '
          '$_rewardsEarned/${widget.adCount}',
    );

    if (mounted) {
      setState(() {});
    }

    // -------------------------------------------------------------------------
    // PER-AD ACTION
    // -------------------------------------------------------------------------

    _callAdWatchedAction(index);

    // -------------------------------------------------------------------------
    // ALL ADS COMPLETED
    // -------------------------------------------------------------------------

    if (_rewardsEarned >= widget.adCount) {
      _allRewardsEarned = true;

      debugPrint(
        '════════════════════════════════════════════════════',
      );

      debugPrint(
        '[Popup] 🎉 ALL ${widget.adCount} ADS COMPLETED',
      );

      debugPrint(
        '════════════════════════════════════════════════════',
      );

      _callUnlockCallback();
    }
  }

  // ---------------------------------------------------------------------------
  // FIND NEXT SLOT
  // ---------------------------------------------------------------------------

  int _getNextRewardIndex() {
    for (int i = 0; i < _adWatched.length; i++) {
      if (!_adWatched[i]) {
        return i;
      }
    }

    return -1;
  }

  // ---------------------------------------------------------------------------
  // PER AD CALLBACK
  // ---------------------------------------------------------------------------

  Future<void> _callAdWatchedAction(
      int index,
      ) async {
    debugPrint(
      '[Popup] 🔔 Calling onAction(ad_watched)',
    );

    try {
      await widget.onAction(
        'ad_watched',
      );

      debugPrint(
        '[Popup] ✅ onAction(ad_watched) completed',
      );

      debugPrint(
        '[Popup] Reward slot: $index',
      );
    } catch (e, st) {
      debugPrint(
        '[Popup] ❌ onAction(ad_watched) failed: $e',
      );

      debugPrint(
        '[Popup] Stack trace: $st',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // AD CLOSED
  // ---------------------------------------------------------------------------

  void _onAdClosed() {
    debugPrint(
      '[Popup] 📺 LevelPlay rewarded ad CLOSED',
    );

    debugPrint(
      '[Popup] Reward was granted previously: '
          '$_rewardCallbackReceived',
    );

    // IMPORTANT:
    //
    // NEVER grant reward here.
    //
    // Reward is granted ONLY from onAdRewarded().

    _isShowingAd = false;

    if (!mounted) {
      return;
    }

    setState(() {
      _isAdReady = false;
    });

    // Reset callback guard for next rewarded ad.
    _rewardCallbackReceived = false;

    // If all ads are already completed, do not continue.
    if (_allRewardsEarned) {
      debugPrint(
        '[Popup] All rewards already completed.',
      );

      return;
    }

    // Give LevelPlay a little time to reload the next ad.
    Future.delayed(
      const Duration(milliseconds: 500),
          () {
        if (!mounted) {
          return;
        }

        _checkAdAvailability();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // AD SHOW FAILED
  // ---------------------------------------------------------------------------

  void _onAdShowFailed(
      String errorMessage,
      ) {
    debugPrint(
      '[Popup] ❌ LevelPlay rewarded ad SHOW FAILED',
    );

    debugPrint(
      '[Popup] Error: $errorMessage',
    );

    // IMPORTANT:
    //
    // No reward here.
    //

    _isShowingAd = false;
    _rewardCallbackReceived = false;

    if (!mounted) {
      return;
    }

    setState(() {
      _isAdReady = false;
    });

    _showSnackBar(
      'Ad failed to show. Please try again.',
    );

    Future.delayed(
      const Duration(milliseconds: 500),
          () {
        if (!mounted) {
          return;
        }

        _checkAdAvailability();
      },
    );
  }

  // ---------------------------------------------------------------------------
  // SHOW REWARDED AD
  // ---------------------------------------------------------------------------

  Future<void> _showAd(int index) async {
    debugPrint(
      '\n[Popup] 🎬 _showAd($index)',
    );

    if (!mounted) {
      debugPrint(
        '[Popup] ⚠️ Popup is not mounted.',
      );

      return;
    }

    if (index < 0 || index >= _adWatched.length) {
      debugPrint(
        '[Popup] ❌ Invalid ad index: $index',
      );

      return;
    }

    if (_isShowingAd) {
      debugPrint(
        '[Popup] ⚠️ Another rewarded ad is already showing.',
      );

      return;
    }

    if (_adWatched[index]) {
      debugPrint(
        '[Popup] ⚠️ Ad slot $index already completed.',
      );

      return;
    }

    if (_allRewardsEarned) {
      debugPrint(
        '[Popup] ⚠️ All rewards already earned.',
      );

      return;
    }

    // Check directly with LevelPlay before showing.
    final available =
    await _levelPlayService.checkRewardedVideoAvailable();

    if (!mounted) {
      return;
    }

    if (!available) {
      debugPrint(
        '[Popup] ❌ LevelPlay rewarded ad is NOT ready.',
      );

      setState(() {
        _isAdReady = false;
      });

      _showSnackBar(
        'Ad is not ready yet. Please wait...',
      );

      // Try checking again shortly.
      Future.delayed(
        const Duration(milliseconds: 700),
            () {
          if (mounted) {
            _checkAdAvailability();
          }
        },
      );

      return;
    }

    _rewardCallbackReceived = false;

    setState(() {
      _isShowingAd = true;
      _isAdReady = false;
    });

    debugPrint(
      '[Popup] ▶️ Showing LevelPlay rewarded ad',
    );

    debugPrint(
      '[Popup] Reward slot: $index',
    );

    try {
      await _levelPlayService.showRewardedVideo(
        placementName: 'premium_server_unlock',
      );
    } catch (e, st) {
      debugPrint(
        '[Popup] ❌ Error showing LevelPlay rewarded ad: $e',
      );

      debugPrint(
        '[Popup] Stack trace: $st',
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isShowingAd = false;
        _isAdReady = false;
      });

      _rewardCallbackReceived = false;

      _showSnackBar(
        'Error showing ad. Please try again.',
      );

      Future.delayed(
        const Duration(milliseconds: 500),
            () {
          if (mounted) {
            _checkAdAvailability();
          }
        },
      );
    }
  }

  // ---------------------------------------------------------------------------
  // FINAL UNLOCK
  // ---------------------------------------------------------------------------

  Future<void> _callUnlockCallback() async {
    if (!mounted) {
      return;
    }

    if (_finalCallbackCalled) {
      debugPrint(
        '[Popup] ⚠️ Final callback already called.',
      );

      return;
    }

    _finalCallbackCalled = true;

    debugPrint(
      '[Popup] 🔔 Calling onAction(all_ads_watched)',
    );

    try {
      await widget.onAction(
        'all_ads_watched',
      );

      debugPrint(
        '[Popup] ✅ onAction(all_ads_watched) completed',
      );

      if (!mounted) {
        return;
      }

      setState(() {});

      // Small delay so user can see completed state.
      await Future.delayed(
        const Duration(milliseconds: 600),
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(true);
    } catch (e, st) {
      debugPrint(
        '[Popup] ❌ Final unlock callback failed: $e',
      );

      debugPrint(
        '[Popup] Stack trace: $st',
      );

      _finalCallbackCalled = false;

      if (mounted) {
        _showSnackBar(
          'Error processing premium unlock.',
        );
      }
    }
  }

  // ---------------------------------------------------------------------------
  // SNACKBAR
  // ---------------------------------------------------------------------------

  void _showSnackBar(
      String message,
      ) {
    if (!mounted) {
      return;
    }

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            message,
          ),
          duration: const Duration(
            seconds: 2,
          ),
        ),
      );
  }

  // ---------------------------------------------------------------------------
  // CLOSE
  // ---------------------------------------------------------------------------

  void _closePopup() {
    debugPrint(
      '[Popup] ❎ Premium unlock popup closed by user',
    );

    widget.onClosed?.call();

    if (mounted) {
      Navigator.of(context).pop(false);
    }
  }

  // ---------------------------------------------------------------------------
  // DISPOSE
  // ---------------------------------------------------------------------------

  @override
  void dispose() {
    debugPrint(
      '[Popup] 🗑️ UnifiedAdsPopupSimple dispose',
    );

    // IMPORTANT:
    //
    // Do not dispose LevelPlayService here.
    //
    // It is a singleton shared by the entire app.
    //
    // We only clear this popup's callbacks.
    _levelPlayService.clearRewardedCallbacks();

    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(
      BuildContext context,
      ) {
    final isDarkMode =
        Theme.of(context).brightness ==
            Brightness.dark;

    final themeColor =
    ref.watch(themeColorProvider);

    final backgroundColor = isDarkMode
        ? const Color(0xFF1E293B)
        : Colors.white;

    final textColor = isDarkMode
        ? Colors.white
        : const Color(0xFF1A1A2E);

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius:
        const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        MediaQuery.of(context)
            .viewInsets
            .bottom +
            24,
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ---------------------------------------------------------------
              // DRAG HANDLE
              // ---------------------------------------------------------------

              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin:
                  const EdgeInsets.only(
                    bottom: 16,
                  ),
                  decoration:
                  BoxDecoration(
                    color: Colors.grey[400],
                    borderRadius:
                    BorderRadius.circular(
                      2,
                    ),
                  ),
                ),
              ),

              // ---------------------------------------------------------------
              // HEADER
              // ---------------------------------------------------------------

              Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.all(
                      9,
                    ),
                    decoration:
                    BoxDecoration(
                      color:
                      themeColor.withValues(
                        alpha: 0.12,
                      ),
                      borderRadius:
                      BorderRadius.circular(
                        12,
                      ),
                    ),
                    child: Icon(
                      Icons
                          .lock_open_rounded,
                      color: themeColor,
                      size: 22,
                    ),
                  ),

                  const SizedBox(
                    width: 12,
                  ),

                  Expanded(
                    child: Text(
                      widget.title ??
                          'Unlock Premium',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight:
                        FontWeight.w800,
                        color: textColor,
                      ),
                    ),
                  ),

                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDarkMode
                          ? Colors.grey[400]
                          : Colors.grey[600],
                    ),
                    onPressed:
                    _isShowingAd
                        ? null
                        : _closePopup,
                  ),
                ],
              ),

              // ---------------------------------------------------------------
              // SUBTITLE
              // ---------------------------------------------------------------

              if (widget.subtitle != null) ...[
                const SizedBox(
                  height: 4,
                ),
                Align(
                  alignment:
                  Alignment.centerLeft,
                  child: Text(
                    widget.subtitle!,
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode
                          ? Colors.grey[400]
                          : Colors.grey[600],
                    ),
                  ),
                ),
              ],

              const SizedBox(
                height: 8,
              ),

              // ---------------------------------------------------------------
              // CUSTOM TEXT
              // ---------------------------------------------------------------

              if (widget.customText != null) ...[
                Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.all(
                    14,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    themeColor.withValues(
                      alpha: 0.07,
                    ),
                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                  ),
                  child: Text(
                    widget.customText!,
                    textAlign:
                    TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: textColor,
                    ),
                  ),
                ),
                const SizedBox(
                  height: 16,
                ),
              ],

              // ---------------------------------------------------------------
              // MULTI AD PROGRESS
              // ---------------------------------------------------------------

              if (widget.adCount > 1)
                _buildProgressSection(
                  context,
                  isDarkMode,
                  themeColor,
                ),

              if (widget.adCount > 1)
                const SizedBox(
                  height: 20,
                ),

              // ---------------------------------------------------------------
              // SINGLE AD
              // ---------------------------------------------------------------

              if (widget.adCount == 1)
                _buildSingleAdSection(
                  context,
                  isDarkMode,
                  themeColor,
                ),

              // ---------------------------------------------------------------
              // MULTI ADS
              // ---------------------------------------------------------------

              if (widget.adCount > 1)
                _buildMultiAdButtons(
                  context,
                  themeColor,
                ),

              const SizedBox(
                height: 12,
              ),

              // ---------------------------------------------------------------
              // SUBSCRIBE
              // ---------------------------------------------------------------

              if (widget.showSubscribeButton)
                ElevatedButton(
                  onPressed: _isShowingAd
                      ? null
                      : () async {
                    try {
                      await widget
                          .onAction(
                        'subscribe_clicked',
                      );

                      if (mounted) {
                        Navigator.of(
                          context,
                        ).pop(false);
                      }
                    } catch (e) {
                      debugPrint(
                        '[Popup] ❌ Subscribe action error: $e',
                      );

                      if (mounted) {
                        _showSnackBar(
                          'Unable to open premium options.',
                        );
                      }
                    }
                  },
                  style:
                  ElevatedButton.styleFrom(
                    backgroundColor:
                    Colors.amber,
                    disabledBackgroundColor:
                    Colors.grey,
                    foregroundColor:
                    Colors.black87,
                    minimumSize:
                    const Size(
                      double.infinity,
                      48,
                    ),
                    shape:
                    RoundedRectangleBorder(
                      borderRadius:
                      BorderRadius.circular(
                        14,
                      ),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment:
                    MainAxisAlignment
                        .center,
                    children: [
                      Icon(
                        Icons
                            .shopping_cart,
                        size: 18,
                      ),
                      SizedBox(
                        width: 8,
                      ),
                      Text(
                        'Or Go Premium',
                        style: TextStyle(
                          fontWeight:
                          FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),

              const SizedBox(
                height: 8,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // PROGRESS SECTION
  // ---------------------------------------------------------------------------

  Widget _buildProgressSection(
      BuildContext context,
      bool isDarkMode,
      Color themeColor,
      ) {
    return Container(
      padding:
      const EdgeInsets.all(16),
      decoration:
      BoxDecoration(
        color: isDarkMode
            ? Colors.grey[800]
            : Colors.grey[200],
        borderRadius:
        BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Text(
            _allRewardsEarned
                ? 'All ads completed'
                : 'Watch ads to unlock',
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(
              fontWeight:
              FontWeight.w600,
            ),
          ),

          const SizedBox(
            height: 12,
          ),

          // Progress circles
          SingleChildScrollView(
            scrollDirection:
            Axis.horizontal,
            child: Row(
              mainAxisAlignment:
              MainAxisAlignment.center,
              children:
              List.generate(
                widget.adCount,
                    (i) {
                  final done =
                  _adWatched[i];

                  return Container(
                    margin:
                    const EdgeInsets
                        .symmetric(
                      horizontal: 5,
                    ),
                    width: 40,
                    height: 40,
                    decoration:
                    BoxDecoration(
                      shape:
                      BoxShape.circle,
                      color: done
                          ? Colors.green
                          : themeColor,
                    ),
                    child: Center(
                      child: done
                          ? const Icon(
                        Icons.check,
                        color:
                        Colors.white,
                        size: 20,
                      )
                          : Text(
                        '${i + 1}',
                        style:
                        const TextStyle(
                          color:
                          Colors.white,
                          fontWeight:
                          FontWeight
                              .bold,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),

          const SizedBox(
            height: 10,
          ),

          Text(
            '$_rewardsEarned/${widget.adCount} completed',
            style: TextStyle(
              fontSize: 12,
              color: isDarkMode
                  ? Colors.grey[400]
                  : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // SINGLE AD SECTION
  // ---------------------------------------------------------------------------

  Widget _buildSingleAdSection(
      BuildContext context,
      bool isDarkMode,
      Color themeColor,
      ) {
    final watched =
        _adWatched.isNotEmpty &&
            _adWatched[0];

    return Column(
      children: [
        Container(
          width: double.infinity,
          padding:
          const EdgeInsets.all(16),
          decoration:
          BoxDecoration(
            color: isDarkMode
                ? Colors.grey[800]
                : Colors.grey[100],
            borderRadius:
            BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(
                watched
                    ? Icons
                    .check_circle_rounded
                    : Icons
                    .play_circle_fill_rounded,
                color: watched
                    ? Colors.green
                    : themeColor,
                size: 54,
              ),

              const SizedBox(
                height: 12,
              ),

              Text(
                watched
                    ? 'Premium server unlocked!'
                    : 'Watch a short video to unlock this server for free',
                textAlign:
                TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode
                      ? Colors.grey[300]
                      : Colors.grey[700],
                ),
              ),

              if (!watched &&
                  !_isAdReady) ...[
                const SizedBox(
                  height: 10,
                ),
                const SizedBox(
                  width: 20,
                  height: 20,
                  child:
                  CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
                const SizedBox(
                  height: 6,
                ),
                Text(
                  'Loading ad...',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? Colors.grey[400]
                        : Colors.grey[600],
                  ),
                ),
              ],
            ],
          ),
        ),

        const SizedBox(
          height: 20,
        ),

        ElevatedButton.icon(
          onPressed:
          watched ||
              _isShowingAd ||
              !_isAdReady
              ? null
              : () => _showAd(0),
          icon: watched
              ? const Icon(
            Icons.check,
            size: 22,
          )
              : const Icon(
            Icons
                .play_circle_outline_rounded,
            size: 22,
          ),
          label: Text(
            watched
                ? 'Unlocked!'
                : _isAdReady
                ? 'Watch Video to Unlock'
                : 'Loading Ad...',
            style:
            const TextStyle(
              fontSize: 15,
              fontWeight:
              FontWeight.w700,
            ),
          ),
          style:
          ElevatedButton.styleFrom(
            backgroundColor: watched
                ? Colors.green
                : themeColor,
            disabledBackgroundColor:
            Colors.grey,
            foregroundColor:
            Colors.white,
            minimumSize:
            const Size(
              double.infinity,
              52,
            ),
            shape:
            RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(
                14,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // MULTI AD BUTTONS
  // ---------------------------------------------------------------------------

  Widget _buildMultiAdButtons(
      BuildContext context,
      Color themeColor,
      ) {
    return Column(
      children: List.generate(
        widget.adCount,
            (i) {
          final done =
          _adWatched[i];

          final enabled =
              !done &&
                  _isAdReady &&
                  !_isShowingAd &&
                  !_allRewardsEarned;

          return Padding(
            padding:
            const EdgeInsets.only(
              bottom: 8,
            ),
            child: ElevatedButton(
              onPressed: enabled
                  ? () => _showAd(i)
                  : null,
              style:
              ElevatedButton.styleFrom(
                backgroundColor: done
                    ? Colors.green
                    : themeColor,
                disabledBackgroundColor:
                Colors.grey,
                padding:
                const EdgeInsets
                    .symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                minimumSize:
                const Size(
                  double.infinity,
                  48,
                ),
                shape:
                RoundedRectangleBorder(
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment
                    .center,
                children: [
                  if (done)
                    const Icon(
                      Icons.check,
                      size: 18,
                    )
                  else if (!_isAdReady)
                    const SizedBox(
                      width: 17,
                      height: 17,
                      child:
                      CircularProgressIndicator(
                        strokeWidth: 2,
                        color:
                        Colors.white,
                      ),
                    )
                  else
                    const Icon(
                      Icons
                          .play_circle,
                      size: 18,
                    ),

                  const SizedBox(
                    width: 8,
                  ),

                  Text(
                    done
                        ? 'Watched'
                        : _isAdReady
                        ? 'Watch Ad ${i + 1}/${widget.adCount}'
                        : 'Loading Ad ${i + 1}/${widget.adCount}...',
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}