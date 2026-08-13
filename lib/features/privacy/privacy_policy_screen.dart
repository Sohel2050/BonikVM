import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../shared/providers/theme_provider.dart';

class PrivacyPolicyScreen extends ConsumerWidget {
  const PrivacyPolicyScreen({super.key});

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
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),

                // Header
                FadeInDown(
                  child: Text(
                    'Privacy Policy',
                    style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                ),

                const SizedBox(height: 8),

                FadeInDown(
                  delay: const Duration(milliseconds: 100),
                  child: Text(
                    'Last updated: January 2025',
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode
                          ? const Color(0xFF94A3B8)
                          : Colors.grey[600],
                    ),
                  ),
                ),

                const SizedBox(height: 30),

                // Content
                FadeInUp(
                  delay: const Duration(milliseconds: 200),
                  child: _buildSection(
                    'Information We Collect',
                    '''We collect minimal information necessary to provide our VPN service:

• Account Information: Email address and payment information for subscription management
• Usage Data: Connection logs, bandwidth usage, and session duration for service optimization
• Device Information: Device type, operating system, and app version for compatibility
• Crash Reports: Anonymous error reports to improve app stability

We do NOT collect or log your browsing activity, IP addresses, DNS queries, or any other identifying information while you're connected to our VPN.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  child: _buildSection(
                    'How We Use Your Information',
                    '''Your information is used solely for:

• Providing and maintaining our VPN service
• Processing payments and managing subscriptions
• Improving app performance and fixing bugs
• Sending important service notifications
• Providing customer support

We never sell, rent, or share your personal information with third parties for marketing purposes.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  child: _buildSection(
                    'Data Security',
                    '''We implement industry-standard security measures:

• All data transmission is encrypted using AES-256 bit encryption
• Secure server infrastructure with regular security audits
• Limited access controls for authorized personnel only
• Regular security updates and monitoring
• Secure payment processing through trusted providers

Your security and privacy are our top priorities.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 500),
                  child: _buildSection(
                    'No-Logs Policy',
                    '''VPN MASTER operates under a strict no-logs policy:

• We do NOT log your browsing activity
• We do NOT track websites you visit
• We do NOT monitor your online behavior
• We do NOT store your real IP address
• We do NOT keep connection timestamps

This ensures your online activities remain completely private and anonymous.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 600),
                  child: _buildSection(
                    'Third-Party Services',
                    '''Our app may integrate with third-party services:

• Payment processors for subscription handling
• Analytics services for app performance (anonymized data only)
• Advertising networks (for free tier users, with opt-out options)
• Crash reporting services for bug fixes

All third-party integrations are carefully vetted and comply with our privacy standards.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 700),
                  child: _buildSection('Your Rights', '''You have the right to:

• Access your personal information
• Correct inaccurate data
• Delete your account and data
• Opt-out of marketing communications
• Request data portability
• File complaints with data protection authorities

Contact our support team to exercise any of these rights.''', isDarkMode),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 800),
                  child: _buildSection(
                    'Children\'s Privacy',
                    '''Our service is not intended for users under 13 years of age. We do not knowingly collect personal information from children under 13. If we become aware that a child under 13 has provided us with personal information, we will take steps to delete such information.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 900),
                  child: _buildSection(
                    'Changes to Privacy Policy',
                    '''We may update this Privacy Policy periodically. We will notify you of any material changes by:

• Posting the updated policy in the app
• Sending email notifications to registered users
• Displaying prominent notices during app usage

Continued use of our service after changes constitutes acceptance of the updated policy.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 1000),
                  child: _buildSection(
                    'Contact Us',
                    '''If you have any questions about this Privacy Policy or our data practices, please contact us:

• Email: support@albonik.com
• Support: Through the app's support section
• Website: https://albonik.com

We're committed to addressing your privacy concerns promptly and transparently.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSection(String title, String content, bool isDarkMode) {
    return Container(
      padding: const EdgeInsets.all(20),
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            content,
            style: TextStyle(
              fontSize: 16,
              height: 1.6,
              color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }
}

