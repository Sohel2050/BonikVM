import 'dart:io' show Platform;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import '../../providers/auth_providers.dart';
import '../../shared/providers/theme_provider.dart';
import '../../core/localization/app_localizations.dart';
import 'legal_webview_screen.dart';

// ─── Color palette ────────────────────────────────────────────────────────────
class _C {
  static const navy = Color(0xFF050E1F);
  static const navyField = Color(0xFF0D1B33);
  static const neon = Color(0xFF00C2FF);
  static const gradA = Color(0xFF00AAFF);
  static const gradB = Color(0xFF0050F0);
  static const muted = Color(0xFF8BA3C1);
  static const border = Color(0x1AFFFFFF);
  // light mode
  static const lightBg = Color(0xFFF0F5FF);
  static const lightBorder = Color(0xFFDDE3F0);
  static const lightText = Color(0xFF0A1628);
  static const lightMuted = Color(0xFF5B7096);
  static const lightIcon = Color(0xFF7B90B2);
}

class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  static const _termsUrl = 'https://albonik.com/privacy-policy/vpn-master.txt';
  static const _privacyUrl = 'https://albonik.com/privacy-policy/vpn-master.txt';
  static const _appleEulaUrl =
      'https://www.apple.com/legal/internet-services/itunes/dev/albonikllc/';

  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isPasswordVisible = false;
  bool _isSignUp = false;
  bool _hasAcceptedTerms = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeColor = ref.watch(themeColorProvider);
    final l10n = AppLocalizations.of(context);

    ref.listen<AuthState>(authStateProvider, (previous, next) {
      if (!mounted) return;
      if (next.status == AuthStatus.unauthenticated &&
          next.lastAction == 'guest') {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/home', (route) => false);
        return;
      }
      if (previous?.status != AuthStatus.authenticated &&
          next.status == AuthStatus.authenticated) {
        if (!context.mounted) return;
        final displayName =
            next.firebaseUser?.displayName ??
            next.firebaseUser?.email ??
            'User';
        Navigator.of(context).pop();
        // Show snackbar on the parent screen (context is still valid at pop)
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final messenger = ScaffoldMessenger.maybeOf(context);
          messenger?.showSnackBar(
            SnackBar(
              content: Text('Welcome, $displayName!'),
              backgroundColor: themeColor,
              duration: const Duration(seconds: 2),
            ),
          );
        });
      }
    });

    final bg = isDark ? _C.navy : _C.lightBg;
    final fieldBg = isDark ? _C.navyField : Colors.white;
    final fieldBorder = isDark ? _C.border : _C.lightBorder;
    final labelColor = isDark ? Colors.white : _C.lightText;
    final hintColor = isDark ? _C.muted : _C.lightMuted;
    final iconColor = isDark ? _C.muted : _C.lightIcon;
    final subtitleColor = isDark ? _C.muted : _C.lightMuted;
    final showApple = Platform.isIOS || Platform.isMacOS;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),

              // ── Logo + Title ───────────────────────────────────────────────
              FadeInDown(
                duration: const Duration(milliseconds: 600),
                child: Column(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(34),
                      child: Image.asset(
                        'assets/images/app_icon.png',
                        height: 96,
                        width: 96,
                        errorBuilder: (_, __, ___) => Container(
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
                    const SizedBox(height: 12),
                    RichText(
                      text: TextSpan(
                        children: [
                          TextSpan(
                            text: 'VPN ',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: themeColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                          TextSpan(
                            text: 'MASTER',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: labelColor,
                              letterSpacing: -0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _isSignUp
                          ? l10n.createYourAccount
                          : l10n.loginSignInContinue,
                      style: TextStyle(fontSize: 15, color: subtitleColor),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),

             /* // ── Social buttons (side-by-side on iOS, full-width on Android) ──
              FadeInUp(
                duration: const Duration(milliseconds: 500),
                delay: const Duration(milliseconds: 100),
                child: showApple
                    ? Row(
                        children: [
                          Expanded(
                            child: _SocialButton(
                              onTap: authState.isLoading
                                  ? null
                                  : () => _runIfTermsAccepted(
                                      () => ref
                                          .read(authStateProvider.notifier)
                                          .signInWithGoogle(),
                                    ),
                              backgroundColor: Colors.white,
                              borderColor: Colors.transparent,
                              icon: _GoogleGIcon(),
                              label: 'Google',
                              labelColor: const Color(0xFF1A1A1A),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SocialButton(
                              onTap: authState.isLoading
                                  ? null
                                  : () => _runIfTermsAccepted(
                                      () => ref
                                          .read(authStateProvider.notifier)
                                          .signInWithApple(),
                                    ),
                              backgroundColor: const Color(0xFF0A0A0A),
                              borderColor: const Color(0xFF333333),
                              icon: const Icon(
                                Icons.apple,
                                color: Colors.white,
                                size: 22,
                              ),
                              label: 'Apple',
                              labelColor: Colors.white,
                            ),
                          ),
                        ],
                      )
                    : _SocialButton(
                        onTap: authState.isLoading
                            ? null
                            : () => _runIfTermsAccepted(
                                () => ref
                                    .read(authStateProvider.notifier)
                                    .signInWithGoogle(),
                              ),
                        backgroundColor: Colors.white,
                        borderColor: Colors.transparent,
                        icon: _GoogleGIcon(),
                        label: l10n.continueWithGoogle,
                        labelColor: const Color(0xFF1A1A1A),
                      ),
              ),

              const SizedBox(height: 22),

              // ── OR divider ─────────────────────────────────────────────────
              FadeInUp(
                duration: const Duration(milliseconds: 500),
                delay: const Duration(milliseconds: 200),
                child: Row(
                  children: [
                    Expanded(
                      child: Divider(
                        color: isDark ? _C.border : _C.lightBorder,
                        thickness: 1,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        l10n.or,
                        style: TextStyle(
                          color: hintColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Divider(
                        color: isDark ? _C.border : _C.lightBorder,
                        thickness: 1,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),
*/
              // ── Form ───────────────────────────────────────────────────────
              FadeInUp(
                duration: const Duration(milliseconds: 500),
                delay: const Duration(milliseconds: 310),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_isSignUp) ...[
                        _FieldLabel('Full Name', labelColor),
                        const SizedBox(height: 6),
                        _AuthInput(
                          controller: _nameController,
                          hint: 'Enter your full name',
                          prefixIcon: Icons.person_outline_rounded,
                          fieldBg: fieldBg,
                          fieldBorder: fieldBorder,
                          iconColor: iconColor,
                          hintColor: hintColor,
                          isDark: isDark,
                          themeColor: themeColor,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Please enter your full name'
                              : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      _FieldLabel(l10n.email, labelColor),
                      const SizedBox(height: 6),
                      _AuthInput(
                        controller: _emailController,
                        hint: l10n.enterEmail,
                        prefixIcon: Icons.email_outlined,
                        keyboardType: TextInputType.emailAddress,
                        fieldBg: fieldBg,
                        fieldBorder: fieldBorder,
                        iconColor: iconColor,
                        hintColor: hintColor,
                        isDark: isDark,
                        themeColor: themeColor,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty)
                            return 'Please enter your email';
                          if (!RegExp(
                            r'^[\w\-.]+@([\w-]+\.)+[\w-]{2,4}$',
                          ).hasMatch(v))
                            return 'Enter a valid email';
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      _FieldLabel(l10n.password, labelColor),
                      const SizedBox(height: 6),
                      _AuthInput(
                        controller: _passwordController,
                        hint: l10n.enterPassword,
                        prefixIcon: Icons.lock_outline_rounded,
                        obscureText: !_isPasswordVisible,
                        fieldBg: fieldBg,
                        fieldBorder: fieldBorder,
                        iconColor: iconColor,
                        hintColor: hintColor,
                        isDark: isDark,
                        themeColor: themeColor,
                        suffixIcon: GestureDetector(
                          onTap: () => setState(
                            () => _isPasswordVisible = !_isPasswordVisible,
                          ),
                          child: Icon(
                            _isPasswordVisible
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: iconColor,
                            size: 20,
                          ),
                        ),
                        validator: (v) {
                          if (v == null || v.isEmpty)
                            return 'Please enter your password';
                          if (_isSignUp && v.length < 6)
                            return 'At least 6 characters required';
                          return null;
                        },
                      ),
                      if (!_isSignUp) ...[
                        const SizedBox(height: 8),
                        Align(
                          alignment: Alignment.centerRight,
                          child: GestureDetector(
                            onTap: authState.isLoading
                                ? null
                                : _handleForgotPassword,
                            child: Text(
                              l10n.forgotPassword,
                              style: TextStyle(
                                color: themeColor,
                                fontSize: 13,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      // ── Terms acceptance checkbox ─────────────────────
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 24,
                            height: 24,
                            child: Checkbox(
                              value: _hasAcceptedTerms,
                              onChanged: (v) => setState(
                                () => _hasAcceptedTerms = v ?? false,
                              ),
                              activeColor: themeColor,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: RichText(
                              text: TextSpan(
                                text: 'I agree to the ',
                                style: TextStyle(
                                  color: subtitleColor,
                                  fontSize: 12,
                                ),
                                children: [
                                  TextSpan(
                                    text: 'Terms & Conditions',
                                    style: TextStyle(
                                      color: themeColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => _openLegalDocument(
                                        title: 'Terms & Conditions',
                                        url: _termsUrl,
                                      ),
                                  ),
                                  TextSpan(
                                    text: ' & ',
                                    style: TextStyle(
                                      color: subtitleColor,
                                      fontSize: 12,
                                    ),
                                  ),
                                  TextSpan(
                                    text: 'Privacy Policy',
                                    style: TextStyle(
                                      color: themeColor,
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                    recognizer: TapGestureRecognizer()
                                      ..onTap = () => _openLegalDocument(
                                        title: 'Privacy Policy',
                                        url: _privacyUrl,
                                      ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      if (authState.hasError) ...[
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          margin: const EdgeInsets.only(bottom: 14),
                          decoration: BoxDecoration(
                            color: Colors.red.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.red.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.error_outline,
                                color: Colors.redAccent,
                                size: 18,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  authState.errorMessage ?? 'An error occurred',
                                  style: const TextStyle(
                                    color: Colors.redAccent,
                                    fontSize: 13,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => ref
                                    .read(authStateProvider.notifier)
                                    .clearError(),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.redAccent,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      _GradientCTA(
                        onPressed: authState.isLoading
                            ? null
                            : () => _runIfTermsAccepted(_handleEmailAuth),
                        isLoading: authState.isLoading,
                        label: _isSignUp ? l10n.signUp : l10n.signIn,
                        themeColor: themeColor,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),

              // ── Toggle sign-up / sign-in ────────────────────────────────────
              FadeInUp(
                duration: const Duration(milliseconds: 500),
                delay: const Duration(milliseconds: 380),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      _isSignUp
                          ? '${l10n.alreadyHaveAccount}  '
                          : '${l10n.dontHaveAccount}  ',
                      style: TextStyle(color: subtitleColor, fontSize: 14),
                    ),
                    GestureDetector(
                      onTap: () {
                        setState(() => _isSignUp = !_isSignUp);
                        ref.read(authStateProvider.notifier).clearError();
                      },
                      child: Text(
                        _isSignUp ? l10n.signIn : l10n.signUp,
                        style: TextStyle(
                          color: themeColor,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 26),

              // ── Continue as Guest ──────────────────────────────────────────
              FadeInUp(
                duration: const Duration(milliseconds: 500),
                delay: const Duration(milliseconds: 440),
                child: GestureDetector(
                  onTap: authState.isLoading
                      ? null
                      : () => ref
                            .read(authStateProvider.notifier)
                            .signInAnonymously(),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.shield_outlined,
                          color: themeColor.withValues(alpha: 0.8),
                          size: 16,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          l10n.continueAsGuest,
                          style: TextStyle(
                            color: subtitleColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _runIfTermsAccepted(Future<void> Function() action) async {
    if (!_hasAcceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please accept the Terms & Conditions and Privacy Policy to continue.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 3),
        ),
      );
      return;
    }
    await action();
  }

  Future<void> _openLegalDocument({
    required String title,
    required String url,
  }) async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => LegalWebViewScreen(title: title, url: url),
      ),
    );
  }

  Future<void> _handleEmailAuth() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (_isSignUp) {
      await ref
          .read(authStateProvider.notifier)
          .createAccount(email, password, _nameController.text.trim());
    } else {
      await ref
          .read(authStateProvider.notifier)
          .signInWithEmailAndPassword(email, password);
    }
  }

  void _handleForgotPassword() {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter your email address first'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    ref.read(authStateProvider.notifier).sendPasswordReset(email);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Password reset email sent! Check your inbox.'),
        backgroundColor: Colors.green,
      ),
    );
  }
}

class _LegalAcceptanceCard extends StatelessWidget {
  final bool isChecked;
  final bool isDark;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onOpenTerms;
  final VoidCallback onOpenPrivacy;
  final VoidCallback? onOpenAppleEula;

  const _LegalAcceptanceCard({
    required this.isChecked,
    required this.isDark,
    required this.onChanged,
    required this.onOpenTerms,
    required this.onOpenPrivacy,
    this.onOpenAppleEula,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final l10n = AppLocalizations.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF161B22)
            : Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDark ? const Color(0xFF30363D) : _C.lightBorder,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Transform.translate(
            offset: const Offset(-8, -6),
            child: Checkbox(
              value: isChecked,
              activeColor: primary,
              onChanged: onChanged,
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.acceptLegalTerms,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : _C.lightText,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  l10n.legalAcceptanceDescription,
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: isDark ? const Color(0xFF8BA3C1) : _C.lightMuted,
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _LegalChip(label: l10n.privacyPolicy, onTap: onOpenPrivacy),
                    _LegalChip(label: l10n.termsConditions, onTap: onOpenTerms),
                    if (onOpenAppleEula != null)
                      _LegalChip(
                        label: l10n.appleEula,
                        onTap: onOpenAppleEula!,
                      ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegalChip extends StatelessWidget {
  const _LegalChip({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: primary,
        side: BorderSide(color: primary),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: Text(label),
    );
  }
}

// ─── Social Button ─────────────────────────────────────────────────────────────
class _SocialButton extends StatelessWidget {
  final VoidCallback? onTap;
  final Color backgroundColor;
  final Color borderColor;
  final Widget icon;
  final String label;
  final Color labelColor;

  const _SocialButton({
    required this.onTap,
    required this.backgroundColor,
    required this.borderColor,
    required this.icon,
    required this.label,
    required this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 52,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: borderColor, width: 1.2),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            icon,
            const SizedBox(width: 10),
            Text(
              label,
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Inline "By continuing..." legal links ─────────────────────────────────────
class _InlineLegalLinks extends StatelessWidget {
  final Color subtitleColor;
  final Color themeColor;
  final VoidCallback onOpenPrivacy;
  final VoidCallback onOpenTerms;
  final VoidCallback? onOpenAppleEula;

  const _InlineLegalLinks({
    required this.subtitleColor,
    required this.themeColor,
    required this.onOpenPrivacy,
    required this.onOpenTerms,
    this.onOpenAppleEula,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final linkStyle = TextStyle(
      color: themeColor,
      fontSize: 12,
      fontWeight: FontWeight.w600,
    );
    final plainStyle = TextStyle(color: subtitleColor, fontSize: 12);
    return Column(
      children: [
        Text(l10n.byContinuingAgree, style: plainStyle),
        const SizedBox(height: 6),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 6,
          runSpacing: 4,
          children: [
            GestureDetector(
              onTap: onOpenPrivacy,
              child: Text(l10n.privacyPolicy, style: linkStyle),
            ),
            Text(',', style: plainStyle),
            GestureDetector(
              onTap: onOpenTerms,
              child: Text(l10n.termsConditions, style: linkStyle),
            ),
            if (onOpenAppleEula != null) ...[
              Text('and', style: plainStyle),
              GestureDetector(
                onTap: onOpenAppleEula,
                child: Text(l10n.appleEula, style: linkStyle),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

// ─── Field label ───────────────────────────────────────────────────────────────
class _FieldLabel extends StatelessWidget {
  final String text;
  final Color color;
  const _FieldLabel(this.text, this.color);
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color),
  );
}

// ─── Auth input field ──────────────────────────────────────────────────────────
class _AuthInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData prefixIcon;
  final bool obscureText;
  final TextInputType? keyboardType;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final Color fieldBg;
  final Color fieldBorder;
  final Color iconColor;
  final Color hintColor;
  final bool isDark;
  final Color themeColor;

  const _AuthInput({
    required this.controller,
    required this.hint,
    required this.prefixIcon,
    this.obscureText = false,
    this.keyboardType,
    this.suffixIcon,
    this.validator,
    required this.fieldBg,
    required this.fieldBorder,
    required this.iconColor,
    required this.hintColor,
    required this.isDark,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      validator: validator,
      style: TextStyle(
        color: isDark ? Colors.white : _C.lightText,
        fontSize: 15,
      ),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(color: hintColor, fontSize: 14),
        prefixIcon: Icon(prefixIcon, color: iconColor, size: 20),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: fieldBg,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: fieldBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: fieldBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: themeColor, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.redAccent, width: 1.5),
        ),
      ),
    );
  }
}

// ─── Gradient CTA button ───────────────────────────────────────────────────────
class _GradientCTA extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final String label;
  final Color themeColor;

  const _GradientCTA({
    required this.onPressed,
    required this.isLoading,
    required this.label,
    required this.themeColor,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null;
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 54,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: disabled
                ? [Colors.grey.shade600, Colors.grey.shade700]
                : [
                    themeColor,
                    Color.lerp(themeColor, Colors.black, 0.2) ?? themeColor,
                  ],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: disabled
              ? []
              : [
                  BoxShadow(
                    color: themeColor.withValues(alpha: 0.45),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (isLoading)
              const SizedBox(
                height: 22,
                width: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            else ...[
              Text(
                label,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 0.3,
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white,
                size: 18,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── Google "G" icon (canvas fallback when PNG not available) ──────────────────
class _GoogleGIcon extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/google_icon.png',
      height: 22,
      width: 22,
      errorBuilder: (_, __, ___) =>
          CustomPaint(size: const Size(22, 22), painter: _GoogleGPainter()),
    );
  }
}

class _GoogleGPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const pi = 3.1415926535;
    final r = size.width / 2;
    final center = Offset(r, r);
    final p = Paint()..style = PaintingStyle.fill;

    canvas.clipPath(
      Path()..addOval(Rect.fromCircle(center: center, radius: r)),
    );
    p.color = Colors.white;
    canvas.drawCircle(center, r, p);

    final rect = Rect.fromCircle(center: center, radius: r * 0.72);
    final sw = r * 0.32;

    void arc(double start, double sweep, Color color) {
      canvas.drawArc(
        rect,
        start,
        sweep,
        false,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw
          ..strokeCap = StrokeCap.butt,
      );
    }

    arc(-pi / 2, pi / 2, const Color(0xFF4285F4));
    arc(0, pi / 2, const Color(0xFF34A853));
    arc(pi / 2, pi / 2, const Color(0xFFFBBC05));
    arc(pi, pi / 2, const Color(0xFFEA4335));

    final white = Paint()..color = Colors.white;
    canvas.drawRect(Rect.fromLTWH(r, r - sw / 2, r * 0.6, sw), white);
    canvas.drawCircle(center, r * 0.36, white);
  }

  @override
  bool shouldRepaint(_) => false;
}
