import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:onesignal_flutter/onesignal_flutter.dart';
import '../models/user_model.dart';
import '../services/auth_service.dart';
import '../repositories/api_repository.dart';
import '../core/services/notification_service.dart';
import 'subscription_provider.dart';

// API Repository Provider
final apiRepositoryProvider = Provider<ApiRepository>((ref) {
  return ApiRepository();
});

// Auth Service Provider
final authServiceProvider = Provider<AuthService>((ref) {
  final apiRepository = ref.read(apiRepositoryProvider);
  return AuthService(apiRepository);
});

// Firebase Auth Stream Provider
final firebaseAuthStateProvider = StreamProvider<User?>((ref) {
  final authService = ref.read(authServiceProvider);
  return authService.authStateChanges;
});

// Current User Provider
final currentUserProvider = Provider<User?>((ref) {
  final authService = ref.read(authServiceProvider);
  return authService.currentUser;
});

// User Model Provider (combines Firebase user with local data)
final userModelProvider = FutureProvider<UserModel?>((ref) async {
  final authService = ref.read(authServiceProvider);
  final firebaseUser = authService.currentUser;

  if (firebaseUser == null) return null;

  // Try to get from local storage first
  // Since getLocalUser doesn't exist, create directly from Firebase user
  return UserModel(
    id: firebaseUser.uid,
    email: firebaseUser.email ?? '',
    name: firebaseUser.displayName ?? '',
    photoUrl: firebaseUser.photoURL,
    isEmailVerified: firebaseUser.emailVerified,
    provider: firebaseUser.providerData.isNotEmpty
        ? firebaseUser.providerData.first.providerId
        : 'email',
    createdAt: firebaseUser.metadata.creationTime ?? DateTime.now(),
    lastLoginAt: DateTime.now(),
  );
});

// Authentication State Provider
final authStateProvider = StateNotifierProvider<AuthStateNotifier, AuthState>((
    ref,
    ) {
  final authService = ref.read(authServiceProvider);
  return AuthStateNotifier(authService, ref);
});

// Auth State
enum AuthStatus { initial, loading, authenticated, unauthenticated, error }

class AuthState {
  final AuthStatus status;
  final User? firebaseUser;
  final UserModel? userModel;
  final String? errorMessage;
  final bool isLoading;
  final String? lastAction;

  const AuthState({
    this.status = AuthStatus.initial,
    this.firebaseUser,
    this.userModel,
    this.errorMessage,
    this.isLoading = false,
    this.lastAction,
  });

  AuthState copyWith({
    AuthStatus? status,
    User? firebaseUser,
    UserModel? userModel,
    String? errorMessage,
    bool? isLoading,
    String? lastAction,
  }) {
    return AuthState(
      status: status ?? this.status,
      firebaseUser: firebaseUser ?? this.firebaseUser,
      userModel: userModel ?? this.userModel,
      errorMessage: errorMessage ?? this.errorMessage,
      isLoading: isLoading ?? this.isLoading,
      lastAction: lastAction ?? this.lastAction,
    );
  }

  bool get isAuthenticated =>
      status == AuthStatus.authenticated && firebaseUser != null;
  bool get isUnauthenticated => status == AuthStatus.unauthenticated;
  bool get hasError => status == AuthStatus.error;
}

// Auth State Notifier
class AuthStateNotifier extends StateNotifier<AuthState> {
  final AuthService _authService;
  final Ref _ref;

  AuthStateNotifier(this._authService, this._ref) : super(const AuthState()) {
    _init();
  }

  void _init() {
    // Listen to Firebase auth state changes with immediate response
    _authService.authStateChanges.listen(
          (user) {
        if (user != null) {
          _setAuthenticated(user);
        } else {
          // Ensure complete unauthenticated state when user is null
          // Preserve lastAction so navigation listeners (e.g. after account deletion) still work
          state = AuthState(
            status: AuthStatus.unauthenticated,
            firebaseUser: null,
            userModel: null,
            errorMessage: null,
            isLoading: false,
            lastAction: state.lastAction,
          );
        }
      },
      onError: (error) {
        _setError(error.toString());
      },
    );
  }

