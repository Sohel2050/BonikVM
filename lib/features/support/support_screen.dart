import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/providers/theme_provider.dart';

class SupportScreen extends ConsumerWidget {
  const SupportScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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

                // Header
                FadeInDown(
                  child: Column(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: const LinearGradient(
                            colors: [Color(0xFF3B82F6), Color(0xFF1D4ED8)],
                          ),
                        ),
                        child: const Icon(
                          Icons.support_agent,
                          size: 80,
                          color: Colors.yellow,
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'Support Center',
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'We\'re here to help you 24/7',
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

                // Contact Options
                FadeInUp(
                  delay: const Duration(milliseconds: 200),
                  child: _buildContactOption(
                    'Live Chat',
                    'Get instant help from our support team',
                    Icons.chat_bubble_outline,
                    const Color(0xFF10B981),
                        () => _launchUrl('https://wa.me/+15059103477'),
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 16),

                FadeInUp(
                  delay: const Duration(milliseconds: 100),
                  child: _buildContactOption(

                    'Email Support',
                    'Send us an email support@albonik.com',
                    Icons.email_outlined,
                    const Color(0xFF3B82F6),
                        () => _launchUrl('mailto:support@albonik.com'),
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 16),

                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  child: _buildContactOption(
                    'FAQ',
                    'Find answers to frequently asked questions',
                    Icons.help_outline,
                    const Color(0xFFF59E0B),
                        () => _showFAQ(context, isDarkMode),
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 16),

                /*  FadeInUp(
                  delay: const Duration(milliseconds: 500),
                  child: _buildContactOption(
                    'Report Bug',
                    'Help us improve by reporting issues',
                    Icons.bug_report_outlined,
                    const Color(0xFFEF4444),
                    () =>
                        _launchUrl('mailto:support@albonik.com?subject=Bug Report'),
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 16),

                FadeInUp(
                  delay: const Duration(milliseconds: 600),
                  child: _buildContactOption(
                    'Feature Request',
                    'Suggest new features or improvements',
                    Icons.lightbulb_outline,
                    const Color(0xFF8B5CF6),
                    () => _launchUrl(
                      'mailto:info@linkze.me?subject=Feature Request',
                    ),
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 40),

                // Quick Actions
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
                          'Quick Actions',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: isDarkMode ? Colors.white : Colors.black,
                          ),
                        ),
                        const SizedBox(height: 16),
                        _buildQuickAction(
                          'Check Connection Status',
                          'Verify if your VPN is working properly',
                          Icons.network_check,
                          () => _checkConnection(),
                          isDarkMode,
                        ),
                        _buildQuickAction(
                          'Speed Test',
                          'Test your connection speed',
                          Icons.speed,
                          () => _launchUrl('https://speedtest.net'),
                          isDarkMode,
                        ),
                        _buildQuickAction(
                          'Clear App Cache',
                          'Reset app data to fix issues',
                          Icons.clear_all,
                          () => _showClearCacheDialog(context),
                          isDarkMode,
                        ),
                        _buildQuickAction(
                          'Download Logs',
                          'Export diagnostic information',
                          Icons.download,
                          () => _downloadLogs(context),
                          isDarkMode,
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Response Time Info
                FadeInUp(
                  delay: const Duration(milliseconds: 800),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.info_outline,
                          color: const Color(0xFF3B82F6),
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Response Times',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: const Color(0xFF3B82F6),
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Live Chat: Instant • Email: Within 24 hours • Critical Issues: Within 2 hours',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: isDarkMode
                                      ? const Color(0xFF94A3B8)
                                      : Colors.grey[700],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
*/
                const SizedBox(height: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContactOption(
      String title,
      String description,
      IconData icon,
      Color color,
      VoidCallback onTap,
      bool isDarkMode,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 18,
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
                Icon(
                  Icons.arrow_forward_ios,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[400],
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildQuickAction(
      String title,
      String description,
      IconData icon,
      VoidCallback onTap,
      bool isDarkMode,
      ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              Icon(icon, color: const Color(0xFF3B82F6), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isDarkMode ? Colors.white : Colors.black,
                      ),
                    ),
                    Text(
                      description,
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode
                            ? const Color(0xFF94A3B8)
                            : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.arrow_forward_ios,
                color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[400],
                size: 12,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _showFAQ(BuildContext context, bool isDarkMode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[400],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'Frequently Asked Questions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: [
                  _buildFAQItem(
                    'How do I connect to a VPN server?',
                    'Tap the power button on the home screen to connect to the best available server, or go to the Servers tab to choose a specific location.',
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    'Why is my connection slow?',
                    'VPN connections may be slower than direct connections due to encryption. Try connecting to a server closer to your location or contact support.',
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    'Can I use the VPN on multiple devices?',
                    'Premium subscriptions allow multiple device connections. Free accounts are limited to one device at a time.',
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    'How do I cancel my subscription?',
                    'You can cancel through your device\'s app store settings. The subscription will remain active until the end of the current billing period.',
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    'Is my data really private?',
                    'Yes, we operate under a strict no-logs policy and use  encryption to protect your data.',
                    isDarkMode,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFAQItem(String question, String answer, bool isDarkMode) {
    return ExpansionTile(
      title: Text(
        question,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w500,
          color: isDarkMode ? Colors.white : Colors.black,
        ),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            answer,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[700],
            ),
          ),
        ),
      ],
    );
  }

  void _checkConnection() {
    // TODO: Implement connection check
  }

  void _showClearCacheDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear App Cache'),
        content: const Text(
          'This will clear all app data and reset settings to default. Are you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement cache clearing
            },
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  void _downloadLogs(BuildContext context) {
    // TODO: Implement log download
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Diagnostic logs exported successfully')),
    );
  }
}

