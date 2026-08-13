import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter/material.dart';
import 'package:ironsource_mediation/ironsource_mediation.dart';


import '../../core/services/level_play_service.dart';
import '../../features/home/home_screen.dart';
import '../../features/servers/servers_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/privacy/privacy_policy_screen.dart';
import '../../features/terms/terms_of_service_screen.dart';
import '../../features/support/support_screen.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/providers/vpn_provider.dart';
import '../providers/app_providers.dart';
import '../providers/theme_provider.dart';
import '../../providers/auth_providers.dart';
import 'modern_app_bar.dart';

class MainShell extends ConsumerStatefulWidget {
  final int initialIndex;

  const MainShell({
    super.key,
    this.initialIndex = 0,
  });

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;
  late final PageController _pageController;
  late final ProviderSubscription _vpnSubscription;

  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();

  DateTime? _lastBackPressed;

  bool _hasRequestedReview = false;

  // Prevent duplicate disconnect interstitial calls.
  bool _disconnectAdShowingOrStarting = false;

  // Prevent review usage check from running repeatedly.
  bool _reviewUsageChecked = false;

  final List<Widget> _screens = [
    const HomeScreen(),
    ServersScreen(key: serversScreenKey),
    const SettingsScreen(),
  ];

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _currentIndex = widget.initialIndex.clamp(
      0,
      _screens.length - 1,
    );

    _pageController = PageController(
      initialPage: _currentIndex,
      keepPage: true,
    );

    _checkReviewStatus();

