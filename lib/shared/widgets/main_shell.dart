import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../features/home/home_screen.dart';
import '../../features/servers/servers_screen.dart';
import '../../features/settings/settings_screen.dart';
import '../../features/premium/premium_screen.dart';
import '../../core/services/admob_service.dart';
import '../../core/services/update_service.dart';
import '../../core/services/vpn_state.dart';
import '../../core/localization/app_localizations.dart';
import '../providers/app_providers.dart';
import '../providers/theme_provider.dart';
import 'modern_app_bar.dart';
import 'language_selector.dart';

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
    if (ref.read(premiumStatusProvider) || _drawerNativeAd != null) {
      return;
    }

    _drawerNativeAd = AdMobService.instance.createNativeAd(
      onAdLoaded: (ad) {
        if (mounted) {
          setState(() {
            _isDrawerNativeAdLoaded = true;
          });
        }
      },
      onAdFailedToLoad: (ad, error) {
        ad.dispose();
        _drawerNativeAd = null;
        _isDrawerNativeAdLoaded = false;
      },
    );

    _drawerNativeAd?.load();
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
              Icon(Icons.exit_to_app, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Press back again to exit VPN MASTER',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
          backgroundColor: Colors.black87,
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
        body: Column(
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
        bottomNavigationBar: SafeArea(
          bottom: true,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            height: 68,
            decoration: BoxDecoration(
              color: isDarkMode
                  ? const Color(0xFF1E293B).withOpacity(0.85)
                  : Colors.white.withOpacity(0.85),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: isDarkMode
                    ? Colors.white.withOpacity(0.08)
                    : Colors.black.withOpacity(0.05),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(isDarkMode ? 0.25 : 0.06),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(24),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 10.0, sigmaY: 10.0),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: [
                      _buildFloatingNavItem(
                        icon: Icons.home_rounded,
                        label: localizations.home,
                        index: 0,
                        isDarkMode: isDarkMode,
                      ),
                      _buildFloatingNavItem(
                        icon: Icons.dns_rounded,
                        label: localizations.servers,
                        index: 1,
                        isDarkMode: isDarkMode,
                      ),
                      _buildFloatingNavItem(
                        icon: Icons.star_rounded,
                        label: isPremium ? localizations.premium : 'Premium',
                        index: 2,
                        isDarkMode: isDarkMode,
                      ),
                      _buildFloatingNavItem(
                        icon: Icons.settings_rounded,
                        label: localizations.settings,
                        index: 3,
                        isDarkMode: isDarkMode,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
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
        return MainAppBar(
          title: 'VPN MASTER',
          showLogo: true,
          leading: IconButton(
            icon: Icon(
              Icons.menu,
              color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
              size: 24,
            ),
            onPressed: () {
              _scaffoldKey.currentState?.openDrawer();
            },
            tooltip: 'Menu',
          ),
          actions: [
            // Theme toggle button
            IconButton(
              onPressed: () {
                final currentMode = ref.read(themeModeProvider);
                final newMode = currentMode == ThemeMode.dark
                    ? ThemeMode.light
                    : ThemeMode.dark;
                ref.read(themeModeProvider.notifier).setThemeMode(newMode);
              },
              icon: Icon(
                isDarkMode ? Icons.light_mode : Icons.dark_mode,
                color: isDarkMode ? Colors.amber : const Color(0xFF1E293B),
                size: 24,
              ),
              tooltip: isDarkMode
                  ? 'Switch to Light Mode'
                  : 'Switch to Dark Mode',
            ),
          ],
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
                size: 24,
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
          title: 'Premium',
          showBackButton: false, // No back button for main screens
          actions: [
            if (!isPremium)
              IconButton(
                icon: Icon(
                  Icons.refresh,
                  color: isDarkMode ? Colors.white : const Color(0xFF1E293B),
                  size: 24,
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
                size: 24,
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

  Widget _buildFloatingNavItem({
    required IconData icon,
    required String label,
    required int index,
    required bool isDarkMode,
  }) {
    final themeColor = ref.watch(themeColorProvider);
    final isSelected = _currentIndex == index;
    final activeColor = themeColor;
    
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _onTabTapped(index),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              decoration: BoxDecoration(
                color: isSelected
                    ? activeColor.withOpacity(0.12)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                icon,
                size: 24,
                color: isSelected
                    ? activeColor
                    : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                color: isSelected
                    ? activeColor
                    : (isDarkMode ? Colors.grey[400] : Colors.grey[600]),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

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
            // Modernized Profile Header with Gradient Background
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: isDarkMode
                      ? [
                          themeColor.withOpacity(0.15),
                          const Color(0xFF1E293B),
                        ]
                      : [
                          themeColor.withOpacity(0.08),
                          const Color(0xFFF3F4F6),
                        ],
                ),
                border: Border(
                  bottom: BorderSide(
                    color: isDarkMode
                        ? const Color(0xFF334155)
                        : const Color(0xFFE5E7EB),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Avatar with glowing gradient border
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: [themeColor, themeColor.withOpacity(0.6)],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: themeColor.withOpacity(0.3),
                          blurRadius: 12,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          'A',
                          style: TextStyle(
                            color: themeColor,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'VPN MASTER User',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isPremium
                                ? const Color(0xFFFFD700).withOpacity(0.15)
                                : themeColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: isPremium
                                  ? const Color(0xFFFFD700).withOpacity(0.6)
                                  : themeColor.withOpacity(0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                isPremium ? Icons.star_rounded : Icons.person_outline,
                                size: 12,
                                color: isPremium ? const Color(0xFFD97706) : themeColor,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                isPremium ? 'Premium User' : 'Free User',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: isPremium ? const Color(0xFFD97706) : themeColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),

            // Navigation Items
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 12),
                children: [
                  const SizedBox(height: 12),

                  // Language Selector in drawer
                  const LanguageSelector(showInDrawer: true),

                  const SizedBox(height: 6),

                  _buildModernDrawerItem(
                    icon: Icons.home_rounded,
                    title: localizations.home,
                    subtitle: 'Connection dashboard',
                    isSelected: _currentIndex == 0,
                    onTap: () => _navigateToTab(0),
                    isDarkMode: isDarkMode,
                  ),
                  _buildModernDrawerItem(
                    icon: Icons.dns_rounded,
                    title: localizations.servers,
                    subtitle: 'Global locations',
                    isSelected: _currentIndex == 1,
                    onTap: () => _navigateToTab(1),
                    isDarkMode: isDarkMode,
                  ),
                  _buildModernDrawerItem(
                    icon: Icons.workspace_premium_rounded,
                    title: localizations.premium,
                    subtitle: 'Unlock VIP nodes',
                    isSelected: _currentIndex == 2,
                    onTap: () => _navigateToTab(2),
                    isDarkMode: isDarkMode,
                    badge: !isPremium ? 'HOT' : null,
                  ),
                  _buildModernDrawerItem(
                    icon: Icons.settings_rounded,
                    title: localizations.settings,
                    subtitle: 'App preferences',
                    isSelected: _currentIndex == 3,
                    onTap: () => _navigateToTab(3),
                    isDarkMode: isDarkMode,
                  ),

                  if (!isPremium && _isDrawerNativeAdLoaded && _drawerNativeAd != null)
                    Container(
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
                        border: Border.all(
                          color: isDarkMode
                              ? Colors.white.withOpacity(0.06)
                              : Colors.black.withOpacity(0.04),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: AdWidget(ad: _drawerNativeAd!),
                      ),
                    ),

                  // Divider
                  Container(
                    margin: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(
                      color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
                      thickness: 1.0,
                      indent: 20,
                      endIndent: 20,
                    ),
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
                    subtitle: 'Leave a review',
                    onTap: () {
                      Navigator.pop(context);
                      _triggerInAppReview();
                    },
                    isDarkMode: isDarkMode,
                  ),
                  _buildModernDrawerItem(
                    icon: Icons.info_rounded,
                    title: localizations.about,
                    subtitle: 'App information',
                    onTap: () => _showAboutDialog(),
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
                      errorBuilder: (_, __, ___) => Icon(
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
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
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
                ? themeColor.withOpacity(0.12)
                : Colors.transparent,
          ),
          child: ListTile(
            leading: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isSelected
                    ? themeColor.withOpacity(0.18)
                    : (isDarkMode ? const Color(0xFF1E293B) : const Color(0xFFF3F4F6)),
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
                color: isDarkMode ? Colors.grey[450] ?? Colors.grey[400] : Colors.grey[500],
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: badge != null
                ? Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            onTap: onTap,
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
                borderRadius: const BorderRadius.horizontal(right: Radius.circular(4)),
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
✅ 50+ server locations worldwide
✅ No-logs policy
✅ Lightning-fast speeds
✅ 24/7 customer support

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
                'About VPN MASTER',
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
                _buildAboutItem(
                  icon: Icons.info_outline,
                  title: 'Version',
                  value: '46.0.0',
                  isDarkMode: isDarkMode,
                ),
                _buildAboutItem(
                  icon: Icons.code,
                  title: 'Build',
                  value: 'Flutter 3.10+',
                  isDarkMode: isDarkMode,
                ),
                _buildAboutItem(
                  icon: Icons.security,
                  title: 'Encryption',
                  value: 'AES-256',
                  isDarkMode: isDarkMode,
                ),
                _buildAboutItem(
                  icon: Icons.language,
                  title: 'Servers',
                  value: '50+ Countries',
                  isDarkMode: isDarkMode,
                ),
                const SizedBox(height: 16),
                Text(
                  'VPN MASTER is a premium VPN service that provides secure, fast, and private internet access. We use military-grade encryption to protect your data and maintain a strict no-logs policy.',
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
