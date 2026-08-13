import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../shared/providers/theme_provider.dart';

class ThemedAuthDialog extends ConsumerStatefulWidget {
  final VoidCallback? onSuccess;
  final bool showSkip;

  const ThemedAuthDialog({
    Key? key,
    this.onSuccess,
    this.showSkip = false,
  }) : super(key: key);

  @override
  ConsumerState<ThemedAuthDialog> createState() => _ThemedAuthDialogState();
}

class _ThemedAuthDialogState extends ConsumerState<ThemedAuthDialog> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;
    final authState = ref.watch(authStateProvider);

    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 400),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E1E1E) : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Row(
                children: [
                  Icon(
                    Icons.security,
                    color: ref.watch(themeColorProvider),
                    size: 24,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Authentication Required',
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(
                      Icons.close,
                      color: isDarkMode ? Colors.white70 : Colors.black54,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              Text(
                'Please sign in to purchase premium subscriptions and access all features.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDarkMode ? Colors.white70 : Colors.black54,
                ),
              ),

              const SizedBox(height: 24),

              // Google Sign-In Button
              _buildGoogleSignInButton(authState, isDarkMode),

              const SizedBox(height: 16),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: isDarkMode ? Colors.white24 : Colors.black26,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'OR',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDarkMode ? Colors.white54 : Colors.black45,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: isDarkMode ? Colors.white24 : Colors.black26,
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // Email/Password Form
              _buildEmailPasswordForm(authState, isDarkMode),

              if (widget.showSkip) ...[
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    'Skip for now',
                    style: TextStyle(
                      color: isDarkMode ? Colors.white54 : Colors.black54,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGoogleSignInButton(AuthState authState, bool isDarkMode) {
    return SizedBox(
      height: 48,
      child: ElevatedButton.icon(
        onPressed: authState.isLoading ? null : _signInWithGoogle,
        icon: authState.isLoading
            ? SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: ref.watch(themeColorProvider),
                ),
              )
            : Image.asset(
                'assets/icons/google.png',
                width: 20,
                height: 20,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.login,
                  color: ref.watch(themeColorProvider),
                ),
              ),
        label: Text(
          authState.isLoading ? 'Signing in...' : 'Continue with Google',
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[100],
          foregroundColor: isDarkMode ? Colors.white : Colors.black87,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: isDarkMode ? Colors.white24 : Colors.black26,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmailPasswordForm(AuthState authState, bool isDarkMode) {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          // Sign In / Sign Up Toggle
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => setState(() => _isSignUp = false),
                child: Text(
                  'Sign In',
                  style: TextStyle(
                    color: !_isSignUp
                        ? ref.watch(themeColorProvider)
                        : (isDarkMode ? Colors.white54 : Colors.black54),
                    fontWeight: !_isSignUp ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => setState(() => _isSignUp = true),
                child: Text(
                  'Sign Up',
                  style: TextStyle(
                    color: _isSignUp
                        ? ref.watch(themeColorProvider)
                        : (isDarkMode ? Colors.white54 : Colors.black54),
                    fontWeight: _isSignUp ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Name field (only for sign up)
          if (_isSignUp) ...[
            _buildTextField(
              controller: _nameController,
              label: 'Full Name',
              icon: Icons.person,
              isDarkMode: isDarkMode,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter your full name';
                }
                return null;
              },
            ),
            const SizedBox(height: 16),
          ],

          // Email field
          _buildTextField(
            controller: _emailController,
            label: 'Email',
            icon: Icons.email,
            isDarkMode: isDarkMode,
            keyboardType: TextInputType.emailAddress,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your email';
              }
              if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                return 'Please enter a valid email';
              }
              return null;
            },
          ),

          const SizedBox(height: 16),

          // Password field
          _buildTextField(
            controller: _passwordController,
            label: 'Password',
            icon: Icons.lock,
            isDarkMode: isDarkMode,
            obscureText: _obscurePassword,
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(
                _obscurePassword ? Icons.visibility : Icons.visibility_off,
                color: isDarkMode ? Colors.white54 : Colors.black54,
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your password';
              }
              if (_isSignUp && value.length < 6) {
                return 'Password must be at least 6 characters';
              }
              return null;
            },
          ),

          const SizedBox(height: 24),

          // Submit button
          SizedBox(
            height: 48,
            width: double.infinity,
            child: ElevatedButton(
              onPressed: authState.isLoading ? null : _handleEmailPasswordAuth,
              style: ElevatedButton.styleFrom(
                backgroundColor: ref.watch(themeColorProvider),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                elevation: 0,
              ),
              child: authState.isLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      _isSignUp ? 'Create Account' : 'Sign In',
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
            ),
          ),

          if (!_isSignUp) ...[
            const SizedBox(height: 12),
            TextButton(
              onPressed: _forgotPassword,
              child: Text(
                'Forgot Password?',
                style: TextStyle(
                  color: ref.watch(themeColorProvider),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool isDarkMode,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      style: TextStyle(
        color: isDarkMode ? Colors.white : Colors.black87,
      ),
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(
          icon,
          color: isDarkMode ? Colors.white54 : Colors.black54,
        ),
        suffixIcon: suffixIcon,
        labelStyle: TextStyle(
          color: isDarkMode ? Colors.white54 : Colors.black54,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white24 : Colors.black26,
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: isDarkMode ? Colors.white24 : Colors.black26,
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(
            color: ref.watch(themeColorProvider),
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Colors.red,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: Colors.red,
            width: 2,
          ),
        ),
        filled: true,
        fillColor: isDarkMode ? const Color(0xFF2A2A2A) : Colors.grey[50],
      ),
    );
  }

  Future<void> _signInWithGoogle() async {
    try {
      await ref.read(authStateProvider.notifier).signInWithGoogle();
      
      if (mounted) {
        _showSuccess('Successfully signed in with Google!');
        widget.onSuccess?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showError('Google sign-in failed: ${e.toString()}');
      }
    }
  }

  Future<void> _handleEmailPasswordAuth() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      if (_isSignUp) {
        await ref.read(authStateProvider.notifier).createAccount(
          _emailController.text.trim(),
          _passwordController.text,
          _nameController.text.trim(),
        );
        
        if (mounted) {
          _showSuccess('Account created successfully!');
        }
      } else {
        await ref.read(authStateProvider.notifier).signInWithEmailAndPassword(
          _emailController.text.trim(),
          _passwordController.text,
        );
        
        if (mounted) {
          _showSuccess('Successfully signed in!');
        }
      }
      
      if (mounted) {
        widget.onSuccess?.call();
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        _showError('Authentication failed: ${e.toString()}');
      }
    }
  }

  Future<void> _forgotPassword() async {
    if (_emailController.text.trim().isEmpty) {
      _showError('Please enter your email address first');
      return;
    }

    try {
      await ref.read(authStateProvider.notifier).sendPasswordReset(
        _emailController.text.trim(),
      );
      
      if (mounted) {
        _showSuccess('Password reset email sent!');
      }
    } catch (e) {
      if (mounted) {
        _showError('Failed to send password reset: ${e.toString()}');
      }
    }
  }

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }
}

