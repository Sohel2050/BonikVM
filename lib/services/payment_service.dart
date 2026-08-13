import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:http/http.dart' as http;
import '../core/config/app_config.dart';
import '../models/payment_models.dart';
import '../core/api_client.dart';

class PaymentService {
  static final PaymentService _instance = PaymentService._internal();
  factory PaymentService() => _instance;
  PaymentService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  final ApiClient _apiClient = ApiClient();
  final Uuid _uuid = const Uuid();

  // CRITICAL: Track processed purchases to prevent infinite loops
  final Set<String> _processedPurchases = <String>{};
  final Map<String, DateTime> _lastVerificationAttempt = <String, DateTime>{};
  final Map<String, int> _verificationRetryCount = <String, int>{};

  // Verification cooldown period (prevents spam)
  static const Duration verificationCooldown = Duration(seconds: 30);
  static const int maxRetries = 3;

  // Available subscription products - fetched from API dynamically
  List<String> _subscriptionIds = [];

  // Fetch product IDs from API (fully dynamic from admin panel)
  Future<void> _fetchProductIds() async {
    try {
      final response = await http.get(
        Uri.parse(
          '${AppConfig.baseUrl}/api/${AppConfig.apiVersion}/purchase/plans',
        ),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['data']?['plans'] != null) {
          _subscriptionIds = (data['data']['plans'] as List)
              .where((plan) => plan['enabled'] == true)
              .map((plan) {
                // Use platform-specific product ID
                if (Platform.isAndroid) {
                  return plan['android_product_id']?.toString() ??
                      plan['product_id']?.toString() ??
                      '';
                } else if (Platform.isIOS) {
                  return plan['ios_product_id']?.toString() ??
                      plan['product_id']?.toString() ??
                      '';
                }
                return plan['product_id']?.toString() ?? '';
              })
              .where((id) => id.isNotEmpty)
              .toList();
        }
      }
    } catch (e) {
      // Fallback to default if API fails
      _subscriptionIds = ['1m', '3m', '6m'];
    }
  }

  // Initialize payment service
  Future<bool> initialize() async {
    try {
      // Fetch product IDs from API first
      await _fetchProductIds();

      final bool isAvailable = await _inAppPurchase.isAvailable();
      if (!isAvailable) {
        return false;
      }

      // Set up purchase stream listener
      _inAppPurchase.purchaseStream.listen(_handlePurchaseUpdate);

      return true;
    } catch (e) {
      return false;
    }
  }

  // Get available products
  Future<List<ProductDetails>> getAvailableProducts() async {
    try {
      final ProductDetailsResponse response = await _inAppPurchase
          .queryProductDetails(_subscriptionIds.toSet());

      if (response.error != null) {
        throw Exception('Failed to load products: ${response.error!.message}');
      }

      return response.productDetails;
    } catch (e) {
      return [];
    }
  }

  // Purchase a subscription
  Future<PaymentResult> purchaseSubscription(ProductDetails product) async {
    try {
      final String transactionId = _uuid.v4();

      // Create purchase params
      final PurchaseParam purchaseParam = PurchaseParam(
        productDetails: product,
        applicationUserName: await _getUserId(),
      );

      // Store transaction locally first
      await _storeLocalTransaction(
        PaymentTransaction(
          id: transactionId,
          productId: product.id,
          amount: product.rawPrice.toDouble(),
          currency: product.currencyCode,
          status: PaymentStatus.pending,
          gateway: PaymentGateway.iap,
          createdAt: DateTime.now(),
          userId: await _getUserId(),
        ),
      );

      // Start purchase flow
      // For subscriptions on both iOS and Android, use buyNonConsumable
      // The recurring billing is handled by the store configuration, not the purchase method
      final bool success = await _inAppPurchase.buyNonConsumable(
        purchaseParam: purchaseParam,
      );

      if (success) {
        return PaymentResult(
          success: true,
          transactionId: transactionId,
          message: 'Purchase initiated successfully',
        );
      } else {
        await _updateLocalTransaction(transactionId, PaymentStatus.failed);
        return PaymentResult(
          success: false,
          error: 'Failed to initiate purchase',
        );
      }
    } catch (e) {
      return PaymentResult(success: false, error: 'Purchase failed: $e');
    }
  }

  // Process payment with Stripe (for web/testing)
  Future<PaymentResult> processStripePayment({
    required String productId,
    required double amount,
    required String currency,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final String transactionId = _uuid.v4();

      // Create test payment request
      final response = await _apiClient.post(
        '/api/payments/process',
        data: {
          'transaction_id': transactionId,
          'product_id': productId,
          'amount': amount,
          'currency': currency,
          'gateway': 'stripe',
          'payment_method': 'test_card',
          'user_id': await _getUserId(),
          'metadata': metadata ?? {},
          'test_mode': true,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;

        // Store transaction locally
        await _storeLocalTransaction(
          PaymentTransaction(
            id: transactionId,
            productId: productId,
            amount: amount,
            currency: currency,
            status: PaymentStatus.fromString(data['status']),
            gateway: PaymentGateway.stripe,
            gatewayTransactionId: data['gateway_transaction_id'],
            createdAt: DateTime.parse(data['created_at']),
            userId: await _getUserId(),
            metadata: data['metadata'],
          ),
        );

        return PaymentResult(
          success: true,
          transactionId: transactionId,
          gatewayTransactionId: data['gateway_transaction_id'],
          message: 'Payment processed successfully',
        );
      } else {
        throw Exception('Payment failed: ${response.data['message']}');
      }
    } catch (e) {
      return PaymentResult(success: false, error: 'Payment failed: $e');
    }
  }

  // Process payment with PayPal (for web/testing)
  Future<PaymentResult> processPayPalPayment({
    required String productId,
    required double amount,
    required String currency,
    Map<String, dynamic>? metadata,
  }) async {
    try {
      final String transactionId = _uuid.v4();

      final response = await _apiClient.post(
        '/api/payments/process',
        data: {
          'transaction_id': transactionId,
          'product_id': productId,
          'amount': amount,
          'currency': currency,
          'gateway': 'paypal',
          'payment_method': 'test_paypal',
          'user_id': await _getUserId(),
          'metadata': metadata ?? {},
          'test_mode': true,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;

        await _storeLocalTransaction(
          PaymentTransaction(
            id: transactionId,
            productId: productId,
            amount: amount,
            currency: currency,
            status: PaymentStatus.fromString(data['status']),
            gateway: PaymentGateway.paypal,
            gatewayTransactionId: data['gateway_transaction_id'],
            createdAt: DateTime.parse(data['created_at']),
            userId: await _getUserId(),
            metadata: data['metadata'],
          ),
        );

        return PaymentResult(
          success: true,
          transactionId: transactionId,
          gatewayTransactionId: data['gateway_transaction_id'],
          message: 'PayPal payment processed successfully',
        );
      } else {
        throw Exception('PayPal payment failed: ${response.data['message']}');
      }
    } catch (e) {
      return PaymentResult(success: false, error: 'PayPal payment failed: $e');
    }
  }

  // Handle purchase updates from store
  void _handlePurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (PurchaseDetails purchaseDetails in purchaseDetailsList) {
      // CRITICAL FIX: Only process each purchase once to prevent infinite loops
      final String purchaseKey =
          '${purchaseDetails.productID}_${purchaseDetails.purchaseID}';

      if (_processedPurchases.contains(purchaseKey)) {
        continue;
      }

      _processPurchaseUpdate(purchaseDetails);
    }
  }

  // Process individual purchase update
  Future<void> _processPurchaseUpdate(PurchaseDetails purchaseDetails) async {
    try {
      final String purchaseKey =
          '${purchaseDetails.productID}_${purchaseDetails.purchaseID}';

      // Mark as processed immediately to prevent re-processing
      _processedPurchases.add(purchaseKey);

      if (purchaseDetails.status == PurchaseStatus.purchased) {
        // Handle new purchase
        await _handlePurchasedStatus(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.restored) {
        // CRITICAL FIX: Handle restored purchases differently
        await _handleRestoredPurchase(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.error) {
        await _updateLocalTransactionByProductId(
          purchaseDetails.productID,
          PaymentStatus.failed,
        );
      } else if (purchaseDetails.status == PurchaseStatus.canceled) {
        await _handleCancelledPurchase(purchaseDetails);
      } else if (purchaseDetails.status == PurchaseStatus.pending) {
        // Don't verify pending purchases
      }
    } catch (e) {}
  }

  // Handle new purchase
  Future<void> _handlePurchasedStatus(PurchaseDetails purchaseDetails) async {
    try {
      // Save premium status immediately for better UX
      await _savePremiumStatus(true);

      // Verify with server with rate limiting
      await _verifyPurchaseWithRateLimit(purchaseDetails);

      // Update local transaction
      await _updateLocalTransactionByProductId(
        purchaseDetails.productID,
        PaymentStatus.completed,
        gatewayTransactionId: purchaseDetails.purchaseID,
      );

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    } catch (e) {}
  }

  // CRITICAL FIX: Handle restored purchases without spamming verification
  Future<void> _handleRestoredPurchase(PurchaseDetails purchaseDetails) async {
    try {
      // For restored purchases, only verify if we haven't recently
      final String purchaseKey =
          '${purchaseDetails.productID}_${purchaseDetails.purchaseID}';

      final DateTime? lastVerification = _lastVerificationAttempt[purchaseKey];
      if (lastVerification != null &&
          DateTime.now().difference(lastVerification) < verificationCooldown) {
        return;
      }

      // Save premium status immediately
      await _savePremiumStatus(true);

      // Only verify once for restored purchases

      // Check if user is authenticated before verification
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      // Verify with server (but with rate limiting)
      await _verifyPurchaseWithRateLimit(purchaseDetails);

      // Complete the purchase if needed
      if (purchaseDetails.pendingCompletePurchase) {
        await _inAppPurchase.completePurchase(purchaseDetails);
      }
    } catch (e) {}
  }

  // Handle cancelled purchase
  Future<void> _handleCancelledPurchase(PurchaseDetails purchaseDetails) async {
    try {
      // Update local transaction
      await _updateLocalTransactionByProductId(
        purchaseDetails.productID,
        PaymentStatus.cancelled,
      );

      // CRITICAL: Inform server about cancellation
      try {
        final user = FirebaseAuth.instance.currentUser;
        if (user != null) {
          await _apiClient.post(
            '/api/${AppConfig.apiVersion}/purchases/cancel',
            data: {
              'user_id': user.uid,
              'product_id': purchaseDetails.productID,
              'transaction_id': purchaseDetails.purchaseID,
              'platform': Platform.isIOS ? 'ios' : 'android',
              'cancellation_reason': 'User cancelled purchase',
            },
          );

          // Update premium status
          await _savePremiumStatus(false);
        }
      } catch (e) {}
    } catch (e) {}
  }

  // CRITICAL: Verify purchase with rate limiting to prevent infinite loops
  Future<void> _verifyPurchaseWithRateLimit(
    PurchaseDetails purchaseDetails,
  ) async {
    final String purchaseKey =
        '${purchaseDetails.productID}_${purchaseDetails.purchaseID}';

    // Check cooldown
    final DateTime? lastAttempt = _lastVerificationAttempt[purchaseKey];
    if (lastAttempt != null &&
        DateTime.now().difference(lastAttempt) < verificationCooldown) {
      return;
    }

    // Check retry limit
    final int retries = _verificationRetryCount[purchaseKey] ?? 0;
    if (retries >= maxRetries) {
      return;
    }

    try {
      _lastVerificationAttempt[purchaseKey] = DateTime.now();
      await _verifyPurchaseWithServer(purchaseDetails);

      // Reset retry count on success
      _verificationRetryCount.remove(purchaseKey);
    } catch (e) {
      // Increment retry count on failure
      _verificationRetryCount[purchaseKey] = retries + 1;

      rethrow;
    }
  }

  // Save premium status locally
  Future<void> _savePremiumStatus(bool isPremium) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_premium', isPremium);
    } catch (e) {}
  }

  // Get premium status
  Future<bool> getPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool('is_premium') ?? false;
    } catch (e) {
      return false;
    }
  }

  Future<void> _verifyPurchaseWithServer(
    PurchaseDetails purchaseDetails,
  ) async {
    try {
      // Get Firebase user for proper authentication
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('User not authenticated');
      }

      // Create unique transaction ID for new purchases
      String transactionId = purchaseDetails.purchaseID ?? '';

      // For test/debug mode, create deterministic transaction IDs
      if (transactionId.isEmpty || transactionId == 'fake_transaction_id') {
        transactionId = 'inapp_${DateTime.now().millisecondsSinceEpoch}';
      }

      // Use real receipt data from the store — never send fake data
      final receiptData =
          purchaseDetails.verificationData.serverVerificationData.isNotEmpty
          ? purchaseDetails.verificationData.serverVerificationData
          : purchaseDetails.verificationData.localVerificationData;

      final requestData = {
        'user_id': user.uid, // Use Firebase UID (string)
        'receipt_data': receiptData,
        'product_id': purchaseDetails.productID,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'transaction_id': transactionId,
        'firebase_uid': user.uid, // Also send as separate field
        'user_email': user.email, // Send email for verification
      };

      final response = await _apiClient.post(
        '/api/${AppConfig.apiVersion}/purchase/verify',
        data: requestData,
      );

      if (response.statusCode == 200) {
        final responseData = response.data;

        if (responseData['success'] == true) {
          await _savePremiumStatus(true);
        } else {
          throw Exception(responseData['message'] ?? 'Verification failed');
        }
      } else if (response.statusCode == 402) {
        // Payment required - subscription was cancelled

        await _savePremiumStatus(false);
        throw Exception('Subscription cancelled');
      } else {
        throw Exception(
          'Server verification failed with status: ${response.statusCode}',
        );
      }
    } catch (e) {
      rethrow;
    }
  }

  // Get user's transaction history
  Future<List<PaymentTransaction>> getTransactionHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? transactionsJson = prefs.getString('local_transactions');

      if (transactionsJson != null) {
        final List<dynamic> transactionsList = jsonDecode(transactionsJson);
        return transactionsList
            .map((json) => PaymentTransaction.fromJson(json))
            .toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  // Get user's receipts
  Future<List<PaymentReceipt>> getReceipts() async {
    try {
      final response = await _apiClient.get('/api/user/receipts');

      if (response.statusCode == 200) {
        final List<dynamic> receiptsData = response.data['receipts'];
        return receiptsData
            .map((json) => PaymentReceipt.fromJson(json))
            .toList();
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  // CRITICAL: Restore purchases with proper handling
  Future<void> restorePurchases() async {
    try {
      // Clear processed purchases to allow restoration
      _processedPurchases.clear();
      _lastVerificationAttempt.clear();
      _verificationRetryCount.clear();

      // Use the in-app purchase restore functionality
      await _inAppPurchase.restorePurchases();
    } catch (e) {}
  }

  // Check if user has any active subscriptions
  Future<bool> hasActiveSubscription() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return false;

      final response = await _apiClient.get(
        '/api/${AppConfig.apiVersion}/purchases/subscriptions/${user.uid}',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return data['has_active_subscription'] ?? false;
      }

      return false;
    } catch (e) {
      return await getPremiumStatus(); // Fallback to local status
    }
  }

  // Clear purchase processing cache (useful for testing)
  void clearProcessingCache() {
    _processedPurchases.clear();
    _lastVerificationAttempt.clear();
    _verificationRetryCount.clear();
  }

  // Generate receipt for transaction
  Future<PaymentReceipt?> generateReceipt(String transactionId) async {
    try {
      final response = await _apiClient.post(
        '/api/payments/generate-receipt',
        data: {'transaction_id': transactionId},
      );

      if (response.statusCode == 200) {
        return PaymentReceipt.fromJson(response.data);
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Create test transaction
  Future<PaymentResult> createTestTransaction({
    required String productId,
    required double amount,
    required String currency,
    required PaymentGateway gateway,
  }) async {
    try {
      final String transactionId = _uuid.v4();

      final response = await _apiClient.post(
        '/api/payments/create-test-transaction',
        data: {
          'transaction_id': transactionId,
          'product_id': productId,
          'amount': amount,
          'currency': currency,
          'gateway': gateway.toString().split('.').last,
          'user_id': await _getUserId(),
          'test_mode': true,
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;

        await _storeLocalTransaction(
          PaymentTransaction(
            id: transactionId,
            productId: productId,
            amount: amount,
            currency: currency,
            status: PaymentStatus.fromString(data['status']),
            gateway: gateway,
            gatewayTransactionId: data['gateway_transaction_id'],
            createdAt: DateTime.parse(data['created_at']),
            userId: await _getUserId(),
            isTest: true,
          ),
        );

        return PaymentResult(
          success: true,
          transactionId: transactionId,
          gatewayTransactionId: data['gateway_transaction_id'],
          message: 'Test transaction created successfully',
        );
      } else {
        throw Exception(
          'Failed to create test transaction: ${response.data['message']}',
        );
      }
    } catch (e) {
      return PaymentResult(
        success: false,
        error: 'Test transaction failed: $e',
      );
    }
  }

  // Helper methods
  Future<String> _getUserId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('user_id') ?? 'anonymous_${_uuid.v4()}';
  }

  Future<void> _storeLocalTransaction(PaymentTransaction transaction) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? transactionsJson = prefs.getString('local_transactions');

      List<dynamic> transactions = [];
      if (transactionsJson != null) {
        transactions = jsonDecode(transactionsJson);
      }

      transactions.add(transaction.toJson());
      await prefs.setString('local_transactions', jsonEncode(transactions));
    } catch (e) {}
  }

  Future<void> _updateLocalTransaction(
    String transactionId,
    PaymentStatus status, {
    String? gatewayTransactionId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? transactionsJson = prefs.getString('local_transactions');

      if (transactionsJson != null) {
        List<dynamic> transactions = jsonDecode(transactionsJson);

        for (int i = 0; i < transactions.length; i++) {
          if (transactions[i]['id'] == transactionId) {
            transactions[i]['status'] = status.toString().split('.').last;
            if (gatewayTransactionId != null) {
              transactions[i]['gateway_transaction_id'] = gatewayTransactionId;
            }
            break;
          }
        }

        await prefs.setString('local_transactions', jsonEncode(transactions));
      }
    } catch (e) {}
  }

  Future<void> _updateLocalTransactionByProductId(
    String productId,
    PaymentStatus status, {
    String? gatewayTransactionId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final String? transactionsJson = prefs.getString('local_transactions');

      if (transactionsJson != null) {
        List<dynamic> transactions = jsonDecode(transactionsJson);

        for (int i = 0; i < transactions.length; i++) {
          if (transactions[i]['product_id'] == productId &&
              transactions[i]['status'] == 'pending') {
            transactions[i]['status'] = status.toString().split('.').last;
            if (gatewayTransactionId != null) {
              transactions[i]['gateway_transaction_id'] = gatewayTransactionId;
            }
            break;
          }
        }

        await prefs.setString('local_transactions', jsonEncode(transactions));
      }
    } catch (e) {}
  }

  // Clean up
  void dispose() {
    // Dispose of streams and resources
  }
}
