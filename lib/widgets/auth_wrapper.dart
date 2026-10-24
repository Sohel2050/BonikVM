import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/auth_providers.dart';
import '../screens/auth/sign_in_screen.dart';

class AuthWrapper extends ConsumerWidget {
  final Widget child;

  const AuthWrapper({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    // Show loading screen while checking auth state
    if (authState.status == AuthStatus.initial ||
        authState.status == AuthStatus.loading) {
      return const Scaffold(
        backgroundColor: Color(0xFF0A0E27),
        body: Center(
          child: CircularProgressIndicator(
            valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF00D2FF)),
          ),
        ),
      );
    }

    // Show main app if authenticated (this takes priority over error state)
    if (authState.status == AuthStatus.authenticated && authState.isAuthenticated) {
      return child;
    }

    // Show sign-in screen if not authenticated
    return const SignInScreen();
  }
}

class AuthGuard extends ConsumerWidget {
  final Widget child;
  final bool requireAuth;

  const AuthGuard({super.key, required this.child, this.requireAuth = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authState = ref.watch(authStateProvider);

    if (!requireAuth) {
      return child;
    }

    if (authState.status == AuthStatus.unauthenticated) {
      return const SignInScreen();
    }

    return child;
  }
}

