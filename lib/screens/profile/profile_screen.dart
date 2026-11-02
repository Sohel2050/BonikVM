import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../providers/auth_providers.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_field.dart';
import '../../core/localization/app_localizations.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  bool _isEditing = false;
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeUserData();
  }

  void _initializeUserData() {
    final authState = ref.read(authStateProvider);
    final user = authState.firebaseUser;
    if (user != null) {
      _nameController.text = user.displayName ?? '';
      _emailController.text = user.email ?? '';
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final user = authState.firebaseUser;

    return Scaffold(
      backgroundColor: const Color(0xFF0A0E27),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(
          tr('prof_title'),
          style: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          if (!_isEditing)
            IconButton(
              icon: const Icon(Icons.edit, color: Color(0xFF00D2FF)),
              onPressed: () => setState(() => _isEditing = true),
            ),
        ],
      ),
      body: user == null
          ? Center(
              child: Text(
                tr('prof_no_data'),
                style: TextStyle(color: Colors.white),
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  // Profile Header
                  FadeInDown(
                    duration: const Duration(milliseconds: 600),
                    child: _buildProfileHeader(user),
                  ),

                  const SizedBox(height: 40),

                  // Profile Information
                  FadeInUp(
                    duration: const Duration(milliseconds: 600),
                    delay: const Duration(milliseconds: 200),
                    child: _buildProfileInfo(user),
                  ),

                  const SizedBox(height: 30),

                  // Subscription Information
                  FadeInUp(
                    duration: const Duration(milliseconds: 600),
                    delay: const Duration(milliseconds: 400),
                    child: _buildSubscriptionInfo(),
                  ),

                  const SizedBox(height: 30),

                  // Action Buttons
                  FadeInUp(
                    duration: const Duration(milliseconds: 600),
                    delay: const Duration(milliseconds: 600),
                    child: _buildActionButtons(authState),
                  ),

                  const SizedBox(height: 30),

                  // Danger Zone
                  FadeInUp(
                    duration: const Duration(milliseconds: 600),
                    delay: const Duration(milliseconds: 800),
                    child: _buildDangerZone(authState),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildProfileHeader(User user) {
    return Column(
      children: [
        CircleAvatar(
          radius: 50,
          backgroundColor: const Color(0xFF00D2FF).withValues(alpha: 0.2),
          backgroundImage: user.photoURL != null
              ? NetworkImage(user.photoURL!)
              : null,
          child: user.photoURL == null
              ? const Icon(Icons.person, size: 50, color: Color(0xFF00D2FF))
              : null,
        ),
        const SizedBox(height: 16),
        Text(
          user.displayName ?? tr('user_word'),
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: user.emailVerified
                ? Colors.green.withValues(alpha: 0.2)
                : Colors.orange.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: user.emailVerified ? Colors.green : Colors.orange,
            ),
          ),
          child: Text(
            user.emailVerified ? tr('prof_verified') : tr('prof_not_verified'),
            style: TextStyle(
              color: user.emailVerified ? Colors.green : Colors.orange,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProfileInfo(User user) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[700]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('prof_account_info'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 20),

          if (_isEditing) ...[
            CustomTextField(
              controller: _nameController,
              labelText: tr('prof_display_name'),
              prefixIcon: Icons.person_outline,
            ),
            const SizedBox(height: 16),
            CustomTextField(
              controller: _emailController,
              labelText: tr('prof_email_address'),
              prefixIcon: Icons.email_outlined,
              readOnly: true, // Email cannot be changed easily
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: CustomButton(
                    onPressed: _saveProfile,
                    child: Text(tr('prof_save_changes')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: CustomButton(
                    onPressed: () {
                      setState(() => _isEditing = false);
                      _initializeUserData();
                    },
                    backgroundColor: Colors.grey[600],
                    child: Text(tr('cancel')),
                  ),
                ),
              ],
            ),
          ] else ...[
            _buildInfoRow(tr('name'), user.displayName ?? tr('prof_not_set')),
            const SizedBox(height: 16),
            _buildInfoRow(tr('email'), user.email ?? tr('prof_not_available')),
            const SizedBox(height: 16),
            _buildInfoRow(tr('prof_provider'), _getProviderName(user)),
            const SizedBox(height: 16),
            _buildInfoRow(tr('prof_member_since'), _getJoinDate(user)),
          ],
        ],
      ),
    );
  }

  Widget _buildSubscriptionInfo() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1F3A).withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey[700]!, width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('prof_sub_status'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF00D2FF).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: const Color(0xFF00D2FF).withValues(alpha: 0.3),
              ),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Color(0xFF00D2FF), size: 20),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    tr('prof_sub_info'),
                    style: TextStyle(color: Colors.white, fontSize: 14),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(AuthState authState) {
    return Column(
      children: [
        CustomButton(
          onPressed: authState.isLoading ? null : _restorePurchases,
          isLoading: authState.isLoading,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.restore, color: Colors.white),
              SizedBox(width: 8),
              Text(
                tr('restore_purchases'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        CustomButton(
          onPressed: authState.isLoading ? null : _linkWithGoogle,
          backgroundColor: Colors.orange,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.link, color: Colors.white),
              SizedBox(width: 8),
              Text(
                tr('prof_link_google'),
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDangerZone(AuthState authState) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3), width: 1),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            tr('prof_danger_zone'),
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.red,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            tr('prof_cannot_undo'),
            style: TextStyle(color: Colors.grey, fontSize: 14),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: CustomButton(
                  onPressed: authState.isLoading ? null : _signOut,
                  backgroundColor: Colors.grey[600],
                  child: Text(
                    tr('sign_out'),
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: CustomButton(
                  onPressed: authState.isLoading ? null : _deleteAccount,
                  backgroundColor: Colors.red,
                  child: Text(
                    tr('delete_account'),
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(color: Colors.grey[400], fontSize: 14),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }

  String _getProviderName(User user) {
    if (user.providerData.isEmpty) return tr('email');

    final providerId = user.providerData.first.providerId;
    switch (providerId) {
      case 'google.com':
        return 'Google';
      case 'apple.com':
        return 'Apple';
      case 'facebook.com':
        return 'Facebook';
      default:
        return tr('email');
    }
  }

  String _getJoinDate(User user) {
    final creationTime = user.metadata.creationTime;
    if (creationTime == null) return tr('unknown');

    return '${creationTime.day}/${creationTime.month}/${creationTime.year}';
  }

  void _saveProfile() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        await user.updateDisplayName(_nameController.text.trim());
        setState(() => _isEditing = false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(tr('prof_updated')),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(tr('prof_update_failed', {'e': '$e'})),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _restorePurchases() {
    ref.read(authStateProvider.notifier).restorePurchases();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr('restoring_purchases')),
        backgroundColor: Color(0xFF00D2FF),
      ),
    );
  }

  void _linkWithGoogle() {
    ref.read(authStateProvider.notifier).linkWithGoogle();
  }

  void _signOut() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: Text(tr('sign_out'), style: TextStyle(color: Colors.white)),
        content: Text(
          tr('prof_sign_out_q'),
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel'), style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              ref.read(authStateProvider.notifier).signOut();
            },
            child: Text(tr('sign_out'), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  void _deleteAccount() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1F3A),
        title: Text(
          tr('delete_account'),
          style: TextStyle(color: Colors.red),
        ),
        content: Text(
          tr('prof_delete_msg'),
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(tr('cancel'), style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(authStateProvider.notifier).deleteAccount();
              if (context.mounted) {
                Navigator.of(
                  context,
                ).pushNamedAndRemoveUntil('/splash', (route) => false);
              }
            },
            child: Text(tr('delete'), style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}
