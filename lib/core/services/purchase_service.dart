import 'dart:async';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';

class PurchaseService {
  static final PurchaseService _instance = PurchaseService._internal();
  factory PurchaseService() => _instance;
  PurchaseService._internal();

  final InAppPurchase _inAppPurchase = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;

  // Premium status
  static const String _premiumKey = 'is_premium_user';
  bool _isPremium = false;
  bool get isPremium => _isPremium;

  // Product IDs are now fetched dynamically from API endpoint:
  // GET /api/v1/purchase/plans
  // Configured through admin panel: /admin/purchases/config/products
  // NO HARDCODED PRODUCT IDs - all managed via database

  Set<String> _productIds = {}; // Populated from API
  Set<String> get productIds => _productIds;

  /// Update product IDs dynamically (loaded from API) and await the reload.
  Future<void> updateProductIds(Set<String> newProductIds) async {
    _productIds = newProductIds;
    // Reload products with new IDs
    if (_productIds.isNotEmpty) {
      await _loadProducts();
    }
  }

  /// Ensure a specific product ID is loaded and ready to purchase.
  /// Merges [productId] into the current set and reloads if not already loaded.
  Future<void> ensureProductLoaded(String productId) async {
    if (!_products.any((p) => p.id == productId)) {
      _productIds = {..._productIds, productId};
      await _loadProducts();
    }
  }

  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;

  final StreamController<bool> _premiumStatusController =
      StreamController<bool>.broadcast();
  Stream<bool> get premiumStatusStream => _premiumStatusController.stream;

  final StreamController<PurchaseResult> _purchaseResultController =
      StreamController<PurchaseResult>.broadcast();
  Stream<PurchaseResult> get purchaseResultStream =>
      _purchaseResultController.stream;

  /// Initialize the purchase service
  Future<void> initialize() async {
    try {
      // Check if in-app purchases are available
      final bool isAvailable = await _inAppPurchase.isAvailable();
      if (!isAvailable) {
        return;
      }

      // CRITICAL FIX: Start with premium status cleared to prevent auto-activation
      // Only activate after genuine verification
      await _savePremiumStatus(false);

      // Listen to purchase updates
      _subscription = _inAppPurchase.purchaseStream.listen(
        _onPurchaseUpdate,
        onError: (error) {
          _purchaseResultController.add(
            PurchaseResult.error('Purchase stream error: $error'),
          );
        },
      );

      // Load products
      await _loadProducts();

      // Check for pending purchases on startup
      await _checkPendingPurchases();
    } catch (e) {}
  }

  /// Load products from the store
  Future<void> _loadProducts() async {
    try {
      final ProductDetailsResponse response = await _inAppPurchase
          .queryProductDetails(_productIds);

      if (response.error != null) {
        return;
      }

      _products = response.productDetails;
    } catch (e) {}
  }

