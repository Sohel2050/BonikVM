// lib/services/subscription_service.dart
// Subscription management service for VPN MASTER Flutter app
// Handles subscription status, purchase history, and synchronization

import 'dart:async';
import 'package:flutter/foundation.dart';
import '../core/api_client.dart';

enum SubscriptionStatus { active, cancelled, expired, pending, trial }
enum SubscriptionPlatform { android, ios, web }
enum PaymentGateway { googlePlay, appStore, stripe, paypal }

class Subscription {
  final String id;
  final String productId;
  final SubscriptionPlatform platform;
  final PaymentGateway? paymentGateway;
  final String? transactionId;
  final String? orderId;
  final SubscriptionStatus status;
  final bool isActive;
  final DateTime? startedAt;
  final DateTime? expiresAt;
  final DateTime? cancelledAt;
  final String? cancelReason;
  final double? amount;
  final String? currency;
  final String type;
  final bool? autoRenewing;
  final int? daysRemaining;
  final bool isTrial;
  final String? countryCode;
  final bool canCancel;

  Subscription({
    required this.id,
    required this.productId,
    required this.platform,
    this.paymentGateway,
    this.transactionId,
    this.orderId,
    required this.status,
    required this.isActive,
    this.startedAt,
    this.expiresAt,
    this.cancelledAt,
    this.cancelReason,
    this.amount,
    this.currency,
    required this.type,
    this.autoRenewing,
    this.daysRemaining,
    required this.isTrial,
    this.countryCode,
    required this.canCancel,
  });

  factory Subscription.fromJson(Map<String, dynamic> json) {
    return Subscription(
      id: json['id'].toString(),
      productId: json['product_id'] ?? '',
      platform: _parsePlatform(json['platform']),
      paymentGateway: _parsePaymentGateway(json['payment_gateway']),
      transactionId: json['transaction_id'],
      orderId: json['order_id'],
      status: _parseStatus(json['status']),
      isActive: json['is_active'] ?? false,
      startedAt: json['started_at'] != null ? DateTime.parse(json['started_at']) : null,
      expiresAt: json['expires_at'] != null ? DateTime.parse(json['expires_at']) : null,
      cancelledAt: json['cancelled_at'] != null ? DateTime.parse(json['cancelled_at']) : null,
      cancelReason: json['cancel_reason'],
      amount: json['amount'] != null ? double.parse(json['amount'].toString()) : null,
      currency: json['currency'],
      type: json['type'] ?? 'yearly',
      autoRenewing: json['auto_renewing'],
      daysRemaining: json['days_remaining'],
      isTrial: json['is_trial'] ?? false,
      countryCode: json['country_code'],
      canCancel: json['can_cancel'] ?? false,
    );
  }

  static SubscriptionPlatform _parsePlatform(String? platform) {
    switch (platform?.toLowerCase()) {
      case 'android': return SubscriptionPlatform.android;
      case 'ios': return SubscriptionPlatform.ios;
      case 'web': return SubscriptionPlatform.web;
      default: return SubscriptionPlatform.android;
    }
  }

  static PaymentGateway? _parsePaymentGateway(String? gateway) {
    switch (gateway?.toLowerCase()) {
      case 'google_play': return PaymentGateway.googlePlay;
      case 'app_store': return PaymentGateway.appStore;
      case 'stripe': return PaymentGateway.stripe;
      case 'paypal': return PaymentGateway.paypal;
      default: return null;
    }
  }

  static SubscriptionStatus _parseStatus(String? status) {
    switch (status?.toLowerCase()) {
      case 'active': return SubscriptionStatus.active;
      case 'cancelled': return SubscriptionStatus.cancelled;
      case 'expired': return SubscriptionStatus.expired;
      case 'pending': return SubscriptionStatus.pending;
      case 'free trial': return SubscriptionStatus.trial;
      default: return SubscriptionStatus.expired;
    }
  }

  String get statusText {
    switch (status) {
      case SubscriptionStatus.active: return isTrial ? 'Free Trial' : 'Active';
      case SubscriptionStatus.cancelled: return 'Cancelled';
      case SubscriptionStatus.expired: return 'Expired';
      case SubscriptionStatus.pending: return 'Pending';
      case SubscriptionStatus.trial: return 'Free Trial';
    }
  }

  String get platformText {
    switch (platform) {
      case SubscriptionPlatform.android: return 'Google Play';
      case SubscriptionPlatform.ios: return 'App Store';
      case SubscriptionPlatform.web: return 'Web';
    }
  }

  String get gatewayText {
    switch (paymentGateway) {
      case PaymentGateway.googlePlay: return 'Google Play';
      case PaymentGateway.appStore: return 'App Store';
      case PaymentGateway.stripe: return 'Stripe';
      case PaymentGateway.paypal: return 'PayPal';
      case null: return 'Unknown';
    }
  }
}

class PaymentTransaction {
  final String id;
  final String gateway;
  final String? gatewayTransactionId;
  final double amount;
  final String currency;
  final String status;
  final String type;
  final DateTime createdAt;
  final Map<String, dynamic>? metadata;

  PaymentTransaction({
    required this.id,
    required this.gateway,
    this.gatewayTransactionId,
    required this.amount,
    required this.currency,
    required this.status,
    required this.type,
    required this.createdAt,
    this.metadata,
  });

