import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../shared/providers/theme_provider.dart';

class TermsOfServiceScreen extends ConsumerWidget {
  const TermsOfServiceScreen({super.key});

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
                    'Terms of Service',
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
                    'Acceptance of Terms',
                    '''By downloading, installing, or using VPN MASTER ("the Service"), you agree to be bound by these Terms of Service ("Terms"). If you do not agree to these Terms, please do not use our Service.

These Terms constitute a legal agreement between you and Albonik.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  child: _buildSection(
                    'Service Description',
                    '''VPN MASTER provides a virtual private network service that:

• Encrypts your internet connection for privacy and security
• Allows access to geo-restricted content
• Protects your data on public Wi-Fi networks
• Provides servers in multiple global locations
• Offers both free and premium subscription tiers

The Service is provided "as is" and we reserve the right to modify or discontinue features at any time.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 400),
                  child: _buildSection(
                    'Acceptable Use Policy',
                    '''You agree to use our Service only for lawful purposes and in accordance with these Terms. You SHALL NOT:

• Use the Service for any illegal activities
• Attempt to hack, crack, or circumvent our security measures
• Share your account credentials with others
• Use the Service to transmit malware, spam, or harmful content
• Violate any applicable laws or regulations
• Infringe on intellectual property rights of others
• Use automated systems to access our servers excessively

Violation of these terms may result in immediate account termination.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 500),
                  child: _buildSection(
                    'Subscription and Payments',
                    '''Premium subscriptions are billed in advance on a recurring basis:

• Free tier: Limited features with advertisements
• Premium subscriptions: Full features without ads
• Payment is charged to your chosen payment method
• Subscriptions auto-renew unless cancelled before renewal date
• Refunds are subject to our refund policy and applicable laws
• Price changes will be communicated 30 days in advance

You can manage your subscription through your device's app store settings.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 600),
                  child: _buildSection(
                    'Privacy and Data Protection',
                    '''Your privacy is important to us:

• We operate under a strict no-logs policy
• Personal data is handled according to our Privacy Policy
• We use industry-standard encryption and security measures
• Data retention is minimized to what's necessary for service operation
• You have rights regarding your personal data under applicable laws

Please review our Privacy Policy for detailed information about data handling.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 700),
                  child: _buildSection(
                    'Service Availability',
                    '''While we strive for maximum uptime:

• Service availability is not guaranteed 100% of the time
• Maintenance may require temporary service interruptions
• Network conditions may affect connection quality
• Some content may remain geo-blocked due to licensing restrictions
• Server locations may change based on operational requirements

We will provide reasonable notice for planned maintenance whenever possible.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 800),
                  child: _buildSection(
                    'Intellectual Property',
                    '''All content and technology provided through our Service is protected:

• The VPN MASTER name, logo, and branding are our trademarks
• The app, software, and service technology are our proprietary property
• You receive a limited license to use our Service for personal use only
• Reverse engineering, copying, or distributing our technology is prohibited
• User-generated content remains your property but you grant us usage rights

We respect intellectual property rights and expect users to do the same.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 900),
                  child: _buildSection(
                    'Limitation of Liability',
                    '''To the maximum extent permitted by law:

• Our liability is limited to the amount you paid for the Service
• We are not liable for indirect, incidental, or consequential damages
• We do not guarantee the Service will meet your specific requirements
• You use the Service at your own risk
• We are not responsible for content accessed through our Service
• Some jurisdictions do not allow certain liability limitations

This limitation applies even if we have been advised of the possibility of such damages.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 1000),
                  child: _buildSection(
                    'Termination',
                    '''Either party may terminate this agreement:

• You can cancel your subscription at any time
• We may terminate accounts for Terms violations
• Termination does not affect rights and obligations that accrued before termination
• Upon termination, your right to use the Service ceases immediately
• Data deletion will occur according to our Privacy Policy

Paid subscriptions will continue until the end of the current billing period.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 1100),
                  child: _buildSection(
                    'Governing Law',
                    '''These Terms are governed by and construed in accordance with applicable laws. Any disputes arising from these Terms or your use of the Service will be resolved through binding arbitration or in the courts of our jurisdiction.

If any provision of these Terms is found to be unenforceable, the remaining provisions will remain in full force and effect.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 1200),
                  child: _buildSection(
                    'Changes to Terms',
                    '''We may update these Terms periodically:

• Material changes will be communicated through the app or email
• Continued use of the Service constitutes acceptance of updated Terms
• If you disagree with changes, you may terminate your account
• The latest version will always be available in the app

We encourage you to review these Terms periodically for any updates.''',
                    isDarkMode,
                  ),
                ),

                const SizedBox(height: 20),

                FadeInUp(
                  delay: const Duration(milliseconds: 1300),
                  child: _buildSection(
                    'Contact Information',
                    '''For questions about these Terms or our Service:

• Email: support@albonik.com
• Support: Through the app's support section
• Website: https://albonik.com
• Address: New Mexico,US

We will respond to inquiries within 48 hours during business days.''',
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

