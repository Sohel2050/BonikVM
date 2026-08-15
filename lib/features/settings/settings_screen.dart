import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/admob_service.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/widgets/language_selector.dart';
import '../../providers/auth_providers.dart';
import '../../core/api/api_service.dart';
import '../../core/services/purchase_service.dart';
import '../about/about_screen.dart';
import '../support/support_screen.dart';
import 'admin_notifications_screen.dart';
import '../../screens/profile/purchase_history_screen.dart';
import '../../screens/auth/sign_in_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  @override
  void initState() {
    super.initState();
    _initializeBannerAd();
  }

  void _initializeBannerAd() {
    if (ref.read(premiumStatusProvider) || _bannerAd != null) {
      return;
    }

    _bannerAd = AdMobService.instance.createBannerAd(
      onAdLoaded: (ad) {
        if (mounted) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        }
      },
      onAdFailedToLoad: (ad, error) {
        ad.dispose();
        _bannerAd = null;
        _isBannerAdLoaded = false;
      },
    );

    _bannerAd?.load();
  }

  void _disposeBannerAd() {
    _bannerAd?.dispose();
    _bannerAd = null;
    _isBannerAdLoaded = false;
  }

  @override
  void dispose() {
    _disposeBannerAd();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = ref.watch(themeModeProvider) == ThemeMode.dark;
    final authState = ref.watch(authStateProvider);
    final isPremium = ref.watch(premiumStatusProvider);
    final localizations = AppLocalizations.of(context);

    ref.listen<bool>(premiumStatusProvider, (previous, next) {
      if (previous != null && previous != next) {
        if (next) {
          _disposeBannerAd();
        } else {
          _initializeBannerAd();
        }
      }
    });

    return Container(
      color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Connection Settings
            _buildSectionTitle(localizations.connection, isDarkMode),
            const SizedBox(height: 8),
            _buildSettingCard(
              isDarkMode: isDarkMode,
              children: [
                _buildSettingTile(
                  title: localizations.protocol,
                  subtitle: ref.watch(protocolProvider)
                      ? localizations.udpRecommended
                      : localizations.tcpReliable,
                  icon: Icons.settings_ethernet,
                  isDarkMode: isDarkMode,
                  onTap: () => _showProtocolDialog(context, isDarkMode),
                  trailingText: ref.watch(protocolProvider) ? 'UDP' : 'TCP',
                ),
                _buildDivider(isDarkMode),
                _buildSettingTile(
                  title: localizations.killSwitch,
                  subtitle: 'Block traffic when VPN disconnects',
                  icon: Icons.security,
                  isDarkMode: isDarkMode,
                  trailing: Switch(
                    value: ref.watch(killSwitchProvider),
                    onChanged: (value) {
                      ref.read(killSwitchProvider.notifier).toggle();
                    },
                  ),
                ),
                _buildDivider(isDarkMode),
                _buildSettingTile(
                  title: localizations.autoConnect,
                  subtitle: 'Connect automatically on app start',
                  icon: Icons.power_settings_new,
                  isDarkMode: isDarkMode,
                  trailing: Switch(
                    value: ref.watch(autoConnectProvider),
                    onChanged: (value) {
                      ref.read(autoConnectProvider.notifier).toggle();
                    },
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Appearance Settings
            _buildSectionTitle(localizations.appearance, isDarkMode),
            const SizedBox(height: 8),
            _buildSettingCard(
              isDarkMode: isDarkMode,
              children: [
                _buildSettingTile(
                  title: localizations.theme,
                  subtitle: _getThemeModeText(ref.watch(themeModeProvider)),
                  icon: isDarkMode ? Icons.dark_mode : Icons.light_mode,
                  isDarkMode: isDarkMode,
                  onTap: () => _showThemeDialog(context, isDarkMode),
                ),
                _buildDivider(isDarkMode),
                _buildSettingTile(
                  title: localizations.accentColor,
                  subtitle: 'Customize app appearance',
                  icon: Icons.color_lens,
                  isDarkMode: isDarkMode,
                  onTap: () => _showColorDialog(context, isDarkMode),
                  trailing: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: ref.watch(themeColorProvider),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                _buildDivider(isDarkMode),
                const LanguageSelector(showInDrawer: false),
              ],
            ),

            const SizedBox(height: 24),

            // Account Settings
            _buildSectionTitle(localizations.account, isDarkMode),
            const SizedBox(height: 8),
            _buildSettingCard(
              isDarkMode: isDarkMode,
              children: [
                _buildSettingTile(
                  title: localizations.premiumStatus,
                  subtitle: isPremium ? 'Active' : 'Free Plan',
                  icon: Icons.star,
                  isDarkMode: isDarkMode,
                  onTap: isPremium
                      ? null
                      : () => Navigator.pushNamed(context, '/premium'),
                  trailing: isPremium
                      ? Icon(
                          Icons.check_circle,
                          color: ref.watch(themeColorProvider),
                        )
                      : ElevatedButton.icon(
                          icon: const Icon(Icons.workspace_premium, size: 14),
                          label: const Text(
                            'UPGRADE',
                            style: TextStyle(fontSize: 12),
                          ),
                          onPressed: () =>
                              Navigator.pushNamed(context, '/premium'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: ref.watch(themeColorProvider),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                ),
                _buildDivider(isDarkMode),
                _buildSettingTile(
                  title: localizations.accountManagement,
                  subtitle: authState.firebaseUser != null
                      ? 'Signed in as ${authState.firebaseUser?.email ?? "User"}'
                      : 'Sign in with Google account',
                  icon: authState.firebaseUser != null
                      ? Icons.person
                      : Icons.login,
                  isDarkMode: isDarkMode,
                  trailing: authState.firebaseUser != null
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (authState.firebaseUser?.emailVerified == true)
                              Icon(
                                Icons.verified,
                                color: Colors.green,
                                size: 16,
                              ),
                            const SizedBox(width: 4),
                            Icon(Icons.check_circle, color: Colors.green),
                          ],
                        )
                      : Icon(Icons.login, color: Colors.blue),
                  onTap: () => _handleAccountManagement(),
                ),
                if (authState.firebaseUser != null) ...[
                  _buildDivider(isDarkMode),
                  _buildSettingTile(
                    title: localizations.purchaseHistory,
                    subtitle: 'View your subscription history',
                    icon: Icons.history,
                    isDarkMode: isDarkMode,
                    onTap: () => _navigateToPurchaseHistory(),
                  ),
                  _buildDivider(isDarkMode),
                  _buildSettingTile(
                    title: localizations.restorePurchases,
                    subtitle:
                        'Restore previous purchases from Play Store or App Store',
                    icon: Icons.restore,
                    isDarkMode: isDarkMode,
                    onTap: () => _handleRestorePurchases(),
                  ),
                ],
              ],
            ),

            const SizedBox(height: 24),

            // Miscellaneous Settings
            _buildSectionTitle(localizations.miscellaneous, isDarkMode),
            const SizedBox(height: 8),
            _buildSettingCard(
              isDarkMode: isDarkMode,
              children: [
                _buildSettingTile(
                  title: localizations.notifications,
                  subtitle: 'Manage push notifications',
                  icon: Icons.notifications,
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AdminNotificationsScreen(),
                      ),
                    );
                  },
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Other Settings
            _buildSectionTitle('Other', isDarkMode),
            const SizedBox(height: 8),
            _buildSettingCard(
              isDarkMode: isDarkMode,
              children: [
                _buildSettingTile(
                  title: localizations.privacyPolicy,
                  subtitle: 'Read our privacy policy',
                  icon: Icons.privacy_tip,
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.pushNamed(context, '/privacy');
                  },
                ),
                _buildDivider(isDarkMode),
                _buildSettingTile(
                  title: localizations.termsOfService,
                  subtitle: 'Read our terms',
                  icon: Icons.description,
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.pushNamed(context, '/terms');
                  },
                ),
                _buildDivider(isDarkMode),
                _buildSettingTile(
                  title: localizations.support,
                  subtitle: 'Get help with the app',
                  icon: Icons.support_agent,
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const SupportScreen(),
                      ),
                    );
                  },
                ),
                _buildDivider(isDarkMode),
                _buildSettingTile(
                  title: localizations.about,
                  subtitle: 'App information and credits',
                  icon: Icons.info,
                  isDarkMode: isDarkMode,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const AboutScreen(),
                      ),
                    );
                  },
                ),
                // Add debug option (always available for Play Store testing)
                // _buildDivider(isDarkMode),
                // _buildSettingTile(
                //   title: 'VPN Debug & Testing',
                //   subtitle: 'Test VPN configuration and Play Store readiness',
                //   icon: Icons.bug_report,
                //   isDarkMode: isDarkMode,
                //   onTap: () {
                //     Navigator.pushNamed(context, '/debug');
                //   },
                // ),
              ],
            ),

            // Bottom banner ad
            if (!isPremium && _isBannerAdLoaded && _bannerAd != null) ...[
              const SizedBox(height: 24),
              Container(
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AdWidget(ad: _bannerAd!),
                ),
              ),
            ],

            const SizedBox(height: 100), // Bottom padding
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title, bool isDarkMode) {
    final themeColor = ref.watch(themeColorProvider);
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.8,
          color: themeColor,
        ),
      ),
    );
  }

  Widget _buildSettingCard({
    required bool isDarkMode,
    required List<Widget> children,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Material(
          type: MaterialType.transparency,
          child: Column(children: children),
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required bool isDarkMode,
    VoidCallback? onTap,
    Widget? trailing,
    String? trailingText,
  }) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: ref.watch(themeColorProvider).withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: ref.watch(themeColorProvider), size: 20),
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[600],
          fontSize: 12,
        ),
      ),
      trailing:
          trailing ??
          (trailingText != null
              ? Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: ref.watch(themeColorProvider).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    trailingText,
                    style: TextStyle(
                      color: ref.watch(themeColorProvider),
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : const Icon(Icons.chevron_right)),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildDivider(bool isDarkMode) {
    return Divider(
      height: 1,
      color: isDarkMode ? const Color(0xFF334155) : Colors.grey[200],
      indent: 60,
      endIndent: 16,
    );
  }

  String _getThemeModeText(ThemeMode mode) {
    final localizations = AppLocalizations.of(context);
    switch (mode) {
      case ThemeMode.light:
        return localizations.lightMode;
      case ThemeMode.dark:
        return localizations.darkMode;
      case ThemeMode.system:
        return localizations.systemDefault;
    }
  }

  void _showThemeDialog(BuildContext context, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        title: Text(
          'Choose Theme',
          style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.light_mode),
              title: const Text('Light'),
              onTap: () {
                ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.light);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.dark_mode),
              title: const Text('Dark'),
              onTap: () {
                ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.dark);
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.brightness_auto),
              title: const Text('System Default'),
              onTap: () {
                ref
                    .read(themeModeProvider.notifier)
                    .setThemeMode(ThemeMode.system);
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _showProtocolDialog(BuildContext context, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Select Protocol',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Choose the connection protocol for optimal performance',
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),

              // UDP Option
              _buildProtocolOption(
                context: context,
                title: 'UDP',
                subtitle: 'Faster, recommended for streaming',
                description:
                    'Best for most use cases. Faster connection with lower latency.',
                isSelected: ref.watch(protocolProvider),
                onTap: () {
                  if (!ref.read(protocolProvider)) {
                    ref.read(protocolProvider.notifier).toggle();
                  }
                  Navigator.pop(context);
                },
                isDarkMode: isDarkMode,
                isRecommended: true,
              ),

              const SizedBox(height: 12),

              // TCP Option
              _buildProtocolOption(
                context: context,
                title: 'TCP',
                subtitle: 'More reliable, better for restricted networks',
                description:
                    'More stable on unstable networks but slightly slower.',
                isSelected: !ref.watch(protocolProvider),
                onTap: () {
                  if (ref.read(protocolProvider)) {
                    ref.read(protocolProvider.notifier).toggle();
                  }
                  Navigator.pop(context);
                },
                isDarkMode: isDarkMode,
                isRecommended: false,
              ),

              const SizedBox(height: 20),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDarkMode
                            ? const Color(0xFF94A3B8)
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProtocolOption({
    required BuildContext context,
    required String title,
    required String subtitle,
    required String description,
    required bool isSelected,
    required VoidCallback onTap,
    required bool isDarkMode,
    required bool isRecommended,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? ref.watch(themeColorProvider).withValues(alpha: 0.1)
              : (isDarkMode
                    ? const Color(0xFF334155)
                    : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? ref.watch(themeColorProvider)
                : (isDarkMode
                      ? const Color(0xFF475569)
                      : const Color(0xFFE2E8F0)),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? ref.watch(themeColorProvider)
                        : (isDarkMode ? Colors.white : Colors.black),
                  ),
                ),
                if (isRecommended) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'RECOMMENDED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (isSelected)
                  Icon(
                    Icons.check_circle,
                    color: ref.watch(themeColorProvider),
                    size: 20,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 4),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? const Color(0xFF64748B) : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showColorDialog(BuildContext context, bool isDarkMode) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Choose Accent Color',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Select a color theme that suits your style',
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[600],
                ),
              ),
              const SizedBox(height: 20),

              // Preview section
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: ref.watch(themeColorProvider).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: ref.watch(themeColorProvider).withValues(alpha: 0.3),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: ref.watch(themeColorProvider),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.color_lens,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Preview',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: ref.watch(themeColorProvider),
                          ),
                        ),
                        Text(
                          'This is how it will look',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDarkMode
                                ? const Color(0xFF94A3B8)
                                : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Color selection grid
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 4,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                ),
                itemCount: AppThemeColors.colors.length,
                itemBuilder: (context, index) {
                  final entry = AppThemeColors.colors.entries.elementAt(index);
                  final colorKey = entry.key;
                  final color = entry.value;
                  final isSelected = ref.watch(themeColorProvider) == color;

                  return GestureDetector(
                    onTap: () async {
                      await ref
                          .read(themeColorProvider.notifier)
                          .setThemeColorByKey(colorKey);
                      await ref
                          .read(themeColorKeyProvider.notifier)
                          .setThemeColorKey(colorKey);
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.white : Colors.transparent,
                          width: 3,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: color.withValues(alpha: 0.3),
                            blurRadius: 8,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: isSelected
                          ? const Icon(
                              Icons.check,
                              color: Colors.white,
                              size: 24,
                            )
                          : null,
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDarkMode
                            ? const Color(0xFF94A3B8)
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: ref.watch(themeColorProvider),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Done'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Handle Account Management - either sign in or show account options
  Future<void> _handleAccountManagement() async {
    final authState = ref.read(authStateProvider);

    if (authState.firebaseUser == null) {
      // User not signed in, navigate to login screen
      if (mounted && context.mounted) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => const SignInScreen()),
        );
      }
    } else {
      // User signed in, show account options as modern bottom sheet
      final themeColor = ref.read(themeColorProvider);
      final isDarkMode = Theme.of(context).brightness == Brightness.dark;
      final firebaseUser = authState.firebaseUser!;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _AccountManagementSheet(
          email: firebaseUser.email ?? 'Unknown',
          memberSince:
              firebaseUser.metadata.creationTime?.toString().split(' ')[0] ??
              'Unknown',
          emailVerified: firebaseUser.emailVerified,
          themeColor: themeColor,
          isDark: isDarkMode,
          onDelete: () {
            Navigator.pop(ctx);
            _showDeleteAccountDialog();
          },
          onSignOut: () {
            Navigator.pop(ctx);
            _signOut();
          },
        ),
      );
    }
  }

  /// Navigate to Purchase History screen
  void _navigateToPurchaseHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const PurchaseHistoryScreen()),
    );
  }

  /// Handle Restore Purchases
  Future<void> _handleRestorePurchases() async {
    final isDarkMode = ref.read(themeModeProvider) == ThemeMode.dark;
    final themeColor = ref.read(themeColorProvider);
    final currentUser = ref.read(currentUserProvider); // Firebase User

    if (currentUser == null) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'Sign In Required',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          content: Text(
            'Please sign in with the account you used for the original purchase.',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'OK',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(
                'Restoring purchases...',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final apiService = ApiService();
    final purchaseService = PurchaseService();
    bool foundActive = false;
    StreamSubscription<PurchaseResult>? subscription;
    final completer = Completer<void>();

    // Auto-complete after 15 seconds (store may not return events if no purchases)
    final timer = Timer(const Duration(seconds: 15), () {
      if (!completer.isCompleted) completer.complete();
    });

    subscription = purchaseService.purchaseResultStream.listen((result) async {
      if (result.isRestored && !completer.isCompleted) {
        // Verify each restored purchase with our backend — only active
        // subscriptions (not cancelled/expired) will pass verification.
        try {
          final verified = await apiService.verifyPurchase(
            userId: currentUser.uid,
            receiptData: result.receiptData ?? '',
            productId: result.productId ?? '',
            platform: Platform.isAndroid ? 'android' : 'ios',
            transactionId: result.transactionId,
            firebaseUid: currentUser.uid,
            userEmail: currentUser.email,
          );
          if (verified != null && verified['success'] == true) {
            foundActive = true;
            await purchaseService.setPremiumStatus(true);
            await purchaseService.activateSubscriptionBenefits();
            if (!completer.isCompleted) completer.complete();
          }
        } catch (_) {}
      } else if (result.isError && !completer.isCompleted) {
        completer.complete();
      }
    });

    try {
      purchaseService.restorePurchases();
      await completer.future;
    } finally {
      timer.cancel();
      await subscription.cancel();
    }

    if (!mounted) return;
    Navigator.pop(context); // Close loading dialog

    if (foundActive) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.green),
              const SizedBox(width: 8),
              Text(
                'Subscription Restored',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          content: Text(
            'Your active subscription has been restored successfully. Premium features are now available.',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: themeColor,
                foregroundColor: Colors.white,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          title: Row(
            children: [
              const Icon(Icons.info_outline, color: Colors.orange),
              const SizedBox(width: 8),
              Text(
                'No Active Subscriptions',
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
          content: Text(
            'No active subscriptions were found for this account. If you believe this is a mistake, make sure you\'re signed in with the same account used for the original purchase.',
            style: TextStyle(
              color: isDarkMode ? Colors.white70 : Colors.black54,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'OK',
                style: TextStyle(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
          ],
        ),
      );
    }
  }

  /// Show delete account confirmation dialog
  void _showDeleteAccountDialog() {
    final isDarkMode = ref.read(themeModeProvider) == ThemeMode.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF111827) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.grey[700] : Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: const Color(0xFFEF4444).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.delete_forever_rounded,
                    color: Color(0xFFEF4444),
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  'Delete Account',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'This action is permanent and cannot be undone.',
              style: TextStyle(
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            _buildDeleteItem('• Account information'),
            _buildDeleteItem('• Subscription history'),
            _buildDeleteItem('• Payment records'),
            _buildDeleteItem('• Settings and preferences'),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _deleteAccount();
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFEF4444),
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Delete Forever'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDeleteItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 4),
      child: Text(
        text,
        style: TextStyle(fontSize: 13, color: Colors.grey[600]),
      ),
    );
  }

  /// Delete account functionality
  void _deleteAccount() async {
    final authState = ref.read(authStateProvider);
    final userId = authState.firebaseUser?.uid;

    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Error: User not found'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Show loading dialog
    if (mounted) {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );
    }

    try {
      // Call API to delete account
      final apiService = ApiService.instance;
      final result = await apiService.deleteAccount(userId: userId);

      if (mounted) {
        Navigator.pop(context); // Close loading dialog
      }

      if (result['success'] == true || result['message'] == 'User not found') {
        // Delete Firebase account (also handles backend cleanup internally)
        await ref.read(authStateProvider.notifier).deleteAccount();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Account deleted successfully'),
              backgroundColor: Colors.green,
            ),
          );

          // Hard reset to splash to rebuild shell/auth flow cleanly.
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/splash', (route) => false);
        }
      } else {
        // Backend error other than "user not found" — still attempt Firebase deletion
        await ref.read(authStateProvider.notifier).deleteAccount();
        if (mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/splash', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Sign out functionality
  Future<void> _signOut() async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    try {
      await ref.read(authStateProvider.notifier).signOut();

      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('✅ Successfully signed out!'),
            backgroundColor: Colors.green,
          ),
        );

        // Force full route reset to prevent stale shell causing black screens.
        await Future.delayed(const Duration(milliseconds: 100));
        if (mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/splash', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // Close loading dialog

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to sign out: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }
}

/// Modern bottom sheet for Account Management
class _AccountManagementSheet extends StatelessWidget {
  final String email;
  final String memberSince;
  final bool emailVerified;
  final Color themeColor;
  final bool isDark;
  final VoidCallback onDelete;
  final VoidCallback onSignOut;

  const _AccountManagementSheet({
    required this.email,
    required this.memberSince,
    required this.emailVerified,
    required this.themeColor,
    required this.isDark,
    required this.onDelete,
    required this.onSignOut,
  });

  @override
  Widget build(BuildContext context) {
    final bgColor = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark
        ? const Color(0xFF94A3B8)
        : Colors.grey.shade600;
    final dividerColor = isDark
        ? const Color(0xFF334155)
        : Colors.grey.shade200;

    // Build avatar initials from email
    final initial = email.isNotEmpty ? email[0].toUpperCase() : 'U';

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF475569) : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Avatar + name
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: themeColor,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                initial,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Text(
                email,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  emailVerified ? Icons.verified : Icons.warning_amber_rounded,
                  size: 14,
                  color: emailVerified ? Colors.green : Colors.orange,
                ),
                const SizedBox(width: 4),
                Text(
                  emailVerified ? 'Email verified' : 'Email not verified',
                  style: TextStyle(
                    fontSize: 12,
                    color: emailVerified ? Colors.green : Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Info rows
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dividerColor),
              ),
              child: Column(
                children: [
                  _InfoRow(
                    icon: Icons.calendar_today_outlined,
                    label: 'Member since',
                    value: memberSince,
                    themeColor: themeColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                  Divider(
                    height: 1,
                    color: dividerColor,
                    indent: 48,
                    endIndent: 16,
                  ),
                  _InfoRow(
                    icon: Icons.email_outlined,
                    label: 'Account',
                    value: email,
                    themeColor: themeColor,
                    textPrimary: textPrimary,
                    textSecondary: textSecondary,
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // Danger zone
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF0F172A)
                    : const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: dividerColor),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(
                          Icons.delete_forever,
                          color: Colors.red,
                        ),
                        title: const Text(
                          'Delete Account',
                          style: TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        subtitle: Text(
                          'Permanently remove your account',
                          style: TextStyle(color: textSecondary, fontSize: 12),
                        ),
                        trailing: const Icon(
                          Icons.chevron_right,
                          color: Colors.red,
                        ),
                        onTap: onDelete,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Sign Out button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: onSignOut,
                  icon: const Icon(Icons.logout),
                  label: const Text(
                    'Sign Out',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color themeColor;
  final Color textPrimary;
  final Color textSecondary;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.themeColor,
    required this.textPrimary,
    required this.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          Icon(icon, color: themeColor, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: textSecondary)),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: textPrimary,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
