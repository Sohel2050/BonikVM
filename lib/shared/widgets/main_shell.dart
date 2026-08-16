import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
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
import '../../core/services/update_service.dart';
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

  const MainShell({super.key, this.initialIndex = 0});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  late int _currentIndex;
  late final PageController _pageController;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  DateTime? _lastBackPressed;
  bool _hasRequestedReview = false;
  NativeAd? _drawerNativeAd;
  bool _isDrawerNativeAdLoaded = false;

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
    // Ensure initialIndex is within bounds
    _currentIndex = widget.initialIndex.clamp(0, _screens.length - 1);
    _pageController = PageController(
      initialPage: _currentIndex,
      keepPage: true,
      viewportFraction: 1.0,
    );
    _checkReviewStatus();
    _initializeDrawerNativeAd();

    // Ask the backend whether this installed version is below the
    // admin-configured minimum — if force_update is on, this shows a
    // blocking dialog the user can't dismiss until they update.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        UpdateService.instance.checkForUpdates(context: context);
      }
    });
  }

  void _initializeDrawerNativeAd() {
    // The LevelPlay native widget below owns its own lifecycle.
  }

  void _disposeDrawerNativeAd() {
    _drawerNativeAd?.dispose();
    _drawerNativeAd = null;
    _isDrawerNativeAdLoaded = false;
  }

  /// Check if we've already requested review from shared preferences
  void _checkReviewStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _hasRequestedReview = prefs.getBool('has_requested_review') ?? false;
    } catch (e) {}
  }

  /// Check app usage patterns and trigger review if appropriate
  void _checkAndTriggerReviewByUsage() async {
    if (_hasRequestedReview) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final launchCount = prefs.getInt('app_launch_count') ?? 0;
      final firstLaunchDate =
          prefs.getInt('first_launch_date') ??
          DateTime.now().millisecondsSinceEpoch;

      // Increment launch count
      await prefs.setInt('app_launch_count', launchCount + 1);

      // Set first launch date if not set
      if (prefs.getInt('first_launch_date') == null) {
        await prefs.setInt(
          'first_launch_date',
          DateTime.now().millisecondsSinceEpoch,
        );
      }

      final daysSinceFirstLaunch = DateTime.now()
          .difference(DateTime.fromMillisecondsSinceEpoch(firstLaunchDate))
          .inDays;

      // Trigger review after 5 launches and at least 3 days of usage
      if (launchCount >= 5 && daysSinceFirstLaunch >= 3) {
        Future.delayed(const Duration(seconds: 5), () {
          if (mounted && !_hasRequestedReview) {
            _triggerInAppReview();
          }
        });
      }
    } catch (e) {}
  }

  void _onTabTapped(int index) {
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _onPageChanged(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  /// Handle double tap to exit functionality
  Future<bool> _onWillPop() async {
    final now = DateTime.now();
    const backPressDuration = Duration(seconds: 2);

    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) > backPressDuration) {
      _lastBackPressed = now;

      // Show snackbar with icon and better styling
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.exit_to_app, color: Colors.redAccent, size: 22),
              const SizedBox(width: 8),
              const Text(
                'Double Back To Exit',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.cyan,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          margin: const EdgeInsets.all(16),
        ),
      );
      return false;
    }

    // Exit app
    return true;
  }

  /// Trigger in-app review when VPN connects successfully
  void _triggerInAppReview() async {
    if (_hasRequestedReview) return;

    try {
      final InAppReview inAppReview = InAppReview.instance;

      // First try system in-app review
      if (await inAppReview.isAvailable()) {
        await inAppReview.requestReview();
        _hasRequestedReview = true;

        // Store that we've requested review
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('has_requested_review', true);
      } else {
        // Show custom review dialog if system review not available
        _showCustomReviewDialog();
      }
    } catch (e) {
      // Fallback to custom dialog
      _showCustomReviewDialog();
    }
  }

  /// Show custom review dialog with back-to-close functionality
  void _showCustomReviewDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return PopScope(
          canPop: true,
          child: AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.star, color: Colors.amber, size: 28),
                SizedBox(width: 8),
                Text('Rate VPN MASTER'),
              ],
            ),
            content: const Text(
              'Great! You\'re connected to VPN successfully. Would you like to rate our app and share your experience?',
              style: TextStyle(fontSize: 16),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                },
                child: const Text('Maybe Later'),
              ),
              ElevatedButton.icon(
                onPressed: () async {
                  Navigator.of(context).pop();
                  _hasRequestedReview = true;

                  // Store that we've requested review
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setBool('has_requested_review', true);

                  // Try to open store page for rating
                  try {
                    final InAppReview inAppReview = InAppReview.instance;
                    await inAppReview.openStoreListing();
                  } catch (e) {}
                },
                icon: const Icon(Icons.star_rate),
                label: const Text('Rate Now'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _disposeDrawerNativeAd();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final isPremium = ref.watch(premiumStatusProvider);
    final localizations = AppLocalizations.of(context);

    ref.listen<bool>(premiumStatusProvider, (previous, next) {
      if (previous != null && previous != next) {
        if (next) {
          _disposeDrawerNativeAd();
        } else {
          _initializeDrawerNativeAd();
        }
      }
    });

    // Listen to VPN connection state for in-app review.
    // Uses vpnStateProvider (the real, wired-up VPN state) rather than
    // vpn_provider.dart's vpnProvider, whose VpnNotifier.initialize() is
    // never called anywhere in the app — that provider's state never
    // leaves VpnState.disconnected, so listening to it never fires.
    ref.listen<AsyncValue<VpnState>>(vpnStateProvider, (previous, next) {
      next.whenData((state) {
        // Trigger review when VPN connects successfully (not just state change)
        if (previous?.value != VpnState.connected &&
            state == VpnState.connected) {
          // VPN successfully connected, trigger review after delay
          Future.delayed(const Duration(seconds: 3), () {
            if (mounted && !_hasRequestedReview) {
              _triggerInAppReview();
            }
          });
        }
      });
    });

    // Also trigger review based on app usage patterns
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAndTriggerReviewByUsage();
    });

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop) {
          final shouldPop = await _onWillPop();
          if (shouldPop && context.mounted) {
            // Use SystemNavigator.pop() instead of Navigator.pop() to exit app
            SystemNavigator.pop();
          }
        }
      },
      child: Scaffold(
        key: _scaffoldKey,
        body: Stack(
          children: [
            // Background Image

            // Dark overlay
            Positioned.fill(
              child: Container(color: Colors.black.withValues(alpha: 0.2)),
            ),

            // Main Content
            Column(
              children: [
                // Modern AppBar for each screen
                _buildModernAppBar(
                  _currentIndex,
                  isDarkMode,
                  isPremium,
                  localizations,
                ),
                // Screen content
                Expanded(
                  child: SafeArea(
                    top: false, // We handle top padding in AppBar
                    child: PageView(
                      key: const Key('main_page_view'),
                      controller: _pageController,
                      onPageChanged: _onPageChanged,
                      physics: const ClampingScrollPhysics(),
                      children: _screens,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
        bottomNavigationBar: _buildPillBottomNavBar(
          isDarkMode,
          isPremium,
          localizations,
        ),
        drawer: _buildDrawer(context, isDarkMode, isPremium, localizations),
      ),
    );
  }

  Widget _buildModernAppBar(
    int currentIndex,
    bool isDarkMode,
    bool isPremium,
    AppLocalizations localizations,
  ) {
    switch (currentIndex) {
      case 0: // Home screen
        return Container(
          color: isDarkMode ? Colors.black : Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: SafeArea(
            bottom: false,
            child: Row(
              children: [
                // Hamburger menu
                Container(
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.05),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.menu_rounded,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF1E293B),
                      size: 22,
                    ),
                    onPressed: () {
                      _scaffoldKey.currentState?.openDrawer();
                    },
                    tooltip: 'Menu',
                  ),
                ),
                // Center brand pill
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 22,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF7A1A), Color(0xFFFF9F1C)],
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFFFF7A1A,
                            ).withValues(alpha: 0.35),
                            blurRadius: 14,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: const Text(
                        'VPN Master',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                  ),
                ),
                // Premium pill
                GestureDetector(
                  onTap: () => _onTabTapped(2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? Colors.white.withValues(alpha: 0.08)
                          : Colors.black.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.workspace_premium_rounded,
                          color: Color(0xFFFFB020),
                          size: 17,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Premium',
                          style: TextStyle(
                            color: isDarkMode
                                ? Colors.white
                                : const Color(0xFF1E293B),
                            fontWeight: FontWeight.w600,
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
      case 1: // Servers screen
        return ModernAppBar(
          title: 'Select Server',
          showBackButton: false, // No back button for main screens
          actions: [
            IconButton(
              icon: Icon(
                Icons.refresh,
                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                size: 33,
              ),
              onPressed: () {
                // Refresh the servers list.
                try {
                  final _ = ref.refresh(serversProvider);
                } catch (e) {}
              },
              tooltip: 'Refresh Servers',
            ),
          ],
        );
      case 2: // Premium screen
        return ModernAppBar(
          title: 'SUBSCRIPTION',
          showBackButton: true, // No back button for main screens
          actions: [
            if (!isPremium)
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                  size: 27,
                ),
                tooltip: 'Refresh Products',
                onPressed: () {
                  premiumScreenKey.currentState?.refreshProducts();
                },
              ),
          ],
        );
      case 3: // Settings screen
        return ModernAppBar(
          title: 'Settings',
          showBackButton: false, // No back button for main screens
        );
      default:
        return MainAppBar(
          title: 'VPN MASTER',
          showLogo: true,
          actions: [
            IconButton(
              icon: Icon(
                Icons.menu,
                color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                size: 42,
              ),
              onPressed: () {
                _scaffoldKey.currentState?.openDrawer();
              },
              tooltip: 'Menu',
            ),
          ],
        );
    }
  }

  /// Bottom nav bar restyled to match the reference "VPN Master" design —
  /// a black bar with the active tab rendered as a rounded lime pill.
  Widget _buildPillBottomNavBar(
    bool isDarkMode,
    bool isPremium,
    AppLocalizations localizations,
  ) {
    const activeColor = Color(0xFFAEEA1C);
    final items = <_HomeNavItemSpec>[
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
        color: isDarkMode ? Colors.black : Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 10,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 10,
        bottom: 10 + MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: items.map((item) {
          final selected = _currentIndex == item.index;
          return GestureDetector(
            onTap: () => _onTabTapped(item.index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: EdgeInsets.symmetric(
                horizontal: selected ? 18 : 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: selected ? activeColor : Colors.transparent,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Icon(
                        item.icon,
                        size: 22,
                        color: selected
                            ? Colors.black
                            : (isDarkMode
                                  ? Colors.grey[500]
                                  : Colors.grey[500]),
                      ),
                      if (item.badge)
                        Positioned(
                          right: -2,
                          top: -2,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.redAccent,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    Text(
                      item.label,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // BottomNavigationBarItem _buildBottomNavItem({
  //   required IconData icon,
  //   required String label,
  //   required int index,
  //   bool badge = false,
  // }) {
  //   return BottomNavigationBarItem(
  //     icon: Stack(
  //       children: [
  //         FadeInUp(
  //           delay: Duration(milliseconds: index * 100),
  //           child: Icon(icon, size: _currentIndex == index ? 28 : 24),
  //         ),
  //         if (badge)
  //           Positioned(
  //             right: 0,
  //             top: 0,
  //             child: Container(
  //               padding: const EdgeInsets.all(2),
  //               decoration: const BoxDecoration(
  //                 color: Colors.red,
  //                 shape: BoxShape.circle,
  //               ),
  //               constraints: const BoxConstraints(minWidth: 8, minHeight: 8),
  //             ),
  //           ),
  //       ],
  //     ),
  //     label: label,
  //   );
  // }

  Widget _buildDrawer(
    BuildContext context,
    bool isDarkMode,
    bool isPremium,
    AppLocalizations localizations,
  ) {
    final themeColor = ref.watch(themeColorProvider);

    return Drawer(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : Colors.white,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Header with gradient
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          const Color(0xFF1E293B),
                          const Color(0xFF334155),
                          themeColor.withValues(alpha: 0.8),
                        ]
                      : [
                          themeColor,
                          themeColor.withValues(alpha: 0.8),
                          themeColor.withValues(alpha: 0.6),
                        ],
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Logo with glow effect
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          width: 31,
                          height: 31,
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) {
                            // Fallback to icon if image fails to load
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
                    // App name with modern typography
                    const Text(
                      'VPN MASTER',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                    const SizedBox(height: 4),
                    // User status with premium badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isPremium
                                ? const Color(0xFF65645E)
                                : Colors.white.withValues(alpha: 0.2),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            isPremium ? 'PREMIUM' : 'FREE',
                            style: TextStyle(
                              color: isPremium ? Colors.black : Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                        if (isPremium) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.verified,
                            color: Color(0xFF3C3B38),
                            size: 16,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Fast & Secure VPN',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w300,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 10),
                children: [
                  _buildModernDrawerItem(
                    icon: Icons.home_rounded,
                    title: localizations.home,
                    subtitle: 'Connection dashboard',

                    onTap: () => _navigateToTab(0),
                    isDarkMode: isDarkMode,
                  ),

                  if (!isPremium)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isDarkMode
                            ? const Color(0xFF1E293B)
                            : const Color(0xFFF8FAFC),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withValues(alpha: 0.06)
                              : Colors.black.withValues(alpha: 0.04),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: const LevelPlayNativeAdPlacement(height: 80),
                      ),
                    ),
                  _buildModernDrawerItem(
                    icon: Icons.privacy_tip,
                    title: 'Privacy Policy',
                    subtitle: 'Read our privacy policy',
                    onTap: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PrivacyPolicyScreen(),
                        ),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon: Icons.description,
                    title: 'Terms & Conditions',
                    subtitle: 'Read our terms of service',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const TermsOfServiceScreen(),
                        ),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon: Icons.share_rounded,
                    title: localizations.shareApp,
                    subtitle: 'Tell your friends',
                    onTap: () => _shareApp(),
                    isDarkMode: isDarkMode,
                  ),
                  _buildModernDrawerItem(
                    icon: Icons.star_rate_rounded,
                    title: localizations.rateApp,
                    subtitle: ' ⭐⭐⭐⭐⭐',
                    onTap: () {
                      Navigator.pop(context);
                      _triggerInAppReview();
                    },
                    isDarkMode: isDarkMode,
                  ),
                  /* _buildModernDrawerItem(
                    icon: Icons.info_rounded,
                    title: localizations.about,
                    subtitle: 'App information',
                    onTap: () => _showAboutDialog(),
                    isDarkMode: isDarkMode,
                  ),

                  */
                  _buildModernDrawerItem(
                    icon: Icons.headset_mic,
                    title: 'Support',
                    subtitle: 'Get help with the app',
                    onTap: () {
                      Navigator.pop(context);
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const SupportScreen(),
                        ),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),

                  _buildModernDrawerItem(
                    icon: Icons.info_outline,
                    title: 'About',
                    subtitle: 'App information and credits',
                    onTap: () {
                      Navigator.pop(context);

                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const AboutScreen()),
                      );
                    },
                    isDarkMode: isDarkMode,
                  ),
                ],
              ),
            ),

            // Branded Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(
                  top: BorderSide(
                    color: isDarkMode
                        ? const Color(0xFF334155)
                        : const Color(0xFFE5E7EB),
                    width: 0.5,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.asset(
                      'assets/images/app_icon.png',
                      width: 24,
                      height: 24,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) =>
                          Icon(Icons.shield, size: 24, color: themeColor),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'VPN MASTER',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? const Color(0xFF94A3B8)
                          : const Color(0xFF6B7280),
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

  Widget _buildModernDrawerItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isDarkMode,
    bool isSelected = false,
    String? badge,
  }) {
    final themeColor = ref.watch(themeColorProvider);

    return Stack(
      children: [
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: isSelected
                ? themeColor.withValues(alpha: 0.12)
                : Colors.transparent,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Material(
              type: MaterialType.transparency,
              child: ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? themeColor.withValues(alpha: 0.18)
                        : (isDarkMode
                              ? const Color(0xFF1E293B)
                              : const Color(0xFFF3F4F6)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    icon,
                    size: 20,
                    color: isSelected
                        ? themeColor
                        : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
                title: Text(
                  title,
                  style: TextStyle(
                    color: isSelected
                        ? themeColor
                        : (isDarkMode ? Colors.white : const Color(0xFF1F2937)),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                    fontSize: 15,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  subtitle,
                  style: TextStyle(
                    color: isDarkMode
                        ? Colors.grey[450] ?? Colors.grey[400]
                        : Colors.grey[500],
                    fontSize: 11,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: badge != null
                    ? Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          badge,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : null,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 4,
                ),
                onTap: onTap,
              ),
            ),
          ),
        ),
        if (isSelected)
          Positioned(
            left: 12,
            top: 14,
            bottom: 14,
            width: 4,
            child: Container(
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(4),
                ),
              ),
            ),
          ),
      ],
    );
  }

  // Share app functionality
  void _shareApp() async {
    Navigator.pop(context); // Close drawer

    try {
      const String appUrl =
          'https://play.google.com/store/apps/details?id=com.albonik.vpn';
      const String shareText =
          '''
🛡️ VPN MASTER - Secure & Fast VPN

Protect your privacy with VPN MASTER:
✅ Multi grade encryption
✅ 24+ server locations worldwide
✅ No-logs policy
✅ Lightning-fast speeds


Download now and get premium features!
$appUrl

#VPNMASTER #VPN #Privacy #Security
      ''';

      await Share.share(
        shareText,
        subject: 'VPN MASTER - Secure VPN for Everyone',
      );
    } catch (e) {
      // Show fallback
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Share VPN MASTER'),
            content: const Text(
              'Help us grow by sharing VPN MASTER with your friends and family!\n\n'
              'Search for "VPN MASTER" in your app store.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    }
  }

  // About dialog functionality
  void _showAboutDialog() {
    Navigator.pop(context); // Close drawer

    showDialog(
      context: context,
      builder: (context) {
        final isDarkMode = Theme.of(context).brightness == Brightness.dark;
        final themeColor = ref.watch(themeColorProvider);

        return AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shield, color: themeColor, size: 24),
              ),
              const SizedBox(width: 12),
              Text(
                'VPN MASTER',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'VPN MASTER is a Premium VPN service that provides secure, fast, and private internet access. We use military-grade encryption to protect your data and maintain a strict no-logs policy.',
                  style: TextStyle(
                    color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                    fontSize: 14,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildQuickAction(
                      icon: Icons.privacy_tip,
                      label: 'Privacy Policy',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.pushNamed(this.context, '/privacy');
                      },
                      isDarkMode: isDarkMode,
                    ),
                    _buildQuickAction(
                      icon: Icons.gavel,
                      label: 'Terms',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.pushNamed(this.context, '/terms');
                      },
                      isDarkMode: isDarkMode,
                    ),
                    _buildQuickAction(
                      icon: Icons.support,
                      label: 'Support',
                      onTap: () {
                        Navigator.of(context).pop();
                        Navigator.pushNamed(this.context, '/support');
                      },
                      isDarkMode: isDarkMode,
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close', style: TextStyle(color: themeColor)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAboutItem({
    required IconData icon,
    required String title,
    required String value,
    required bool isDarkMode,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              color: isDarkMode ? Colors.white : Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDarkMode,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
        child: Column(
          children: [
            Icon(
              icon,
              size: 20,
              color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                fontSize: 10,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openUrl(String url) async {
    try {
      final Uri uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {}
    } catch (e) {}
  }

  void _navigateToTab(int index) {
    Navigator.pop(context); // Close drawer
    setState(() {
      _currentIndex = index;
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }
}
