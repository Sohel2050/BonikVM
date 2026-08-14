// lib/services/billing_service.dart
// Handles all payment methods: Stripe, PayPal, Crypto, IAP, Voucher.
// Uses ApiClient (Dio) which automatically injects the Bearer token.

import 'dart:io';
import 'package:dio/dio.dart';
import '../core/api_client.dart';

class BillingService {
  static final BillingService _instance = BillingService._internal();
  factory BillingService() => _instance;
  BillingService._internal();

  final ApiClient _api = ApiClient();

  static const String _base = '/api/v1';

  // ───────────────────────────────────────────────────────────────────────────
  // Subscription status & history
  // ───────────────────────────────────────────────────────────────────────────

  /// Returns current plan, expiry, source and full plan catalogue.
  Future<Map<String, dynamic>> getSubscriptionStatus() async {
    try {
      final response = await _api.get('$_base/subscription/status');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// Returns last 50 subscription records for the authenticated user.
  Future<Map<String, dynamic>> getReceipts() async {
    try {
      final response = await _api.get('$_base/subscription/receipts');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// Cancels all active subscriptions for the authenticated user.
  Future<Map<String, dynamic>> cancelSubscription() async {
    try {
      final response = await _api.post('$_base/subscription/cancel');
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Stripe
  // ───────────────────────────────────────────────────────────────────────────

  /// Creates a Stripe Checkout session and returns {checkout_url, session_id}.
  Future<Map<String, dynamic>> stripeCheckout({
    required String productId,
    required String successUrl,
    required String cancelUrl,
  }) async {
    try {
      final response = await _api.post(
        '$_base/billing/stripe/checkout',
        data: {
          'product_id': productId,
          'success_url': successUrl,
          'cancel_url': cancelUrl,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// Confirms a completed Stripe session (call from success_url handler).
  Future<Map<String, dynamic>> confirmStripeSession(String sessionId) async {
    try {
      final response = await _api.post(
        '$_base/billing/stripe/confirm',
        data: {'session_id': sessionId},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // PayPal
  // ───────────────────────────────────────────────────────────────────────────

  /// Creates a PayPal order and returns {order_id, approve_url}.
  Future<Map<String, dynamic>> createPaypalOrder({
    required String productId,
    required String returnUrl,
    required String cancelUrl,
  }) async {
    try {
      final response = await _api.post(
        '$_base/billing/paypal/order',
        data: {
          'product_id': productId,
          'return_url': returnUrl,
          'cancel_url': cancelUrl,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// Captures an approved PayPal order and activates the subscription.
  Future<Map<String, dynamic>> capturePaypalOrder(String orderId) async {
    try {
      final response = await _api.post(
        '$_base/billing/paypal/capture',
        data: {'order_id': orderId},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Crypto
  // ───────────────────────────────────────────────────────────────────────────

  /// Returns crypto wallet addresses (public – no auth required).
  Future<Map<String, dynamic>> getCryptoConfig() async {
    try {
      final response = await _api.get(
        '$_base/billing/crypto/config',
        // No auth needed, but ApiClient sends it anyway – harmless.
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  /// Submits a crypto payment for admin review.
  /// [proofImagePath] is optional – path to a local image file.
  Future<Map<String, dynamic>> submitCryptoPayment({
    required String productId,
    required String txHash,
    required String coin,
    String? proofImagePath,
  }) async {
    try {
      final formData = FormData.fromMap({
        'product_id': productId,
        'tx_hash': txHash,
        'coin': coin.toLowerCase(),
        if (proofImagePath != null && proofImagePath.isNotEmpty)
          'proof_image': await MultipartFile.fromFile(
            proofImagePath,
            filename: proofImagePath.split(Platform.pathSeparator).last,
          ),
      });

      final response = await _api.post(
        '$_base/billing/crypto/submit',
        data: formData,
        options: Options(contentType: 'multipart/form-data'),
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Payment methods (dynamic from admin)
  // ───────────────────────────────────────────────────────────────────────────

  /// Returns the list of payment methods enabled in the admin panel.
  /// Each entry has at least: id (String), name (String), enabled (bool).
  Future<List<String>> getEnabledPaymentMethodIds() async {
    try {
      final response = await _api.get('$_base/payment-methods');
      final data = response.data as Map<String, dynamic>;
      if (data['success'] == true) {
        final methods = data['payment_methods'] as List<dynamic>? ?? [];
        return methods
            .map((m) => (m['id'] as String? ?? '').toLowerCase())
            .where((id) => id.isNotEmpty)
            .toList();
      }
      return [];
    } catch (_) {
      return [];
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // In-App Purchase verification
  // ───────────────────────────────────────────────────────────────────────────

  /// Verifies a Google Play or App Store purchase with the backend.
  Future<Map<String, dynamic>> verifyIap({
    required String platform, // 'google_play' or 'app_store'
    required String productId, // Store product ID
    required String transactionId,
    required String receiptData,
    double? priceAmount,
    String? currencyCode,
  }) async {
    try {
      final response = await _api.post(
        '$_base/subscription/verify-iap',
        data: {
          'platform': platform,
          'product_id': productId,
          'transaction_id': transactionId,
          'receipt_data': receiptData,
          'amount_paid': priceAmount,
          'currency': currencyCode,
        },
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Voucher
  // ───────────────────────────────────────────────────────────────────────────

  /// Redeems a voucher code.
  Future<Map<String, dynamic>> redeemVoucher(String code) async {
    try {
      final response = await _api.post(
        '$_base/subscription/redeem-voucher',
        data: {'code': code},
      );
      return response.data as Map<String, dynamic>;
    } on DioException catch (e) {
      return _handleError(e);
    }
  }

  // ───────────────────────────────────────────────────────────────────────────
  // Error handling
  // ───────────────────────────────────────────────────────────────────────────

  Map<String, dynamic> _handleError(DioException e) {
    final responseData = e.response?.data;
    if (responseData is Map<String, dynamic>) {
      return responseData;
    }
    return {'success': false, 'message': e.message ?? 'Network error'};
  }
}
