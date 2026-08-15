import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:package_info_plus/package_info_plus.dart';
import '../../shared/providers/theme_provider.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  PackageInfo? _packageInfo;

  @override
  void initState() {
    super.initState();
    _loadPackageInfo();
  }

  Future<void> _loadPackageInfo() async {
    final packageInfo = await PackageInfo.fromPlatform();
    if (mounted) {
      setState(() {
        _packageInfo = packageInfo;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: isDarkMode
                ? [const Color(0xFF0F172A), const Color(0xFF1E293B)]
                : [const Color(0xFFF8FAFC), const Color(0xFFE2E8F0)],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 20),

                // App Logo & Name
                Center(
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(34),
                        child: Image.asset(
                          'assets/images/app_icon.png',
                          height: 96,
                          width: 96,
                          errorBuilder: (_, _, _) => Container(
                            height: 96,
                            width: 96,
                            decoration: BoxDecoration(
                              gradient: const LinearGradient(
                                colors: [Color(0xFF00C2FF), Color(0xFF0044BB)],
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                              ),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Icon(
                              Icons.vpn_lock_rounded,
                              size: 48,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'VPN MASTER',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Secure • Fast • Reliable',
                        style: TextStyle(
                          fontSize: 16,
                          color: isDarkMode
                              ? const Color(0xFF94A3B8)
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // App Info
                if (_packageInfo != null) ...[
                  FadeInUp(
                    delay: const Duration(milliseconds: 200),
                    child: _buildInfoCard(
                      'Version',
                      '${_packageInfo!.version} (${_packageInfo!.buildNumber})',
                      Icons.info_outline,
                      isDarkMode,
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  child: _buildInfoCard(
                    'Developer',
                    'ALBONIK LLC',
                    Icons.developer_mode,
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 12),

                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  child: _buildInfoCard(
                    'Release Date',
                    'January 2025',
                    Icons.calendar_today,
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 12),

                FadeInUp(
                  delay: const Duration(milliseconds: 500),
                  child: _buildInfoCard(
                    'Platform',
                    'Android & iOS',
                    Icons.smartphone,
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 30),

                // Description
                FadeInUp(
                  delay: const Duration(milliseconds: 600),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'About VPN MASTER',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'VPN MASTER is a premium VPN service that provides secure, fast, and reliable internet access. Our app uses military-grade encryption to protect your online privacy and allows you to access content from around the world.',
                          style: TextStyle(
                            fontSize: 16,
                            height: 1.5,
                            color: isDarkMode
                                ? const Color(0xFF94A3B8)
                                : Colors.grey[700],
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            Icon(
                              Icons.shield_outlined,
                              color: const Color(0xFF3B82F6),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Your privacy is our priority',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF3B82F6),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Features
                FadeInUp(
                  delay: const Duration(milliseconds: 700),
                  child: Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF1E293B)
                          : Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Key Features',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildFeatureItem(
                          '🔒',
                          'Multi grade encryption',
                          'AES-256 bit encryption for maximum security',
                          isDarkMode,
                        ),
                        _buildFeatureItem(
                          '🚀',
                          'High-speed servers',
                          'Optimized servers for fastest connection',
                          isDarkMode,
                        ),
                        _buildFeatureItem(
                          '🌍',
                          'Global network',
                          'Servers in multiple countries worldwide',
                          isDarkMode,
                        ),
                        _buildFeatureItem(
                          '📱',
                          'Multi-platform',
                          'Available on Android and iOS devices',
                          isDarkMode,
                        ),
                        _buildFeatureItem(
                          '🔄',
                          'Auto-connect',
                          'Automatic connection to best available server',
                          isDarkMode,
                        ),
                        _buildFeatureItem(
                          '🛡️',
                          'Kill switch',
                          'Protect your data if VPN connection drops',
                          isDarkMode,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    String title,
    String value,
    IconData icon,
    bool isDarkMode,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: const Color(0xFF3B82F6), size: 20),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode
                        ? const Color(0xFF94A3B8)
                        : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeatureItem(
    String emoji,
    String title,
    String description,
    bool isDarkMode,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 24)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDarkMode
                        ? const Color(0xFF94A3B8)
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

