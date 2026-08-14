import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/billing_service.dart';
import '../core/services/notification_service.dart';
import 'auth_providers.dart';

// Subscription State
class SubscriptionState {
  final bool isPremium;
  final Map<String, dynamic>? subscription;
  final List<Map<String, dynamic>> planCatalog;
  final bool isLoading;
  final String? errorMessage;
  final DateTime? lastChecked;

  const SubscriptionState({
    this.isPremium = false,
    this.subscription,
    this.planCatalog = const [],
    this.isLoading = false,
    this.errorMessage,
    this.lastChecked,
  });

  SubscriptionState copyWith({
    bool? isPremium,
    Map<String, dynamic>? subscription,
    List<Map<String, dynamic>>? planCatalog,
    bool? isLoading,
    String? errorMessage,
    DateTime? lastChecked,
  }) {
    return SubscriptionState(
      isPremium: isPremium ?? this.isPremium,
      subscription: subscription ?? this.subscription,
      planCatalog: planCatalog ?? this.planCatalog,
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage,
      lastChecked: lastChecked ?? this.lastChecked,
    );
  }

  String? get productId => subscription?['product_id'];
  DateTime? get expiresAt {
    final expiresStr = subscription?['expires_at'];
    if (expiresStr == null) return null;
    try {
      return DateTime.parse(expiresStr);
    } catch (e) {
      return null;
    }
  }

  DateTime? get startedAt {
    final startedStr = subscription?['started_at'];
    if (startedStr == null) return null;
    try {
      return DateTime.parse(startedStr);
    } catch (e) {
      return null;
    }
  }

  bool get isLifetime => subscription?['is_lifetime'] == true;
  String? get platform => subscription?['platform'];
  String get displayName {
    if (subscription == null) return 'No Active Subscription';
    final benefits = subscription!['benefits'] as Map<String, dynamic>?;
    return benefits?['name'] ?? 'Premium Subscription';
  }
}

// Subscription Provider
final subscriptionProvider =
    StateNotifierProvider<SubscriptionNotifier, SubscriptionState>((ref) {
      return SubscriptionNotifier(ref);
    });

class SubscriptionNotifier extends StateNotifier<SubscriptionState> {
  final Ref _ref;

  SubscriptionNotifier(this._ref) : super(const SubscriptionState()) {
    _init();
  }

  void _init() {
    // Load cached subscription immediately
    _loadCachedSubscription();

    // Check current auth state immediately
    final currentAuth = _ref.read(authStateProvider);
    if (currentAuth.status == AuthStatus.authenticated &&
        currentAuth.firebaseUser != null) {
      // User is already logged in on app start - check subscription
      checkSubscriptionStatus(currentAuth.firebaseUser!.uid);
    }

    // Listen to auth state changes
    _ref.listen(authStateProvider, (previous, next) {
      if (next.status == AuthStatus.authenticated &&
          next.firebaseUser != null) {
        // User just logged in - check subscription
        checkSubscriptionStatus(next.firebaseUser!.uid);
      } else if (next.status == AuthStatus.unauthenticated) {
        // User logged out - clear subscription
        _clearSubscription();
      }
    });

    // Refresh subscription when a crypto approval/rejection push arrives.
    NotificationService().subscriptionEventStream.listen((event) {
      final currentAuth = _ref.read(authStateProvider);
      if (currentAuth.status == AuthStatus.authenticated &&
          currentAuth.firebaseUser != null) {
        checkSubscriptionStatus(currentAuth.firebaseUser!.uid);
      }
    });
  }

  /// Load cached subscription from local storage
  Future<void> _loadCachedSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final cachedData = prefs.getString('subscription_data');
      final cachedTime = prefs.getString('subscription_checked_at');

      if (cachedData != null) {
        final data = json.decode(cachedData) as Map<String, dynamic>;
        final checkedAt = cachedTime != null
            ? DateTime.parse(cachedTime)
            : null;

        // Only use cache if it's less than 5 minutes old
        if (checkedAt != null &&
            DateTime.now().difference(checkedAt).inMinutes < 5) {
          final rawCatalog = data['plan_catalog'] as List? ?? [];
          state = state.copyWith(
            isPremium: data['is_premium'] == true,
            subscription: data['subscription'] as Map<String, dynamic>?,
            planCatalog: rawCatalog
                .whereType<Map>()
                .map((e) => Map<String, dynamic>.from(e))
                .toList(),
            lastChecked: checkedAt,
          );
        }
      }
    } catch (e) {
    }
  }

  /// Save subscription to cache
  Future<void> _cacheSubscription() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        'subscription_data',
        json.encode({
          'is_premium': state.isPremium,
          'subscription': state.subscription,
          'plan_catalog': state.planCatalog,
        }),
      );
      await prefs.setString(
        'subscription_checked_at',
        DateTime.now().toIso8601String(),
      );

      // Also update is_premium flag for AdMobService compatibility
      await prefs.setBool('is_premium', state.isPremium);
    } catch (e) {
    }
  }

  /// Clear subscription cache
  Future<void> _clearSubscription() async {
    state = const SubscriptionState();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('subscription_data');
    await prefs.remove('subscription_checked_at');
    await prefs.setBool('is_premium', false);
  }

  /// Check subscription status from API
  Future<void> checkSubscriptionStatus(
    String userId, {
    bool forceRefresh = false,
  }) async {
    // Don't check if already loading
    if (state.isLoading) return;

    // Skip if checked recently and not forcing refresh
    if (!forceRefresh && state.lastChecked != null) {
      final timeSinceCheck = DateTime.now().difference(state.lastChecked!);
      if (timeSinceCheck.inMinutes < 2) {
        return;
      }
    }

    state = state.copyWith(isLoading: true, errorMessage: null);

    try {
      final response = await BillingService().getSubscriptionStatus();

      if (response['success'] == true && response['data'] != null) {
        final data = response['data'] as Map<String, dynamic>;
        final isPremium = data['is_premium'] == true;
        final subscription = data['subscription'] as Map<String, dynamic>?;
        final rawCatalog = data['plan_catalog'] as List? ?? [];
        final planCatalog = rawCatalog
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();

        state = SubscriptionState(
          isPremium: isPremium,
          subscription: subscription,
          planCatalog: planCatalog,
          isLoading: false,
          errorMessage: null,
          lastChecked: DateTime.now(),
        );

        // Cache the result
        await _cacheSubscription();

        if (subscription != null) {
        }
      } else {
        state = state.copyWith(
          isLoading: false,
          isPremium: false,
          subscription: null,
          errorMessage: response['message'] ?? 'Failed to check subscription',
        );
      }
    } catch (e) {
      state = state.copyWith(isLoading: false, errorMessage: e.toString());
    }
  }

  /// Manually activate subscription (call after successful payment)
  Future<void> activateSubscription(
    String userId,
    Map<String, dynamic> subscriptionData,
  ) async {

    state = SubscriptionState(
      isPremium: true,
      subscription: subscriptionData,
      isLoading: false,
      errorMessage: null,
      lastChecked: DateTime.now(),
    );

    await _cacheSubscription();

    // Also refresh from API to ensure consistency
    Future.delayed(const Duration(seconds: 2), () {
      checkSubscriptionStatus(userId, forceRefresh: true);
    });
  }

  /// Force refresh subscription status
  Future<void> refresh() async {
    final authState = _ref.read(authStateProvider);
    if (authState.firebaseUser != null) {
      await checkSubscriptionStatus(
        authState.firebaseUser!.uid,
        forceRefresh: true,
      );
    }
  }
}