  void _setAuthenticated(User user) async {
    try {
      // SECURITY: Account ID Immutability Check
      // Ensure the authenticated user UID matches the previously authenticated UID
      if (state.firebaseUser != null && state.firebaseUser!.uid != user.uid) {

        // This is a critical security issue - log and reject silently
        // Force logout to prevent account hijacking
        await _authService.signOut();
        _setError('Account ID mismatch detected. Please sign in again.');
        return;
      }

      // Create user model directly from Firebase user
      final userModel = UserModel(
        id: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? '',
        photoUrl: user.photoURL,
        isEmailVerified: user.emailVerified,
        provider: user.providerData.isNotEmpty
            ? user.providerData.first.providerId
            : 'firebase',
        createdAt: user.metadata.creationTime ?? DateTime.now(),
        lastLoginAt: DateTime.now(),
      );

      // IMMEDIATELY set to authenticated state - no delays
      state = AuthState(
        status: AuthStatus.authenticated,
        firebaseUser: user,
        userModel: userModel,
        errorMessage: null,
        isLoading: false,
      );

      // Update notification service with authenticated user ID
      NotificationService().updateUserId(user.uid);

      // Link this device to the logged-in user in OneSignal so the admin
      // panel can target notifications at a specific user (not just
      // broadcast to everyone). Non-fatal if it fails.
      try {
        await OneSignal.login(user.uid);
      } catch (e) {
        // Push linking failure shouldn't block login
      }

      // Check subscription status after authentication
      try {
        await _ref
            .read(subscriptionProvider.notifier)
            .checkSubscriptionStatus(user.uid);
      } catch (e) {
        // Don't block authentication if subscription check fails
      }
    } catch (e) {
      _setError(e.toString());
    }
  }

  void _setError(String error) {
    state = state.copyWith(
      status: AuthStatus.error,
      errorMessage: error,
      isLoading: false,
    );
  }

  void _setLoading() {
    state = state.copyWith(
      status: AuthStatus.loading,
      isLoading: true,
      errorMessage: null,
    );
  }

  // Sign in with Google
  Future<void> signInWithGoogle() async {
    _setLoading();
    try {
      final result = await _authService.signInWithGoogle();
      if (result == null) {
        // User cancelled the Google account picker - reset to unauthenticated cleanly
        state = const AuthState(
          status: AuthStatus.unauthenticated,
          isLoading: false,
        );
        return;
      }
      // Success: let the Firebase auth state listener call _setAuthenticated
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Sign in with Apple
  Future<void> signInWithApple() async {
    _setLoading();
    try {
      final result = await _authService.signInWithApple();
      if (result == null) {
        state = const AuthState(
          status: AuthStatus.unauthenticated,
          isLoading: false,
        );
        return;
      }
      // Success: Firebase auth state listener handles the rest
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Sign in with email and password
  Future<void> signInWithEmailAndPassword(String email, String password) async {
    _setLoading();
    try {
      await _authService.signInWithEmail(
        email,
        password,
      ); // Don't set state here - let the auth state listener handle it
      // The _setAuthenticated method will be called automatically when Firebase auth state changes
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Create account
  Future<void> createAccount(String email, String password, String name) async {
    _setLoading();
    try {
      await _authService.signUpWithEmail(email, password, name);
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Sign out
  Future<void> signOut() async {
    _setLoading();
    try {
      await _authService.signOut();
      try {
        await OneSignal.logout();
      } catch (e) {
        // Non-fatal
      }
      // Force complete state reset to ensure logout works
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        firebaseUser: null,
        userModel: null,
        errorMessage: null,
        isLoading: false,
        lastAction: 'signOut',
      );
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Delete account
  Future<void> deleteAccount() async {
    _setLoading();
    try {
      await _authService.deleteAccount();
      // Explicitly sign out and reset state after deletion
      state = const AuthState(
        status: AuthStatus.unauthenticated,
        firebaseUser: null,
        userModel: null,
        errorMessage: null,
        isLoading: false,
        lastAction: 'deleteAccount',
      );
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Send password reset
  Future<void> sendPasswordReset(String email) async {
    _setLoading();
    try {
      await _authService.resetPassword(email);
      // Clear loading state and ensure no error state after successful password reset
      state = state.copyWith(
        isLoading: false,
        status: AuthStatus.unauthenticated, // Maintain unauthenticated status
        errorMessage: null,
      );
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Restore purchases — actual restore logic is handled in settings_screen
  // via PurchaseService stream. This method is kept as a no-op so callers
  // that still reference it do not break.
  Future<void> restorePurchases() async {
    // No-op: settings_screen._handleRestorePurchases() calls PurchaseService
    // directly and verifies each restored purchase with the backend API.
  }

  // Link with Google
  Future<void> linkWithGoogle() async {
    _setLoading();
    try {
      // Use regular Google sign in since linkWithGoogle doesn't exist
      await _authService.signInWithGoogle();
    } catch (e) {
      _setError(e.toString());
    }
  }

  // Sign in anonymously / continue as guest
  Future<void> signInAnonymously() async {
    // Guest mode: allow access to home screen without authentication.
    // Deliberately not `const` — state_notifier's default change-detection
    // uses `identical(old, new)`, and a `const` literal here would
    // canonicalize to the same instance on every call, so tapping "Continue
    // as Guest" a second time (already in guest mode) would silently produce
    // no state change and no listener notification.
    state = AuthState(
      status: AuthStatus.unauthenticated,
      isLoading: false,
      lastAction: 'guest',
    );
  }

  // Clear error
  void clearError() {
    state = state.copyWith(
      status: state.firebaseUser != null
          ? AuthStatus.authenticated
          : AuthStatus.unauthenticated,
      errorMessage: null,
    );
  }
}