  factory PaymentTransaction.fromJson(Map<String, dynamic> json) {
    return PaymentTransaction(
      id: json['id'].toString(),
      gateway: json['gateway'] ?? '',
      gatewayTransactionId: json['gateway_transaction_id'],
      amount: double.parse(json['amount'].toString()),
      currency: json['currency'] ?? 'USD',
      status: json['status'] ?? '',
      type: json['type'] ?? '',
      createdAt: DateTime.parse(json['created_at']),
      metadata: json['metadata'],
    );
  }
}

class PurchaseHistorySummary {
  final int totalSubscriptions;
  final int activeSubscriptions;
  final double totalSpent;
  final List<String> platformsUsed;
  final List<String> gatewaysUsed;

  PurchaseHistorySummary({
    required this.totalSubscriptions,
    required this.activeSubscriptions,
    required this.totalSpent,
    required this.platformsUsed,
    required this.gatewaysUsed,
  });

  factory PurchaseHistorySummary.fromJson(Map<String, dynamic> json) {
    return PurchaseHistorySummary(
      totalSubscriptions: json['total_subscriptions'] ?? 0,
      activeSubscriptions: json['active_subscriptions'] ?? 0,
      totalSpent: double.parse(json['total_spent']?.toString() ?? '0'),
      platformsUsed: List<String>.from(json['platforms_used'] ?? []),
      gatewaysUsed: List<String>.from(json['gateways_used'] ?? []),
    );
  }
}

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final ApiClient _apiClient = ApiClient();
  
  // Cache for subscription status
  Subscription? _activeSubscription;
  List<Subscription> _allSubscriptions = [];
  DateTime? _lastSyncTime;

  /// Sync subscription status with backend
  Future<Map<String, dynamic>> syncSubscriptionStatus(String userId) async {
    try {
      await _apiClient.initialize();
      
      final response = await _apiClient.post(
        '/v1/purchases/sync-status',
        data: {'user_id': userId},
      );

      if (response.data['success']) {
        final data = response.data['data'];
        
        // Update cached data
        _activeSubscription = data['active_subscription'] != null
            ? Subscription.fromJson(data['active_subscription'])
            : null;
            
        _allSubscriptions = (data['all_subscriptions'] as List)
            .map((sub) => Subscription.fromJson(sub))
            .toList();
            
        _lastSyncTime = DateTime.now();

        if (kDebugMode) {}

        return {
          'success': true,
          'hasActiveSubscription': data['has_active_subscription'],
          'activeSubscription': _activeSubscription,
          'syncResults': data['sync_results'],
        };
      } else {
        return {'success': false, 'error': response.data['message']};
      }
    } catch (e) {
      if (kDebugMode) {}
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get purchase history
  Future<Map<String, dynamic>> getPurchaseHistory(
    String userId, {
    String? platform,
    String? status,
    int limit = 20,
  }) async {
    try {
      await _apiClient.initialize();
      
      final queryParams = <String, dynamic>{
        'user_id': userId,
        'limit': limit,
      };
      
      if (platform != null) queryParams['platform'] = platform;
      if (status != null) queryParams['status'] = status;

      final response = await _apiClient.get(
        '/v1/purchases/history',
        queryParameters: queryParams,
      );

      if (response.data['success']) {
        final data = response.data['data'];
        
        final subscriptions = (data['subscriptions'] as List)
            .map((sub) => Subscription.fromJson(sub))
            .toList();
            
        final transactions = (data['transactions'] as List)
            .map((trans) => PaymentTransaction.fromJson(trans))
            .toList();
            
        final summary = PurchaseHistorySummary.fromJson(data['summary']);

        return {
          'success': true,
          'subscriptions': subscriptions,
          'transactions': transactions,
          'summary': summary,
        };
      } else {
        return {'success': false, 'error': response.data['message']};
      }
    } catch (e) {
      if (kDebugMode) {}
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Force sync with Google Play Store
  Future<Map<String, dynamic>> forceSyncGooglePlay(
    String userId,
    String productId,
    String purchaseToken,
  ) async {
    try {
      await _apiClient.initialize();
      
      final response = await _apiClient.post(
        '/v1/purchases/force-sync-google-play',
        data: {
          'user_id': userId,
          'product_id': productId,
          'purchase_token': purchaseToken,
        },
      );

      if (response.data['success']) {
        // Update cached active subscription
        final subscriptionData = response.data['data']['subscription'];
        if (subscriptionData['is_active']) {
          _activeSubscription = Subscription.fromJson(subscriptionData);
        }

        return {
          'success': true,
          'subscription': Subscription.fromJson(subscriptionData),
          'verificationResult': response.data['data']['verification_result'],
        };
      } else {
        return {'success': false, 'error': response.data['message']};
      }
    } catch (e) {
      if (kDebugMode) {}
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get current active subscription (cached)
  Subscription? get activeSubscription => _activeSubscription;

  /// Get all subscriptions (cached)
  List<Subscription> get allSubscriptions => _allSubscriptions;

  /// Check if user has active subscription
  bool get hasActiveSubscription => _activeSubscription != null && _activeSubscription!.isActive;

  /// Get last sync time
  DateTime? get lastSyncTime => _lastSyncTime;

  /// Check if sync is needed (older than 5 minutes)
  bool get needsSync {
    if (_lastSyncTime == null) return true;
    return DateTime.now().difference(_lastSyncTime!).inMinutes > 5;
  }

  /// Clear cached data
  void clearCache() {
    _activeSubscription = null;
    _allSubscriptions.clear();
    _lastSyncTime = null;
  }

  /// Auto-sync subscription status if needed
  Future<void> autoSyncIfNeeded(String userId) async {
    if (needsSync) {
      await syncSubscriptionStatus(userId);
    }
  }
}