    // IMPORTANT:
    // VPN listener must NOT be inside build().
    _vpnSubscription = ref.listenManual<VpnState>(
      vpnProvider,
          (previous, next) {
        _handleVpnStateChange(
          previous,
          next,
        );
      },
    );
  }

  // ============================================================
  // VPN STATE CHANGE
  // ============================================================

  void _handleVpnStateChange(
      VpnState? previous,
      VpnState next,
      ) {
    debugPrint(
      '[HOME VPN] State changed: $previous → $next',
    );

    // ==========================================================
    // VPN CONNECTED
    // ==========================================================

    if (previous != VpnState.connected &&
        next == VpnState.connected) {
      debugPrint(
        '[HOME VPN] ✅ VPN connected',
      );

      Future.delayed(
        const Duration(seconds: 3),
            () {
          if (mounted && !_hasRequestedReview) {
            _triggerInAppReview();
          }
        },
      );

      return;
    }

    // ==========================================================
    // VPN FULLY DISCONNECTED
    // ==========================================================
    //
    // IMPORTANT:
    //
    // Ad ONLY triggers on:
    //
    // connected → disconnected
    //
    // It does NOT trigger on:
    //
    // disconnecting → disconnected
    // unknown → disconnected
    // connecting → disconnected
    //
    // ==========================================================

    if (previous == VpnState.connected &&
        next == VpnState.disconnected) {
      debugPrint(
        '[HOME VPN] ❌ VPN fully disconnected',
      );

      _showDisconnectInterstitial();

      return;
    }

    // ==========================================================
    // OTHER VPN STATE CHANGES
    // ==========================================================

    debugPrint(
      '[HOME VPN] ℹ️ No disconnect ad trigger '
          'for this transition',
    );
  }

  // ============================================================
  // LEVELPLAY INTERSTITIAL AFTER FULL DISCONNECT
  // ============================================================

  Future<void> _showDisconnectInterstitial() async {
    if (!mounted) {
      return;
    }

    // Prevent duplicate calls.
    if (_disconnectAdShowingOrStarting) {
      debugPrint(
        '[HOME ADS] ⚠️ Disconnect interstitial '
            'already starting/showing',
      );
      return;
    }

    _disconnectAdShowingOrStarting = true;

    try {
      // Give VPN state/UI time to settle.
      await Future.delayed(
        const Duration(milliseconds: 700),
      );

      if (!mounted) {
        return;
      }

      final levelPlay = LevelPlayService.instance;

      debugPrint(
        '[HOME ADS] ─────────────────────────────',
      );

      debugPrint(
        '[HOME ADS] 🔍 Checking LevelPlay '
            'disconnect interstitial...',
      );

      debugPrint(
        '[HOME ADS] Initialized: '
            '${levelPlay.isInitialized}',
      );

      // ========================================================
      // REFRESH PREMIUM STATUS
      // ========================================================

      try {
        await levelPlay.refreshPremiumStatus();
      } catch (e) {
        debugPrint(
          '[HOME ADS] ⚠️ Premium refresh error: $e',
        );
      }

      if (!mounted) {
        return;
      }

      // ========================================================
      // CHECK LEVELPLAY INITIALIZATION
      // ========================================================

      if (!levelPlay.isInitialized) {
        debugPrint(
          '[HOME ADS] ❌ LevelPlay is NOT initialized',
        );

        return;
      }

      // ========================================================
      // REQUEST DISCONNECT INTERSTITIAL
      // ========================================================
      //
      // LevelPlayService handles:
      //
      // READY
      //   → show immediately
      //
      // NOT READY
      //   → load ad
      //   → onAdLoaded()
      //   → automatically show
      //
      // ========================================================

      debugPrint(
        '[HOME ADS] 🎬 Requesting disconnect '
            'interstitial...',
      );

      await levelPlay.showDisconnectInterstitial();

      debugPrint(
        '[HOME ADS] ✅ Disconnect interstitial '
            'request completed',
      );
    } catch (e, stackTrace) {
      debugPrint(
        '[HOME ADS] ❌ Disconnect interstitial error: $e',
      );

      debugPrint(
        '[HOME ADS] StackTrace: $stackTrace',
      );
    } finally {
      _disconnectAdShowingOrStarting = false;

      debugPrint(
        '[HOME ADS] ─────────────────────────────',
      );
    }
  }

  // ============================================================
  // REVIEW STATUS
  // ============================================================

  Future<void> _checkReviewStatus() async {
    try {
      final prefs =
      await SharedPreferences.getInstance();

      if (!mounted) {
        return;
      }

      setState(() {
        _hasRequestedReview =
            prefs.getBool(
              'has_requested_review',
            ) ??
                false;
      });
    } catch (e) {
      debugPrint(
        '[REVIEW] Error checking review status: $e',
      );
    }
  }

  // ============================================================
  // REVIEW BY USAGE
  // ============================================================

  Future<void> _checkAndTriggerReviewByUsage() async {
    if (_reviewUsageChecked) {
      return;
    }

    _reviewUsageChecked = true;

    if (_hasRequestedReview) {
      return;
    }

    try {
      final prefs =
      await SharedPreferences.getInstance();

      final launchCount =
          prefs.getInt(
            'app_launch_count',
          ) ??
              0;

      final storedFirstLaunchDate =
      prefs.getInt(
        'first_launch_date',
      );

      final now =
          DateTime.now().millisecondsSinceEpoch;

      final firstLaunchDate =
          storedFirstLaunchDate ?? now;

      // Increment launch count.
      await prefs.setInt(
        'app_launch_count',
        launchCount + 1,
      );

      // Save first launch date if missing.
      if (storedFirstLaunchDate == null) {
        await prefs.setInt(
          'first_launch_date',
          now,
        );
      }

      final daysSinceFirstLaunch =
          DateTime.now()
              .difference(
            DateTime.fromMillisecondsSinceEpoch(
              firstLaunchDate,
            ),
          )
              .inDays;

      debugPrint(
        '[REVIEW] Launch: $launchCount '
            '| Days: $daysSinceFirstLaunch',
      );

      // Trigger after 5 launches and 3 days.
      if (launchCount >= 5 &&
          daysSinceFirstLaunch >= 3) {
        Future.delayed(
          const Duration(seconds: 5),
              () {
            if (mounted &&
                !_hasRequestedReview) {
              _triggerInAppReview();
            }
          },
        );
      }
    } catch (e) {
      debugPrint(
        '[REVIEW] Usage check error: $e',
      );
    }
  }

  // ============================================================
  // TAB NAVIGATION
  // ============================================================

  void _onTabTapped(int index) {
    if (index < 0 ||
        index >= _screens.length) {
      return;
    }

    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });

    _pageController.animateToPage(
      index,
      duration: const Duration(
        milliseconds: 300,
      ),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (!mounted) {
      return;
    }

    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });
  }

  // ============================================================
  // BACK / EXIT
  // ============================================================

  Future<bool> _onWillPop() async {
    final now = DateTime.now();

    const backPressDuration =
    Duration(seconds: 2);

    if (_lastBackPressed == null ||
        now.difference(
          _lastBackPressed!,
        ) >
            backPressDuration) {
      _lastBackPressed = now;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(
                  Icons.exit_to_app,
                  color: Colors.redAccent,
                  size: 22,
                ),
                SizedBox(width: 8),
                Text(
                  'Double Back To Exit',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            duration: const Duration(
              seconds: 2,
            ),
            behavior:
            SnackBarBehavior.floating,
            backgroundColor:
            Colors.cyan,
            shape:
            RoundedRectangleBorder(
              borderRadius:
              BorderRadius.circular(8),
            ),
            margin:
            const EdgeInsets.all(16),
          ),
        );

      return false;
    }

    return true;
  }

  // ============================================================
  // IN APP REVIEW
  // ============================================================

  Future<void> _triggerInAppReview() async {
    if (_hasRequestedReview) {
      return;
    }

    try {
      final InAppReview inAppReview =
          InAppReview.instance;

      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();

        _hasRequestedReview = true;

        final prefs =
        await SharedPreferences.getInstance();

        await prefs.setBool(
          'has_requested_review',
          true,
        );
      } else {
        _showCustomReviewDialog();
      }
    } catch (e) {
      debugPrint(
        '[REVIEW] System review error: $e',
      );

      _showCustomReviewDialog();
    }
  }

  // ============================================================
  // CUSTOM REVIEW DIALOG
  // ============================================================

  void _showCustomReviewDialog() {
    if (!mounted) {
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (
          BuildContext dialogContext,
          ) {
        return PopScope(
          canPop: true,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(
                  Icons.star,
                  color: Colors.blueGrey,
                  size: 28,
                ),
                SizedBox(width: 8),
                Text('Rate VPN MASTER'),
              ],
            ),
            content: const Text(
              'Great! You\'re connected to VPN successfully. '
                  'Would you like to rate our app and share your experience?',
              style: TextStyle(
                fontSize: 16,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(
                    dialogContext,
                  ).pop();
                },
                child: const Text(
                  'Maybe Later',
                ),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(
                    dialogContext,
                  ).pop();

                  _hasRequestedReview = true;

                  final prefs =
                  await SharedPreferences
                      .getInstance();

                  await prefs.setBool(
                    'has_requested_review',
                    true,
                  );

                  try {
                    final InAppReview
                    inAppReview =
                        InAppReview.instance;

                    await inAppReview
                        .openStoreListing();
                  } catch (e) {
                    debugPrint(
                      '[REVIEW] Store listing error: $e',
                    );
                  }
                },
                icon: const Icon(
                  Icons.star_rate,
                ),
                label: const Text(
                  'Rate Now',
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    debugPrint(
      '[MAIN SHELL] Disposing',
    );

    _vpnSubscription.close();

    _pageController.dispose();

    super.dispose();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Theme.of(context).brightness ==
            Brightness.dark;

    final isPremium =
    ref.watch(
      premiumStatusProvider,
    );

    final localizations =
    AppLocalizations.of(context);

    // Run usage review check only once.
    if (!_reviewUsageChecked) {
      WidgetsBinding.instance
          .addPostFrameCallback(
            (_) {
          if (mounted) {
            _checkAndTriggerReviewByUsage();
          }
        },
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) async {
        if (!didPop) {
          final shouldPop =
          await _onWillPop();

          if (shouldPop &&
              context.mounted) {
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        key: _scaffoldKey,

        // ======================================================
        // BODY
        // ======================================================

        body: Stack(
          children: [
            // Background image.
            Positioned.fill(
              child: Image.asset(
                'assets/images/bg2.png',
                fit: BoxFit.cover,
              ),
            ),

            // Dark overlay.
            Positioned.fill(
              child: Container(
                color:
                Colors.black.withValues(
                  alpha: 0.2,
                ),
              ),
            ),

            // Main content.
            Column(
              children: [
                _buildModernAppBar(
                  _currentIndex,
                  isDarkMode,
                  isPremium,
                  localizations,
                ),
                Expanded(
                  child: SafeArea(
                    top: false,
                    child: PageView(
                      controller:
                      _pageController,
                      onPageChanged:
                      _onPageChanged,
                      physics:
                      const ClampingScrollPhysics(),
                      children: _screens,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // ======================================================
        // BOTTOM NAVIGATION
        // ======================================================

        bottomNavigationBar:
        Container(
          decoration: BoxDecoration(
            boxShadow: [
              BoxShadow(
                color:
                Colors.black.withValues(
                  alpha: 0.1,
                ),
                blurRadius: 10,
                offset:
                const Offset(0, -5),
              ),
            ],
          ),
          child:
          BottomNavigationBar(
            currentIndex:
            _currentIndex,
            onTap:
            _onTabTapped,
            type:
            BottomNavigationBarType.fixed,
            backgroundColor:
            isDarkMode
                ? const Color(
              0xFF1E293B,
            )
                : Colors.white,
            selectedItemColor:
            ref.watch(
              themeColorProvider,
            ),
            unselectedItemColor:
            isDarkMode
                ? Colors.grey[400]
                : Colors.grey[600],
            elevation: 0,
            selectedLabelStyle:
            const TextStyle(
              fontWeight:
              FontWeight.w600,
              fontSize: 12,
            ),
            unselectedLabelStyle:
            const TextStyle(
              fontWeight:
              FontWeight.w400,
              fontSize: 11,
            ),
            items: [
              _buildBottomNavItem(
                icon:
                Icons.home_rounded,
                label:
                localizations.home,
                index: 0,
              ),
              _buildBottomNavItem(
                icon:
                Icons.public,
                label:
                localizations.servers,
                index: 1,
              ),
              _buildBottomNavItem(
                icon:
                Icons.settings_rounded,
                label:
                localizations.settings,
                index: 2,
              ),
            ],
          ),
        ),

        // ======================================================
        // DRAWER
        // ======================================================

        drawer: _buildDrawer(
          context,
          isDarkMode,
          isPremium,
          localizations,
        ),
      ),
    );
  }

  // ============================================================
  // MODERN APP BAR
  // ============================================================

  Widget _buildModernAppBar(
      int currentIndex,
      bool isDarkMode,
      bool isPremium,
      AppLocalizations localizations,
      ) {
    switch (currentIndex) {
      case 0:
        return MainAppBar(
          title: 'VPN MASTER ',
          showLogo: false,
          leading: IconButton(
            icon: Icon(
              Icons.menu,
              color: isDarkMode
                  ? Colors.white
                  : const Color(0xFF1E293B),
              size: 42,
            ),
            onPressed: () {
              _scaffoldKey.currentState
                  ?.openDrawer();
            },
            tooltip: 'Menu',
          ),
          actions: [
            if (!isPremium)
              GestureDetector(
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/premium',
                  );
                },
                child: Container(
                  margin:
                  const EdgeInsets.only(
                    right: 12,
                  ),
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration:
                  BoxDecoration(
                    color:
                    const Color(0xFFD97706),
                    borderRadius:
                    BorderRadius.circular(
                      20,
                    ),
                  ),
                  child: const Row(
                    mainAxisSize:
                    MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.workspace_premium,
                        color:
                        Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 4),
                      Text(
                        'Premium',
                        style: TextStyle(
                          color:
                          Colors.white,
                          fontWeight:
                          FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        );

      case 1:
        return MainAppBar(
          title: 'Select Server ',
          showLogo: false,
          leading: IconButton(
            icon: Icon(
              Icons.menu,
              color: isDarkMode
                  ? Colors.white
                  : const Color(0xFF1E293B),
              size: 42,
            ),
            onPressed: () {
              _scaffoldKey.currentState
                  ?.openDrawer();
            },
            tooltip: 'Menu',
          ),
          actions: [
            IconButton(
              icon: Icon(
                Icons.filter_list,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1E293B),
                size: 24,
              ),
              tooltip: 'Filter',
              onPressed: () {
                serversScreenKey
                    .currentState
                    ?.triggerFilterDialog();
              },
            ),
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1E293B),
                size: 24,
              ),
              tooltip: 'Refresh',
              onPressed: () {
                ref.invalidate(
                  serversProvider,
                );
              },
            ),
          ],
        );

      case 2:
        return const ModernAppBar(
          title: 'Settings',
          showBackButton: false,
        );

      default:
        return MainAppBar(
          title: 'VPN MASTER',
          showLogo: false,
          leading: IconButton(
            icon: Icon(
              Icons.menu,
              color: isDarkMode
                  ? Colors.white
                  : const Color(0xFF1E293B),
              size: 42,
            ),
            onPressed: () {
              _scaffoldKey.currentState
                  ?.openDrawer();
            },
          ),
          actions: const [],
        );
    }
  }

  // ============================================================
  // BOTTOM NAV ITEM
  // ============================================================

  BottomNavigationBarItem
  _buildBottomNavItem({
    required IconData icon,
    required String label,
    required int index,
    bool badge = false,
  }) {
    return BottomNavigationBarItem(
      icon: Stack(
        children: [
          FadeInUp(
            delay: Duration(
              milliseconds:
              index * 100,
            ),
            child: Icon(
              icon,
              size:
              _currentIndex == index
                  ? 28
                  : 24,
            ),
          ),
          if (badge)
            Positioned(
              right: 0,
              top: 0,
              child: Container(
                padding:
                const EdgeInsets.all(2),
                decoration:
                const BoxDecoration(
                  color: Colors.red,
                  shape:
                  BoxShape.circle,
                ),
                constraints:
                const BoxConstraints(
                  minWidth: 8,
                  minHeight: 8,
                ),
              ),
            ),
        ],
      ),
      label: label,
    );
  }

  // ============================================================
  // DRAWER
  // ============================================================

  Widget _buildDrawer(
      BuildContext context,
      bool isDarkMode,
      bool isPremium,
      AppLocalizations localizations,
      ) {
    final themeColor =
    ref.watch(themeColorProvider);

    return Drawer(
      backgroundColor:
      isDarkMode
          ? const Color(0xFF0F172A)
          : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ==================================================
            // HEADER
            // ==================================================

            Container(
              height: 200,
              width: double.infinity,
              decoration:
              BoxDecoration(
                gradient:
                LinearGradient(
                  begin:
                  Alignment.topLeft,
                  end:
                  Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                    const Color(
                      0xFF1E293B,
                    ),
                    const Color(
                      0xFF334155,
                    ),
                    themeColor
                        .withValues(
                      alpha: 0.8,
                    ),
                  ]
                      : [
                    themeColor,
                    themeColor
                        .withValues(
                      alpha: 0.8,
                    ),
                    themeColor
                        .withValues(
                      alpha: 0.6,
                    ),
                  ],
                ),
              ),
              child: Padding(
                padding:
                const EdgeInsets.all(
                  20,
                ),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment
                      .start,
                  children: [
                    Container(
                      padding:
                      const EdgeInsets.all(
                        12,
                      ),
                      decoration:
                      BoxDecoration(
                        color: Colors.white
                            .withValues(
                          alpha: 0.15,
                        ),
                        borderRadius:
                        BorderRadius
                            .circular(
                          16,
                        ),
                        border:
                        Border.all(
                          color: Colors.white
                              .withValues(
                            alpha: 0.2,
                          ),
                          width: 1,
                        ),
                      ),
                      child:
                      ClipRRect(
                        borderRadius:
                        BorderRadius
                            .circular(
                          8,
                        ),
                        child:
                        Image.asset(
                          'assets/images/logo1.png',
                          width: 31,
                          height: 31,
                          fit: BoxFit.contain,
                          errorBuilder:
                              (
                              context,
                              error,
                              stackTrace,
                              ) {
                            return const Icon(
                              Icons
                                  .vpn_lock_sharp,
                              size: 32,
                              color:
                              Colors.white,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(
                      height: 17,
                    ),
                    const Text(
                      'VPN MASTER',
                      style:
                      TextStyle(
                        color:
                        Colors.white,
                        fontSize: 23,
                        fontWeight:
                        FontWeight.bold,
                        letterSpacing:
                        1.2,
                      ),
                    ),
                    const SizedBox(
                      height: 4,
                    ),
                    Row(
                      children: [
                        Container(
                          padding:
                          const EdgeInsets
                              .symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration:
                          BoxDecoration(
                            color: isPremium
                                ? const Color(
                              0xFF65645E,
                            )
                                : Colors.white
                                .withValues(
                              alpha: 0.2,
                            ),
                            borderRadius:
                            BorderRadius
                                .circular(
                              12,
                            ),
                          ),
                          child: Text(
                            isPremium
                                ? 'PREMIUM'
                                : 'FREE',
                            style:
                            TextStyle(
                              color: isPremium
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: 10,
                              fontWeight:
                              FontWeight.bold,
                              letterSpacing:
                              0.5,
                            ),
                          ),
                        ),
                        if (isPremium) ...[
                          const SizedBox(
                            width: 6,
                          ),
                          const Icon(
                            Icons.verified,
                            color:
                            Color(0xFF3C3B38),
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    Text(
                      'Fast & Secure VPN',
                      style:
                      TextStyle(
                        color: Colors.white
                            .withValues(
                          alpha: 0.8,
                        ),
                        fontSize: 13,
                        fontWeight:
                        FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ==================================================
            // NAVIGATION
            // ==================================================

            Expanded(
              child: ListView(
                padding:
                const EdgeInsets.only(
                  bottom: 0,
                ),
                children: [
                  const SizedBox(
                    height: 8,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.privacy_tip,
                    title:
                    'Privacy Policy',
                    subtitle:
                    'Read our privacy policy',
                    onTap: () {
                      Navigator.pop(
                        context,
                      );

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                    isDarkMode:
                    isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.description,
                    title:
                    'Terms & Conditions',
                    subtitle:
                    'Read our terms of service',
                    onTap: () {
                      Navigator.pop(
                        context,
                      );

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const TermsOfServiceScreen(),
                        ),
                      );
                    },
                    isDarkMode:
                    isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.share_rounded,
                    title:
                    localizations.shareApp,
                    subtitle:
                    'Tell your friends',
                    onTap:
                    _shareApp,
                    isDarkMode:
                    isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.headset_mic,
                    title:
                    'Support',
                    subtitle:
                    'Get help with the app',
                    onTap: () {
                      Navigator.pop(
                        context,
                      );

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const SupportScreen(),
                        ),
                      );
                    },
                    isDarkMode:
                    isDarkMode,
                  ),

                  // ==================================================
                  // DARK MODE
                  // ==================================================

                  Container(
                    margin:
                    const EdgeInsets
                        .symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    child: ListTile(
                      leading:
                      Container(
                        padding:
                        const EdgeInsets
                            .all(
                          8,
                        ),
                        decoration:
                        BoxDecoration(
                          color: isDarkMode
                              ? Colors
                              .grey[800]
                              : Colors
                              .grey[100],
                          borderRadius:
                          BorderRadius
                              .circular(
                            10,
                          ),
                        ),
                        child: Icon(
                          isDarkMode
                              ? Icons.dark_mode
                              : Icons.light_mode,
                          size: 20,
                          color: isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                      title: Text(
                        'Dark Mode',
                        style:
                        TextStyle(
                          color: isDarkMode
                              ? Colors.white
                              : Colors.black87,
                          fontWeight:
                          FontWeight.w500,
                          fontSize: 15,
                        ),
                      ),
                      subtitle:
                      Text(
                        isDarkMode
                            ? 'Currently enabled'
                            : 'Currently disabled',
                        style:
                        TextStyle(
                          color: isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                      trailing:
                      Switch(
                        value:
                        ref.watch(
                          themeModeProvider,
                        ) ==
                            ThemeMode.dark,
                        onChanged:
                            (value) {
                          ref
                              .read(
                            themeModeProvider
                                .notifier,
                          )
                              .setThemeMode(
                            value
                                ? ThemeMode.dark
                                : ThemeMode.light,
                          );
                        },
                        activeColor:
                        themeColor,
                      ),
                      contentPadding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DRAWER ITEM
  // ============================================================

  Widget _buildModernDrawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDarkMode,
    bool isSelected = false,
    String? badge,
  }) {
    final themeColor =
    ref.watch(themeColorProvider);

    return Container(
      margin:
      const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 2,
      ),
      decoration:
      BoxDecoration(
        borderRadius:
        BorderRadius.circular(
          12,
        ),
        color: isSelected
            ? themeColor.withValues(
          alpha: 0.1,
        )
            : Colors.transparent,
      ),
      child: ListTile(
        leading:
        Container(
          padding:
          const EdgeInsets.all(
            8,
          ),
          decoration:
          BoxDecoration(
            color: isSelected
                ? themeColor.withValues(
              alpha: 0.2,
            )
                : (isDarkMode
                ? Colors.grey[800]
                : Colors.grey[100]),
            borderRadius:
            BorderRadius.circular(
              10,
            ),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected
                ? themeColor
                : (isDarkMode
                ? Colors.grey[400]
                : Colors.grey[600]),
          ),
        ),
        title: Text(
          title,
          style: TextStyle(
            color: isSelected
                ? themeColor
                : (isDarkMode
                ? Colors.white
                : Colors.black87),
            fontWeight: isSelected
                ? FontWeight.w600
                : FontWeight.w500,
            fontSize: 15,
          ),
        ),
        subtitle:
        Text(
          subtitle,
          style:
          TextStyle(
            color: isDarkMode
                ? Colors.grey[400]
                : Colors.grey[600],
            fontSize: 12,
          ),
        ),
        trailing: badge != null
            ? Container(
          padding:
          const EdgeInsets
              .symmetric(
            horizontal: 6,
            vertical: 2,
          ),
          decoration:
          BoxDecoration(
            color:
            const Color(
              0xFFFF6B6B,
            ),
            borderRadius:
            BorderRadius
                .circular(
              8,
            ),
          ),
          child: Text(
            badge,
            style:
            const TextStyle(
              color:
              Colors.white,
              fontSize: 9,
              fontWeight:
              FontWeight.bold,
            ),
          ),
        )
            : null,
        contentPadding:
        const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 4,
        ),
        onTap: onTap,
      ),
    );
  }

  // ============================================================
  // SHARE APP
  // ============================================================

  Future<void> _shareApp() async {
    Navigator.pop(context);

    try {
      const String appUrl =
          'https://play.google.com/store/apps/details?id=com.albonik.vpn';

      const String shareText = '''
🛡️ VPN MASTER - Secure & Fast VPN

Protect your privacy with VPN MASTER:

✅ Multi-grade encryption
✅ 12+ server locations worldwide
✅ No-logs policy
✅ Fast & secure connection

Download now and get premium features!

$appUrl

#VPNMASTER #VPN #Privacy #Security
''';

      await Share.share(
        shareText,
        subject:
        'VPN MASTER - Secure VPN for Everyone',
      );
    } catch (e) {
      debugPrint(
        '[SHARE] Error: $e',
      );

      if (!mounted) {
        return;
      }

      showDialog(
        context: context,
        builder:
            (dialogContext) {
          return AlertDialog(
            title:
            const Text(
              'Share VPN MASTER',
            ),
            content:
            const Text(
              'Help us grow by sharing VPN MASTER '
                  'with your friends and family!\n\n'
                  'Search for "VPN MASTER" in your app store.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(
                    dialogContext,
                  );
                },
                child:
                const Text(
                  'OK',
                ),
              ),
            ],
          );
        },
      );
    }
  }

  // ============================================================
  // NAVIGATE TO TAB
  // ============================================================

  void _navigateToTab(int index) {
    Navigator.pop(context);

    if (index < 0 ||
        index >= _screens.length) {
      return;
    }

    if (_currentIndex == index) {
      return;
    }

    setState(() {
      _currentIndex = index;
    });

    _pageController.animateToPage(
      index,
      duration:
      const Duration(
        milliseconds: 300,
      ),
      curve:
      Curves.easeInOut,
    );
  }
}