  /// Load premium status from local storage
  Future<void> _loadPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _isPremium = prefs.getBool(_premiumKey) ?? false;
      _premiumStatusController.add(_isPremium);
    } catch (e) {}
  }

  /// Save premium status to local storage
  Future<void> _savePremiumStatus(bool isPremium) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_premiumKey, isPremium);
      _isPremium = isPremium;
      _premiumStatusController.add(_isPremium);
    } catch (e) {}
  }

  /// Purchase a product
  Future<void> purchaseProduct(String productId) async {
    try {
      final ProductDetails? productDetails = _products
          .cast<ProductDetails?>()
          .firstWhere(
            (product) => product?.id == productId,
            orElse: () => null,
          );

      if (productDetails == null) {
        final errorMsg =
            'Product not found: $productId. Available: ${_products.map((p) => p.id).join(', ')}';

        // Try to reload products in case they weren't loaded properly

        await _loadProducts();

        // Try again after reload
        final ProductDetails? retryProductDetails = _products
            .cast<ProductDetails?>()
            .firstWhere(
              (product) => product?.id == productId,
              orElse: () => null,
            );

        if (retryProductDetails == null) {
          throw Exception(errorMsg);
        } else {
          // Continue with the found product
          await _initiatePurchase(retryProductDetails, productId);
          return;
        }
      }

      await _initiatePurchase(productDetails, productId);
    } catch (e) {
      _purchaseResultController.add(
        PurchaseResult.error('Purchase failed: $e'),
      );
    }
  }

  /// Helper method to initiate purchase
  Future<void> _initiatePurchase(
    ProductDetails productDetails,
    String productId,
  ) async {
    final PurchaseParam purchaseParam = PurchaseParam(
      productDetails: productDetails,
    );

    // IMPORTANT: For recurring subscriptions (monthly, yearly, weekly):
    // 1. Products MUST be configured as SUBSCRIPTIONS in Google Play Console and App Store Connect
    // 2. Use buyNonConsumable() for both iOS and Android subscriptions
    // 3. Recurring billing is controlled by the store configuration, NOT the purchase method
    // 4. Make sure to set up subscription details (billing period, trial period, etc.) in the store console
    // 5. Enable "Restore Purchases" functionality for users who reinstall the app
    await _inAppPurchase.buyNonConsumable(purchaseParam: purchaseParam);
  }

  /// Handle purchase updates
  void _onPurchaseUpdate(List<PurchaseDetails> purchaseDetailsList) {
    for (final PurchaseDetails purchaseDetails in purchaseDetailsList) {
      switch (purchaseDetails.status) {
        case PurchaseStatus.pending:
          _purchaseResultController.add(PurchaseResult.pending());
          break;

        case PurchaseStatus.purchased:
          // Only handle genuine new purchases
          _handleSuccessfulPurchase(purchaseDetails);
          break;

        case PurchaseStatus.restored:
          // Emit restored event with real receipt data so the UI layer can
          // verify with our backend whether the subscription is still active.
          // This properly handles cancelled subscriptions reported by Play Store.
          final restoredReceipt =
              purchaseDetails.verificationData.serverVerificationData.isNotEmpty
              ? purchaseDetails.verificationData.serverVerificationData
              : purchaseDetails.verificationData.localVerificationData;
          _purchaseResultController.add(
            PurchaseResult.restored(
              purchaseDetails.productID,
              receiptData: restoredReceipt,
              transactionId: purchaseDetails.purchaseID,
            ),
          );
          break;

        case PurchaseStatus.error:
          _purchaseResultController.add(
            PurchaseResult.error(
              purchaseDetails.error?.message ?? 'Purchase failed',
            ),
          );
          break;

        case PurchaseStatus.canceled:
          _purchaseResultController.add(PurchaseResult.cancelled());
          break;
      }

      // Complete the purchase
      if (purchaseDetails.pendingCompletePurchase) {
        _inAppPurchase.completePurchase(purchaseDetails);
      }
    }
  }

  /// Handle successful purchase
  void _handleSuccessfulPurchase(PurchaseDetails purchaseDetails) async {
    try {
      // Verify the purchase (in production, you should verify with your backend)
      if (await _verifyPurchase(purchaseDetails)) {
        await _savePremiumStatus(true);
        // Pass real receipt data so the screen can verify with backend properly
        final receiptData =
            purchaseDetails.verificationData.serverVerificationData.isNotEmpty
            ? purchaseDetails.verificationData.serverVerificationData
            : purchaseDetails.verificationData.localVerificationData;
        _purchaseResultController.add(
          PurchaseResult.success(
            purchaseDetails.productID,
            receiptData: receiptData,
            transactionId: purchaseDetails.purchaseID,
          ),
        );
      } else {
        _purchaseResultController.add(
          PurchaseResult.error('Purchase verification failed'),
        );
      }
    } catch (e) {
      _purchaseResultController.add(
        PurchaseResult.error('Error processing purchase: $e'),
      );
    }
  }

  /// Verify purchase (implement your own verification logic)
  Future<bool> _verifyPurchase(PurchaseDetails purchaseDetails) async {
    try {
      // Don't auto-verify restored purchases
      if (purchaseDetails.status == PurchaseStatus.restored) {
        return false;
      }

      // Only verify genuinely purchased items
      if (purchaseDetails.status != PurchaseStatus.purchased) {
        return false;
      }

      // Accept purchase — backend will do the real validation
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Restore purchases — triggers purchaseResultStream with
  /// PurchaseResult.restored() events that the UI must verify with backend.
  Future<void> restorePurchases() async {
    try {
      final bool available = await _inAppPurchase.isAvailable();
      if (!available) {
        _purchaseResultController.add(
          PurchaseResult.error('Store not available'),
        );
        return;
      }
      await _inAppPurchase.restorePurchases();
    } catch (e) {
      _purchaseResultController.add(
        PurchaseResult.error('Failed to restore purchases: $e'),
      );
    }
  }

  /// Check for pending purchases on app startup
  Future<void> _checkPendingPurchases() async {
    try {
      // This will trigger the purchase stream for any pending purchases
      await _inAppPurchase.restorePurchases();
    } catch (e) {}
  }

  /// Get product details by ID
  ProductDetails? getProductDetails(String productId) {
    try {
      return _products.firstWhere((product) => product.id == productId);
    } catch (e) {
      return null;
    }
  }

  /// Get real price from store for a product
  String? getRealPrice(String productId) {
    final product = getProductDetails(productId);
    return product?.price;
  }

  /// Get all available products with their real prices
  Map<String, String> getAllRealPrices() {
    Map<String, String> prices = {};
    for (final product in _products) {
      prices[product.id] = product.price;
    }
    return prices;
  }

  /// Debug method to check available products
  void debugAvailableProducts() {
    // Debug products
  }

  /// Manually set premium status (for testing or admin override)
  Future<void> setPremiumStatus(bool isPremium) async {
    await _savePremiumStatus(isPremium);
  }

  /// Check if user has active premium subscription
  Future<bool> checkPremiumStatus() async {
    try {
      // In production, you might want to validate with the store
      // For now, return the locally stored status
      await _loadPremiumStatus();
      return _isPremium;
    } catch (e) {
      return false;
    }
  }

  /// Dispose the service
  void dispose() {
    _subscription?.cancel();
    _premiumStatusController.close();
    _purchaseResultController.close();
  }

  /// Verify subscription with backend server (simplified)
  Future<bool> verifySubscriptionWithServer() async {
    try {
      // For now, just check local purchase status
      // TODO: Implement proper server verification
      final localPremium = await checkPremiumStatus();

      if (localPremium) {
        await activateSubscriptionBenefits();
        return true;
      }

      return false;
    } catch (e) {
      return false;
    }
  }

  /// Check and sync subscription status on app start
  Future<void> syncSubscriptionStatus() async {
    try {
      // First check local status
      final localPremium = await checkPremiumStatus();

      // If already premium locally, verify with server
      if (localPremium) {
        final serverVerified = await verifySubscriptionWithServer();
        if (!serverVerified) {
          // Server verification failed, reset local premium status
          await setPremiumStatus(false);
        }
      } else {
        // Not premium locally, check for any valid purchases
        await verifySubscriptionWithServer();
      }
    } catch (e) {}
  }

  /// Handle subscription benefits activation
  Future<void> activateSubscriptionBenefits() async {
    try {
      if (_isPremium) {
        // Disable ads
        // AdService.instance?.disableAds();

        // Enable premium features
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('premium_features_enabled', true);
        await prefs.setBool('ads_disabled', true);
        await prefs.setString(
          'premium_activated_at',
          DateTime.now().toIso8601String(),
        );
      } else {
        // Re-enable ads
        // AdService.instance?.enableAds();

        // Disable premium features
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool('premium_features_enabled', false);
        await prefs.setBool('ads_disabled', false);
        await prefs.remove('premium_activated_at');
      }
    } catch (e) {}
  }

  /// Clear premium status (call on sign out)
  Future<void> clearPremiumStatus() async {
    try {
      await _savePremiumStatus(false);
    } catch (e) {}
  }

  /// Reset purchase service state (call on sign out)
  Future<void> resetPurchaseState() async {
    try {
      await clearPremiumStatus();
    } catch (e) {}
  }

  /// Force refresh subscription status (manual check)
  Future<void> forceRefreshSubscriptionStatus() async {
    try {
      // Clear local status first
      await _savePremiumStatus(false);

      // Verify with server (if user is authenticated)
      await verifySubscriptionWithServer();
    } catch (e) {}
  }
}

/// Purchase result class
class PurchaseResult {
  final PurchaseStatus status;
  final String? productId;
  final String? errorMessage;
  final String? receiptData; // Real Google Play / App Store receipt token
  final String? transactionId; // Store transaction ID

  PurchaseResult._({
    required this.status,
    this.productId,
    this.errorMessage,
    this.receiptData,
    this.transactionId,
  });

  factory PurchaseResult.success(
    String productId, {
    String? receiptData,
    String? transactionId,
  }) => PurchaseResult._(
    status: PurchaseStatus.purchased,
    productId: productId,
    receiptData: receiptData,
    transactionId: transactionId,
  );

  factory PurchaseResult.pending() =>
      PurchaseResult._(status: PurchaseStatus.pending);

  factory PurchaseResult.cancelled() =>
      PurchaseResult._(status: PurchaseStatus.canceled);

  factory PurchaseResult.error(String message) =>
      PurchaseResult._(status: PurchaseStatus.error, errorMessage: message);

  factory PurchaseResult.restored(
    String productId, {
    String? receiptData,
    String? transactionId,
  }) => PurchaseResult._(
    status: PurchaseStatus.restored,
    productId: productId,
    receiptData: receiptData,
    transactionId: transactionId,
  );

  bool get isSuccess => status == PurchaseStatus.purchased;
  bool get isPending => status == PurchaseStatus.pending;
  bool get isCancelled => status == PurchaseStatus.canceled;
  bool get isError => status == PurchaseStatus.error;
  bool get isRestored => status == PurchaseStatus.restored;
}
