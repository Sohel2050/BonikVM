import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/about/about_screen.dart';
import '../../features/home/home_screen.dart';
import '../../features/privacy/privacy_policy_screen.dart';
import '../../features/servers/servers_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/premium/premium_screen.dart';
import '../../core/services/vpn_state.dart';
import '../../core/localization/app_localizations.dart';
import '../../features/support/support_screen.dart';
import '../../features/terms/terms_of_service_screen.dart';
import '../providers/app_providers.dart';
import '../providers/theme_provider.dart';
import 'modern_app_bar.dart';
import '../../widgets/level_play_native_ad.dart';

class _HomeNavItemSpec {
  const _HomeNavItemSpec({
    required this.icon,
    required this.label,
    required this.index,
    this.badge = false,
  });

  final IconData icon;
  final String label;
  final int index;
  final bool badge;
}

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

  final GlobalKey<ScaffoldState> _scaffoldKey =
  GlobalKey<ScaffoldState>();

  DateTime? _lastBackPressed;
  bool _hasRequestedReview = false;

  late List<Widget> _screens;

  @override
  void initState() {
    super.initState();

    _screens = [
      const HomeScreen(),
      ServersScreen(key: serversScreenKey),
      PremiumScreen(key: premiumScreenKey),
      const SettingsScreen(),
    ];

    _currentIndex = widget.initialIndex.clamp(
      0,
      _screens.length - 1,
    );

    _pageController = PageController(
      initialPage: _currentIndex,
      keepPage: true,
    );

    _checkReviewStatus();
  }

  // ------------------------------------------------------------
  // REVIEW
  // ------------------------------------------------------------

  Future<void> _checkReviewStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      if (!mounted) return;

      setState(() {
        _hasRequestedReview =
            prefs.getBool('has_requested_review') ?? false;
      });
    } catch (_) {}
  }

  Future<void> _checkAndTriggerReviewByUsage() async {
    if (_hasRequestedReview) return;

    try {
      final prefs = await SharedPreferences.getInstance();

      final launchCount =
          prefs.getInt('app_launch_count') ?? 0;

      final storedFirstLaunch =
      prefs.getInt('first_launch_date');

      final now = DateTime.now();

      final firstLaunchDate = storedFirstLaunch != null
          ? DateTime.fromMillisecondsSinceEpoch(
        storedFirstLaunch,
      )
          : now;

      await prefs.setInt(
        'app_launch_count',
        launchCount + 1,
      );

      if (storedFirstLaunch == null) {
        await prefs.setInt(
          'first_launch_date',
          now.millisecondsSinceEpoch,
        );
      }

      final daysSinceFirstLaunch =
          now.difference(firstLaunchDate).inDays;

      if (launchCount >= 5 &&
          daysSinceFirstLaunch >= 3 &&
          mounted &&
          !_hasRequestedReview) {
        Future.delayed(
          const Duration(seconds: 5),
              () {
            if (mounted && !_hasRequestedReview) {
              _triggerInAppReview();
            }
          },
        );
      }
    } catch (_) {}
  }

  Future<void> _triggerInAppReview() async {
    if (_hasRequestedReview) return;

    try {
      final inAppReview = InAppReview.instance;

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
    } catch (_) {
      _showCustomReviewDialog();
    }
  }

  void _showCustomReviewDialog() {
    if (!mounted) return;

    showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Row(
            children: [
              Icon(
                Icons.star,
                color: Colors.amber,
                size: 28,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text('Rate VPN MASTER'),
              ),
            ],
          ),
          content: const Text(
            'Great! You are connected to VPN successfully. '
                'Would you like to rate our app and share your experience?',
            style: TextStyle(fontSize: 16),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Maybe Later'),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(dialogContext).pop();

                _hasRequestedReview = true;

                try {
                  final prefs =
                  await SharedPreferences.getInstance();

                  await prefs.setBool(
                    'has_requested_review',
                    true,
                  );

                  await InAppReview.instance
                      .openStoreListing();
                } catch (_) {}
              },
              icon: const Icon(Icons.star_rate),
              label: const Text('Rate Now'),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------
  // NAVIGATION
  // ------------------------------------------------------------

  void _onTabTapped(int index) {
    if (index < 0 || index >= _screens.length) {
      return;
    }

    if (_currentIndex != index) {
      setState(() {
        _currentIndex = index;
      });
    }

    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    if (!mounted) return;

    setState(() {
      _currentIndex = index;
    });
  }

  void _navigateToTab(int index) {
    Navigator.of(context).pop();

    _onTabTapped(index);
  }

  // ------------------------------------------------------------
  // BACK BUTTON
  // ------------------------------------------------------------

  Future<bool> _onWillPop() async {
    final now = DateTime.now();

    const backPressDuration =
    Duration(seconds: 2);

    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) >
            backPressDuration) {
      _lastBackPressed = now;

      ScaffoldMessenger.of(context)
          .hideCurrentSnackBar();

      ScaffoldMessenger.of(context).showSnackBar(
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
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.cyan,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          margin: const EdgeInsets.all(16),
        ),
      );

      return false;
    }

    return true;
  }

  // ------------------------------------------------------------
  // LIFECYCLE
  // ------------------------------------------------------------

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // BUILD
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final isDarkMode =
        Theme.of(context).brightness ==
            Brightness.dark;

    final isPremium =
    ref.watch(premiumStatusProvider);

    final localizations =
    AppLocalizations.of(context);

    // VPN connection -> review
    ref.listen<AsyncValue<VpnState>>(
      vpnStateProvider,
          (previous, next) {
        next.whenData((state) {
          final previousState =
              previous?.value;

          if (previousState != VpnState.connected &&
              state == VpnState.connected) {
            Future.delayed(
              const Duration(seconds: 3),
                  () {
                if (mounted &&
                    !_hasRequestedReview) {
                  _triggerInAppReview();
                }
              },
            );
          }
        });
      },
    );

    // Usage based review check.
    // Only schedule once per mounted lifecycle.
    WidgetsBinding.instance
        .addPostFrameCallback((_) {
      if (mounted) {
        _checkAndTriggerReviewByUsage();
      }
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult:
          (didPop, result) async {
        if (didPop) return;

        final shouldPop =
        await _onWillPop();

        if (shouldPop && mounted) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        body: Column(
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
                  key: const Key(
                    'main_page_view',
                  ),
                  controller: _pageController,
                  onPageChanged: _onPageChanged,
                  physics:
                  const ClampingScrollPhysics(),
                  children: _screens,
                ),
              ),
            ),
          ],
        ),
        bottomNavigationBar:
        _buildPillBottomNavBar(
          isDarkMode,
          isPremium,
          localizations,
        ),
        drawer: _buildDrawer(
          context,
          isDarkMode,
          isPremium,
          localizations,
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // APP BAR
  // ------------------------------------------------------------

  Widget _buildModernAppBar(
      int currentIndex,
      bool isDarkMode,
      bool isPremium,
      AppLocalizations localizations,
      ) {
    switch (currentIndex) {
      case 0:
        return Container(
          color: isDarkMode
              ? Colors.black
              : Colors.white,
          padding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 10,
          ),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withValues(
                      alpha: 0.08,
                    )
                        : Colors.black.withValues(
                      alpha: 0.05,
                    ),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.menu_rounded,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(
                        0xFF1E293B,
                      ),
                      size: 28,
                    ),
                    onPressed: () {
                      _scaffoldKey.currentState
                          ?.openDrawer();
                    },
                    tooltip: 'Menu',
                  ),
                ),
                Expanded(
                  child: Center(
                    child: Row(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 42,
                          height: 40,
                          child: Image.asset(
                            'assets/icon.png',
                            fit: BoxFit.contain,
                            errorBuilder:
                                (
                                context,
                                error,
                                stackTrace,
                                ) {
                              return Image.asset(
                                'assets/images/app_icon.png',
                                fit: BoxFit.contain,
                                errorBuilder:
                                    (
                                    context,
                                    error,
                                    stackTrace,
                                    ) {
                                  return Icon(
                                    Icons
                                        .vpn_lock_rounded,
                                    size: 32,
                                    color: isDarkMode
                                        ? Colors.white
                                        : const Color(
                                      0xFF1E293B,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'VPN Master',
                          maxLines: 1,
                          overflow:
                          TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight:
                            FontWeight.w800,
                            color: isDarkMode
                                ? Colors.white
                                : const Color(
                              0xFF1E293B,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: () =>
                      _onTabTapped(2),
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration:
                    BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(
                        alpha: 0.08,
                      )
                          : Colors.black.withValues(
                        alpha: 0.05,
                      ),
                      borderRadius:
                      BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize:
                      MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons
                              .currency_exchange,
                          color:
                          Color(0xFFFFB020),
                          size: 19,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Premium',
                          style: TextStyle(
                            color: isDarkMode
                                ? Colors.white
                                : const Color(
                              0xFF1E293B,
                            ),
                            fontWeight:
                            FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );

      case 1:
        return ModernAppBar(
          title: 'Select Server',
          showBackButton: false,
          actions: [
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: isDarkMode
                    ? Colors.white
                    : const Color(0xFF1E293B),
                size: 33,
              ),
              onPressed: () {
                try {
                  ref.refresh(
                    serversProvider,
                  );
                } catch (_) {}
              },
              tooltip: 'Refresh Servers',
            ),
          ],
        );

      case 2:
        return ModernAppBar(
          title: 'SUBSCRIPTION',
          showBackButton: false,
          actions: [
            if (!isPremium)
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: isDarkMode
                      ? Colors.white
                      : const Color(
                    0xFF1E293B,
                  ),
                  size: 27,
                ),
                tooltip: 'Refresh Products',
                onPressed: () {
                  premiumScreenKey.currentState
                      ?.refreshProducts();
                },
              ),
          ],
        );

      case 3:
        return const ModernAppBar(
          title: 'Settings',
          showBackButton: false,
        );

      default:
        return MainAppBar(
          title: 'VPN MASTER',
          showLogo: true,
          actions: [
            IconButton(
              icon: Icon(
                Icons.menu,
                color: isDarkMode
                    ? Colors.white
                    : const Color(
                  0xFF1E293B,
                ),
                size: 42,
              ),
              onPressed: () {
                _scaffoldKey.currentState
                    ?.openDrawer();
              },
            ),
          ],
        );
    }
  }

  // ------------------------------------------------------------
  // BOTTOM NAV
  // ------------------------------------------------------------

  Widget _buildPillBottomNavBar(
      bool isDarkMode,
      bool isPremium,
      AppLocalizations localizations,
      ) {
    const selectedColor =
    Color(0xFFAEEA1C);

    final unselectedColor = isDarkMode
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF6B7280);

    final items =
    <_HomeNavItemSpec>[
      _HomeNavItemSpec(
        icon: Icons.home_rounded,
        label: localizations.home,
        index: 0,
      ),
      _HomeNavItemSpec(
        icon: Icons.public_rounded,
        label: localizations.servers,
        index: 1,
      ),
      _HomeNavItemSpec(
        icon: Icons.settings_rounded,
        label: localizations.settings,
        index: 3,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: isDarkMode
            ? Colors.black
            : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(
              alpha: 0.15,
            ),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 10,
        bottom:
        10 +
            MediaQuery.of(context)
                .padding
                .bottom,
      ),
      child: Row(
        mainAxisAlignment:
        MainAxisAlignment.spaceBetween,
        children: items.map((item) {
          final selected =
              _currentIndex == item.index;

          return GestureDetector(
            onTap: () =>
                _onTabTapped(item.index),
            behavior:
            HitTestBehavior.opaque,
            child: AnimatedContainer(
              duration:
              const Duration(milliseconds: 200),
              padding:
              const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: selected
                    ? selectedColor
                    : Colors.transparent,
                borderRadius:
                BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize:
                MainAxisSize.min,
                children: [
                  Icon(
                    item.icon,
                    size: 22,
                    color: selected
                        ? Colors.black87
                        : unselectedColor,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    item.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                      color: selected
                          ? Colors.black87
                          : unselectedColor,
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ------------------------------------------------------------
  // DRAWER
  // ------------------------------------------------------------

  Widget _buildDrawer(
      BuildContext context,
      bool isDarkMode,
      bool isPremium,
      AppLocalizations localizations,
      ) {
    final themeColor =
    ref.watch(themeColorProvider);

    return Drawer(
      backgroundColor: isDarkMode
          ? const Color(0xFF0F172A)
          : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                    const Color(
                        0xFF1E293B),
                    const Color(
                        0xFF334155),
                    themeColor.withValues(
                      alpha: 0.8,
                    ),
                  ]
                      : [
                    themeColor,
                    themeColor.withValues(
                      alpha: 0.8,
                    ),
                    themeColor.withValues(
                      alpha: 0.6,
                    ),
                  ],
                ),
              ),
              child: Padding(
                padding:
                const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment:
                  CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding:
                      const EdgeInsets.all(12),
                      decoration:
                      BoxDecoration(
                        color:
                        Colors.white.withValues(
                          alpha: 0.15,
                        ),
                        borderRadius:
                        BorderRadius.circular(
                          16,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius:
                        BorderRadius.circular(
                          8,
                        ),
                        child: Image.asset(
                          'assets/images/app_icon.png',
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
                              Icons.vpn_lock_sharp,
                              size: 32,
                              color: Colors.white,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 17),
                    const Text(
                      'VPN MASTER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight:
                        FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Container(
                          padding:
                          const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration:
                          BoxDecoration(
                            color: isPremium
                                ? const Color(
                                0xFF65645E)
                                : Colors.white
                                .withValues(
                              alpha: 0.2,
                            ),
                            borderRadius:
                            BorderRadius.circular(
                              12,
                            ),
                          ),
                          child: Text(
                            isPremium
                                ? 'PREMIUM'
                                : 'FREE',
                            style: TextStyle(
                              color: isPremium
                                  ? Colors.black
                                  : Colors.white,
                              fontSize: 10,
                              fontWeight:
                              FontWeight.bold,
                            ),
                          ),
                        ),
                        if (isPremium) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            color:
                            Color(0xFF3C3B38),
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fast & Secure VPN',
                      style: TextStyle(
                        color: Colors.white
                            .withValues(
                          alpha: 0.8,
                        ),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Expanded(
              child: ListView(
                padding:
                const EdgeInsets.only(
                  bottom: 10,
                ),
                children: [
                  _buildModernDrawerItem(
                    icon: Icons.home_rounded,
                    title:
                    localizations.home,
                    subtitle:
                    'Connection dashboard',
                    onTap: () =>
                        _navigateToTab(0),
                    isDarkMode: isDarkMode,
                  ),

                  if (!isPremium)
                    Container(
                      margin:
                      const EdgeInsets.fromLTRB(
                        16,
                        12,
                        16,
                        12,
                      ),
                      height: 80,
                      decoration:
                      BoxDecoration(
                        borderRadius:
                        BorderRadius.circular(
                          16,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius:
                        BorderRadius.circular(
                          16,
                        ),
                        child:
                        const LevelPlayNativeAdPlacement(
                          height: 80,
                        ),
                      ),
                    ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.privacy_tip,
                    title:
                    'Privacy Policy',
                    subtitle:
                    'Read our privacy policy',
                    onTap: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.description,
                    title:
                    'Terms & Conditions',
                    subtitle:
                    'Read our terms of service',
                    onTap: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const TermsOfServiceScreen(),
                        ),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.share_rounded,
                    title:
                    localizations.shareApp,
                    subtitle:
                    'Tell your friends',
                    onTap: _shareApp,
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.star_rate_rounded,
                    title:
                    localizations.rateApp,
                    subtitle:
                    '⭐⭐⭐⭐⭐',
                    onTap: () {
                      Navigator.pop(context);
                      _triggerInAppReview();
                    },
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.headset_mic,
                    title: 'Support',
                    subtitle:
                    'Get help with the app',
                    onTap: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const SupportScreen(),
                        ),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon:
                    Icons.info_outline,
                    title: 'About',
                    subtitle:
                    'App information and credits',
                    onTap: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) =>
                          const AboutScreen(),
                        ),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ),

            Container(
              padding:
              const EdgeInsets.symmetric(
                horizontal: 20,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? const Color(
                        0xFF334155)
                        : const Color(
                        0xFFE5E7EB),
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment:
                MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius:
                    BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorBuilder:
                          (_, __, ___) =>
                          Icon(
                            Icons.shield,
                            size: 24,
                            color: themeColor,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'VPN MASTER',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight:
                      FontWeight.bold,
                      color: isDarkMode
                          ? const Color(
                          0xFF94A3B8)
                          : const Color(
                          0xFF6B7280),
                      letterSpacing: 1.5,
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

  // ------------------------------------------------------------
  // DRAWER ITEM
  // ------------------------------------------------------------

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
      margin: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        borderRadius:
        BorderRadius.circular(16),
        color: isSelected
            ? themeColor.withValues(
          alpha: 0.12,
        )
            : Colors.transparent,
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: isSelected
                ? themeColor.withValues(
              alpha: 0.18,
            )
                : isDarkMode
                ? const Color(0xFF1E293B)
                : const Color(0xFFF3F4F6),
            borderRadius:
            BorderRadius.circular(12),
          ),
          child: Icon(
            icon,
            size: 20,
            color: isSelected
                ? themeColor
                : isDarkMode
                ? Colors.grey[400]
                : Colors.grey[600],
          ),
        ),
        title: Text(
          title,
          maxLines: 1,
          overflow:
          TextOverflow.ellipsis,
          style: TextStyle(
            color: isSelected
                ? themeColor
                : isDarkMode
                ? Colors.white
                : const Color(
                0xFF1F2937),
            fontWeight: isSelected
                ? FontWeight.bold
                : FontWeight.w500,
            fontSize: 15,
          ),
        ),
        subtitle: Text(
          subtitle,
          maxLines: 1,
          overflow:
          TextOverflow.ellipsis,
          style: TextStyle(
            color: isDarkMode
                ? Colors.grey[400]
                : Colors.grey[500],
            fontSize: 11,
          ),
        ),
        trailing: badge != null
            ? Container(
          padding:
          const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 4,
          ),
          decoration:
          BoxDecoration(
            color:
            const Color(0xFFEF4444),
            borderRadius:
            BorderRadius.circular(8),
          ),
          child: Text(
            badge,
            style:
            const TextStyle(
              color: Colors.white,
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

  // ------------------------------------------------------------
  // SHARE
  // ------------------------------------------------------------

  Future<void> _shareApp() async {
    Navigator.pop(context);

    try {
      const appUrl =
          'https://play.google.com/store/apps/details?id=com.albonik.vpn';

      const shareText = '''
🛡️ VPN MASTER - Secure & Fast VPN

Protect your privacy with VPN MASTER:

✅ Multi grade encryption
✅ 24+ server locations worldwide
✅ No-logs policy
✅ Lightning-fast speeds

Download now:
$appUrl

#VPNMASTER #VPN #Privacy #Security
''';

      await Share.share(
        shareText,
        subject:
        'VPN MASTER - Secure VPN for Everyone',
      );
    } catch (_) {
      if (!mounted) return;

      showDialog<void>(
        context: context,
        builder: (dialogContext) {
          return AlertDialog(
            title:
            const Text('Share VPN MASTER'),
            content: const Text(
              'Help us grow by sharing VPN MASTER '
                  'with your friends and family!\n\n'
                  'Search for "VPN MASTER" in your app store.',
            ),
            actions: [
              TextButton(
                onPressed: () =>
                    Navigator.pop(
                      dialogContext,
                    ),
                child:
                const Text('OK'),
              ),
            ],
          );
        },
      );
    }
  }

  // ------------------------------------------------------------
  // URL
  // ------------------------------------------------------------

  Future<void> _openUrl(String url) async {
    try {
      final uri = Uri.parse(url);

      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode:
          LaunchMode.externalApplication,
        );
      }
    } catch (_) {}
  }
}