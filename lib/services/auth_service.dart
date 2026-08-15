import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/user_model.dart';
import '../repositories/api_repository.dart';
import '../core/services/purchase_service.dart';

class AuthService {
  final FirebaseAuth _firebaseAuth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
    // Remove clientId completely for Android - let it read from google-services.json
    // Enhanced configuration to fix API Exception 10
    signInOption: SignInOption.standard,
    // Force account selection to clear any cached sign-in state
    forceCodeForRefreshToken: true,
  );
  final ApiRepository _apiRepository;

  AuthService(this._apiRepository);

  // Current user stream
  Stream<User?> get authStateChanges => _firebaseAuth.authStateChanges();

  // Current user
  User? get currentUser => _firebaseAuth.currentUser;

  // Check if user is signed in
  bool get isSignedIn => currentUser != null;

  // Check if user is logged in (required for purchases)
  static bool get isLoggedIn => FirebaseAuth.instance.currentUser != null;

  /// Sign in with Google
  Future<UserCredential?> signInWithGoogle() async {
    try {
      // First, sign out to clear any cached state (fixes API 10 error)
      await _googleSignIn.signOut();

      // Then attempt fresh sign-in
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();

      if (googleUser == null) {
        return null;
      } // Get auth details
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;

      // Verify we have valid tokens
      if (googleAuth.accessToken == null || googleAuth.idToken == null) {
        throw Exception('Failed to obtain Google authentication tokens');
      }

      // Create credential
      final credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      // Sign in to Firebase
      final UserCredential userCredential = await _firebaseAuth
          .signInWithCredential(
            credential,
          ); // Try to sync with backend but don't block authentication
      _syncUserWithBackend(userCredential.user!).catchError((error) {});

      return userCredential;
    } catch (e) {
      // Clear any cached sign-in state on error
      await _googleSignIn.signOut();
      final msg = e.toString();
      // API exception 10 = SHA-1/SHA-256 not registered in Firebase console
      if (msg.contains('ApiException: 10') || msg.contains('sign_in_failed')) {
        throw Exception(
          'Google Sign-In is not available on this device or build. '
          'Please use email & password to sign in, or contact support.',
        );
      }
      if (msg.contains('network_error') || msg.contains('NetworkException')) {
        throw Exception(
          'No internet connection. Please check your network and try again.',
        );
      }
      throw Exception(
        'Google Sign-In failed. Please try again or use email & password.',
      );
    }
  }

  /// Sign in with Apple
  Future<UserCredential?> signInWithApple() async {
    try {
      final appleCredential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );

      final oauthCredential = OAuthProvider('apple.com').credential(
        idToken: appleCredential.identityToken,
        accessToken: appleCredential.authorizationCode,
      );

      final userCredential = await _firebaseAuth.signInWithCredential(
        oauthCredential,
      );

      // Update display name if provided by Apple (only on first sign-in)
      final fullName = [
        appleCredential.givenName,
        appleCredential.familyName,
      ].where((n) => n != null && n.isNotEmpty).join(' ');
      if (fullName.isNotEmpty &&
          (userCredential.user?.displayName?.isEmpty ?? true)) {
        await userCredential.user?.updateDisplayName(fullName);
      }

      _syncUserWithBackend(userCredential.user!).catchError((e) {
        debugPrint(
          '⚠️ Backend sync failed after Apple sign-in (non-fatal): $e',
        );
      });

      return userCredential;
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw Exception('Apple Sign-In failed: ${e.message}');
    } catch (e) {
      throw Exception('Apple Sign-In is not available on this device.');
    }
  }

  /// Sign up with email and password
  Future<UserCredential?> signUpWithEmail(
    String email,
    String password,
    String name,
  ) async {
    try {
      final UserCredential userCredential = await _firebaseAuth
          .createUserWithEmailAndPassword(email: email, password: password);

      // Update display name
      await userCredential.user?.updateDisplayName(name);
      await userCredential.user?.reload();

      // Send verification email immediately after account creation
      try {
        await userCredential.user?.sendEmailVerification();
        debugPrint('📧 Verification email sent to ${email}');
      } catch (e) {
        debugPrint('⚠️ Could not send verification email (non-fatal): $e');
      }

      // Sync user data with backend (non-blocking — backend issues shouldn't fail sign-up)
      _syncUserWithBackend(userCredential.user!).catchError((e) {
        debugPrint('⚠️ Backend sync failed after sign-up (non-fatal): $e');
      });

      return userCredential;
    } catch (e) {
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'email-already-in-use':
          // Same Windows plugin quirk as signInWithEmail() above — a
          // rejected create-account request (most commonly: email already
          // registered) surfaces as this generic code on Windows instead of
          // 'email-already-in-use'.
          case 'unknown-error':
            throw Exception(
              'An account already exists for that email. Please sign in instead.',
            );
          case 'invalid-email':
            throw Exception(
              'The email address is not valid. Please check and try again.',
            );
          case 'weak-password':
            throw Exception(
              'Password is too weak. Please use at least 8 characters with letters and numbers.',
            );
          case 'operation-not-allowed':
            throw Exception(
              'Email sign-up is currently disabled. Please contact support.',
            );
          default:
            throw Exception('Account creation failed: ${e.message ?? e.code}');
        }
      }
      throw Exception('Failed to create account. Please try again.');
    }
  }

  /// Sign in with email and password
  Future<UserCredential?> signInWithEmail(String email, String password) async {
    try {
      final UserCredential userCredential = await _firebaseAuth
          .signInWithEmailAndPassword(email: email, password: password);

      // Sync user data with backend (non-blocking — backend issues shouldn't fail sign-in)
      _syncUserWithBackend(userCredential.user!).catchError((e) {
        debugPrint('⚠️ Backend sync failed after sign-in (non-fatal): $e');
      });

      return userCredential;
    } catch (e) {
      if (e is FirebaseAuthException) {
        switch (e.code) {
          case 'user-not-found':
            throw Exception(
              'No account found for this email. Please sign up first.',
            );
          case 'wrong-password':
          case 'invalid-credential':
          // The Windows build of firebase_auth doesn't parse Firebase's
          // REST error body on failed sign-in attempts — it surfaces every
          // rejected credential (wrong password, unknown email, etc.) as
          // this generic code instead of the specific one. Verified: valid
          // credentials sign in successfully on Windows; only the error
          // path for invalid ones collapses to 'unknown-error'. Treating it
          // the same as wrong-password gives users a correct, actionable
          // message instead of a raw "internal error".
          case 'unknown-error':
            throw Exception('Incorrect email or password. Please try again.');
          case 'user-disabled':
            throw Exception(
              'This account has been disabled. Please contact support.',
            );
          case 'too-many-requests':
            throw Exception(
              'Too many failed attempts. Please wait a moment and try again.',
            );
          case 'invalid-email':
            throw Exception(
              'The email address is not valid. Please check and try again.',
            );
          default:
            throw Exception('Sign-in failed: ${e.message ?? e.code}');
        }
      }
      throw Exception(
        'Failed to sign in. Please check your credentials and try again.',
      );
    }
  }

  /// Sign out
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
      await _firebaseAuth.signOut();

      // Clear local storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      // Clear premium status cache
      await prefs.setBool('is_premium', false);
      await prefs.remove('premium_status');
      await prefs.remove('subscription_status');
      await prefs.remove('user_purchases');

      // CRITICAL FIX: Reset purchase service state to prevent premium status persisting after sign out
      try {
        await PurchaseService().resetPurchaseState();
      } catch (e) {}
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }

  /// Sync user data with backend
  Future<void> _syncUserWithBackend(User user) async {
    try {
      // Set auth token for API calls
      final idToken = await user.getIdToken();
      if (idToken != null) {
        _apiRepository.setAuthToken(idToken);
      } else {}

      // Determine provider from providerData
      String provider = 'email';
      if (user.providerData.isNotEmpty) {
        final providerId = user.providerData.first.providerId;
        if (providerId == 'google.com') {
          provider = 'google';
        } else if (providerId == 'facebook.com') {
          provider = 'facebook';
        } else if (providerId == 'password') {
          provider = 'email';
        } else {
          provider = providerId;
        }
      }

      final userModel = UserModel(
        id: user.uid,
        email: user.email ?? '',
        name: user.displayName ?? user.email?.split('@').first ?? 'User',
        photoUrl: user.photoURL,
        isEmailVerified: user.emailVerified,
        provider: provider,
        createdAt: user.metadata.creationTime ?? DateTime.now(),
        lastLoginAt: DateTime.now(),
      );
      final response = await _apiRepository.syncUser(
        userModel,
      ); // Check if response indicates success
      if (response['success'] == true) {
        // Store sync status in preferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('user_synced_with_backend', true);
        await prefs.setString(
          'last_sync_time',
          DateTime.now().toIso8601String(),
        );
      } else {
        // DON'T throw error - allow authentication to continue
      }
    } catch (e) {
      // Store sync failure status for retry later
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('user_synced_with_backend', false);
      await prefs.setString('last_sync_error', e.toString());
      await prefs.setString(
        'last_sync_attempt',
        DateTime.now().toIso8601String(),
      );

      // DON'T throw error - allow user to continue with Firebase auth only
      // The app can work without backend sync initially
    }
  }

  /// Get user purchases
  Future<List<Map<String, dynamic>>> getUserPurchases() async {
    if (!isSignedIn) return [];

    try {
      // Set auth token
      final idToken = await currentUser!.getIdToken();
      if (idToken != null) {
        _apiRepository.setAuthToken(idToken);
      }

      final transactions = await _apiRepository.getUserTransactions();
      return transactions;
    } catch (e) {
      return [];
    }
  }

  /// Get current subscription status
  Future<Map<String, dynamic>?> getSubscriptionStatus() async {
    if (!isSignedIn) return null;

    try {
      // Set auth token
      final idToken = await currentUser!.getIdToken();
      if (idToken != null) {
        _apiRepository.setAuthToken(idToken);
      }

      final transactions = await _apiRepository.getUserTransactions();

      // Find the most recent active subscription
      Map<String, dynamic>? activeSubscription;
      for (var transaction in transactions) {
        if (transaction['type'] == 'subscription' &&
            transaction['status'] == 'active' &&
            transaction['is_active'] == true) {
          // If this is the first active subscription or more recent than current
          if (activeSubscription == null ||
              DateTime.parse(
                transaction['created_at'],
              ).isAfter(DateTime.parse(activeSubscription['created_at']))) {
            activeSubscription = transaction;
          }
        }
      }

      if (activeSubscription != null) {
        return {
          'active': true,
          'subscription_id': activeSubscription['subscription_id'],
          'product_id': activeSubscription['product_id'],
          'product_name': activeSubscription['product_name'],
          'status': activeSubscription['status'],
          'platform': activeSubscription['platform'],
          'expires_at': activeSubscription['expires_at'],
          'is_active': activeSubscription['is_active'],
        };
      }

      return {'active': false};
    } catch (e) {
      return {'active': false};
    }
  }

  /// Retry backend sync for users who failed to sync initially
  Future<bool> retryBackendSync() async {
    if (!isSignedIn) return false;

    try {
      await _syncUserWithBackend(currentUser!);

      // Check if sync was successful
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('user_synced_with_backend') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Check if user is synced with backend
  Future<bool> isUserSyncedWithBackend() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('user_synced_with_backend') ?? false;
  }

  /// Verify purchase
  Future<bool> verifyPurchase(
    String productId,
    String purchaseToken,
    String platform,
  ) async {
    if (!isSignedIn) return false;

    try {
      // Set auth token
      final idToken = await currentUser!.getIdToken();
      if (idToken != null) {
        _apiRepository.setAuthToken(idToken);
      }

      final response = await _apiRepository.verifyPurchase(
        userId: currentUser!.uid,
        productId: productId,
        transactionId: purchaseToken,
        receiptData: purchaseToken,
        platform: platform,
      );

      return response['success'] == true;
    } catch (e) {
      return false;
    }
  }

  /// Check if authentication is required for purchase
  static bool requiresAuthForPurchase() {
    return !isLoggedIn;
  }

  /// Reset password
  Future<void> resetPassword(String email) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email);
    } catch (e) {
      throw Exception('Failed to send password reset email: $e');
    }
  }

  /// Delete account
  Future<void> deleteAccount() async {
    try {
      final user = currentUser;

      if (user != null) {
        // Set auth token
        try {
          final idToken = await user.getIdToken();
          if (idToken != null) {
            _apiRepository.setAuthToken(idToken);
          }
        } catch (e) {
          debugPrint('⚠️ Could not get ID token: $e');
        }

        // Delete user data from backend - non-fatal if user not found (404)
        try {
          await _apiRepository.deleteUser(user.uid);
          debugPrint('✅ Backend user deleted');
        } catch (e) {
          // 404 means user not in DB - that is fine, continue with Firebase deletion
          debugPrint('⚠️ Backend delete failed (non-fatal, continuing): $e');
        }

        // Delete from Firebase (also signs out internally)
        try {
          await user.delete();
          debugPrint('✅ Firebase user deleted');
        } catch (e) {
          // If Firebase delete fails, force sign out anyway
          debugPrint('⚠️ Firebase delete failed, signing out: $e');
          await _firebaseAuth.signOut();
        }
      }

      // Always sign out from Google and clear all local data
      try {
        await _googleSignIn.signOut();
      } catch (_) {}
      try {
        await _firebaseAuth.signOut();
      } catch (_) {}

      final prefs = await SharedPreferences.getInstance();
      await prefs.clear();

      debugPrint('✅ Account deletion complete');
    } catch (e) {
      throw Exception('Failed to delete account: $e');
    }
  }

  /// Check if email is verified
  bool get isEmailVerified => currentUser?.emailVerified ?? false;

  /// Send email verification
  Future<void> sendEmailVerification() async {
    try {
      await currentUser?.sendEmailVerification();
    } catch (e) {
      throw Exception('Failed to send email verification: $e');
    }
  }

  /// Update user profile
  Future<void> updateProfile({String? displayName, String? photoURL}) async {
    try {
      if (currentUser != null) {
        await currentUser!.updateDisplayName(displayName);
        await currentUser!.updatePhotoURL(photoURL);
        await currentUser!.reload();

        // Sync updated data with backend
        await _syncUserWithBackend(currentUser!);
      }
    } catch (e) {
      throw Exception('Failed to update profile: $e');
    }
  }

  /// Get Firebase ID token for API authentication
  Future<String?> getIdToken() async {
    try {
      return await currentUser?.getIdToken();
    } catch (e) {
      return null;
    }
  }

  /// Cancel subscription
  Future<bool> cancelSubscription(int subscriptionId) async {
    if (!isSignedIn) return false;

    try {
      // Set auth token
      final idToken = await currentUser!.getIdToken();
      if (idToken != null) {
        _apiRepository.setAuthToken(idToken);
      }

      final result = await _apiRepository.cancelSubscriptionById(
        currentUser!.uid,
        subscriptionId,
      );

      return result['success'] == true;
    } catch (e) {
      return false;
    }
  }
}
