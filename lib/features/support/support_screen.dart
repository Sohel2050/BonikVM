import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../shared/providers/theme_provider.dart';
import '../../core/localization/app_localizations.dart';

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
                        tr('sp_center'),
                        style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.green,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        tr('sp_here_247'),
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
                    tr('sp_live_chat'),
                    tr('sp_live_chat_d'),
                    Icons.chat_bubble_outline,
                    const Color(0xFF10B981),
                        () => _launchUrl('https://wa.me/+15059103477'),
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 16),

                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  child: _buildContactOption(
                    tr('sp_email'),
                    tr('sp_email_d'),
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
                    tr('sp_faq_d'),
                    Icons.help_outline,
                    const Color(0xFFF59E0B),
                        () => _showFAQ(context, isDarkMode),
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 16),

                FadeInUp(
                  delay: const Duration(milliseconds: 500),
                  child: _buildContactOption(
                    tr('sp_report_bug'),
                    tr('sp_report_bug_d'),
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
                    tr('sp_feature'),
                    tr('sp_feature_d'),
                    Icons.lightbulb_outline,
                    const Color(0xFF8B5CF6),
                        () => _launchUrl(
                      'mailto:support@albonik.com?subject=Feature Request',
                    ),
                    isDarkMode,
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
                tr('sp_faq_title'),
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
                    tr('sp_q1'),
                    tr('sp_a1'),
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    tr('sp_q2'),
                    tr('sp_a2'),
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    tr('sp_q3'),
                    tr('sp_a3'),
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    tr('sp_q4'),
                    tr('sp_a4'),
                    isDarkMode,
                  ),
                  _buildFAQItem(
                    tr('sp_q5'),
                    tr('sp_a5'),
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
        title: Text(tr('sp_clear_cache')),
        content: Text(
          tr('sp_clear_cache_msg'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              // TODO: Implement cache clearing
            },
            child: Text(tr('clear')),
          ),
        ],
      ),
    );
  }

  void _downloadLogs(BuildContext context) {
    // TODO: Implement log download
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(tr('sp_logs_exported'))),
    );
  }
}

