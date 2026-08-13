import 'package:vpn_master/core/api/api_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_stripe/flutter_stripe.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../shared/providers/theme_provider.dart';
import '../../providers/auth_providers.dart';
import '../../providers/subscription_provider.dart';
import '../../core/services/purchase_service.dart';
import '../../widgets/stripe_card_input_sheet.dart';
import 'receipt_screen.dart';
import 'paypal_webview_screen.dart';

class PaymentOptionsScreen extends ConsumerStatefulWidget {
  final String planId;
  final String planName;
  final String planPrice;
  final Map<String, dynamic> planDetails;

  const PaymentOptionsScreen({
    Key? key,
    required this.planId,
    required this.planName,
    required this.planPrice,
    required this.planDetails,
  }) : super(key: key);

  @override
  ConsumerState<PaymentOptionsScreen> createState() =>
      _PaymentOptionsScreenState();
}

class _PaymentOptionsScreenState extends ConsumerState<PaymentOptionsScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  bool _isProcessing = false;
  String _selectedPaymentMethod = '';
  List<Map<String, dynamic>> _availablePaymentMethods = [];
  bool _isLoadingPaymentMethods = true;

  final PurchaseService _purchaseService = PurchaseService();
  final ApiService _apiService = ApiService();

  @override
  void initState() {
    super.initState();
    _setupAnimations();
    _loadAvailablePaymentMethods();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  Future<void> _loadAvailablePaymentMethods() async {
    try {
      setState(() {
        _isLoadingPaymentMethods = true;
      });

      final result = await _apiService.getAvailablePaymentMethods();

      if (result['success'] && mounted) {
        List<Map<String, dynamic>> methods = List<Map<String, dynamic>>.from(
          result['payment_methods'] ?? [],
        );

        // Platform-based payment method filtering:
        // - Web/Desktop: IAP not supported, remove it
        // - iOS: Apple policy requires IAP only — remove all other methods
        // - Android: all methods allowed
        if (!Platform.isAndroid && !Platform.isIOS) {
          methods = methods
              .where((method) => method['id'] != 'in_app_purchase')
              .toList();
        } else if (Platform.isIOS) {
          // Apple policy: only in-app purchases allowed on iOS
          methods = methods
              .where((method) => method['id'] == 'in_app_purchase')
              .toList();
        }

        // Update IAP product IDs if IAP is available
        if (Platform.isAndroid || Platform.isIOS) {
          final iapMethod = methods.firstWhere(
            (method) => method['id'] == 'in_app_purchase',
            orElse: () => <String, dynamic>{},
          );
          if (iapMethod.isNotEmpty) {
            // Load pricing plans to get product IDs for IAP
            final plansResult = await _apiService.getPurchasePlans();
            if (plansResult != null && plansResult.isNotEmpty) {
              final productIds = plansResult.map((plan) => plan.id).toSet();
              await _purchaseService.updateProductIds(productIds);
            }
          }
        }

        // Remove duplicates based on 'id' field
        final uniqueMethods = <Map<String, dynamic>>[];
        final seenIds = <String>{};

        for (final method in methods) {
          final id = method['id'] as String? ?? '';
          if (id.isNotEmpty && !seenIds.contains(id)) {
            seenIds.add(id);
            uniqueMethods.add(method);
          }
        }

        // Sort into a predictable user-friendly order so all options are visible
        // without excessive scrolling: IAP → voucher → stripe → paypal
        const _preferredOrder = [
          'in_app_purchase',
          'iap',
          'voucher',
          'stripe',
          'paypal',
        ];
        uniqueMethods.sort((a, b) {
          final ia = _preferredOrder.indexOf(
            (a['id'] as String? ?? '').toLowerCase(),
          );
          final ib = _preferredOrder.indexOf(
            (b['id'] as String? ?? '').toLowerCase(),
          );
          final ra = ia == -1 ? _preferredOrder.length : ia;
          final rb = ib == -1 ? _preferredOrder.length : ib;
          return ra.compareTo(rb);
        });

        setState(() {
          _availablePaymentMethods = uniqueMethods;
          _isLoadingPaymentMethods = false;
        });
      } else {
        // Fallback to default payment methods if API fails
        setState(() {
          _availablePaymentMethods = _getDefaultPaymentMethods();
          _isLoadingPaymentMethods = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _availablePaymentMethods = _getDefaultPaymentMethods();
          _isLoadingPaymentMethods = false;
        });
      }
    }
  }

  List<Map<String, dynamic>> _getDefaultPaymentMethods() {
    // Order: IAP → voucher → stripe → paypal (matches preferred order above)
    final methods = [
      {
        'id': 'in_app_purchase',
        'name': 'In-App Purchase',
        'description': 'Quick and secure purchase through your device',
        'icon': 'shopping_bag',
        'enabled': true,
      },
      {
        'id': 'voucher',
        'name': 'Redeem Voucher Code',
        'description': 'Enter a voucher code for instant access',
        'icon': 'confirmation_number',
        'enabled': true,
      },
      {
        'id': 'stripe',
        'name': 'Credit/Debit Card',
        'description': 'Secure payment - Visa, Mastercard, Amex',
        'icon': 'credit_card',
        'enabled': true,
      },
      {
        'id': 'paypal',
        'name': 'PayPal',
        'description': 'Pay securely with your PayPal account',
        'icon': 'payment',
        'enabled': true,
      },
    ];

    // Platform-based payment method filtering
    if (!Platform.isAndroid && !Platform.isIOS) {
      return methods
          .where((method) => method['id'] != 'in_app_purchase')
          .toList();
    } else if (Platform.isIOS) {
      // Apple policy: only in-app purchases allowed on iOS
      return methods
          .where((method) => method['id'] == 'in_app_purchase')
          .toList();
    }

    return methods;
  }

  void _processPayPalPayment() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _selectedPaymentMethod = 'paypal';
    });

    try {
      // Get current user
      final currentUser = ref.read(currentUserProvider);

      if (currentUser == null) {
        _showErrorDialog('Please sign in to continue with payment');
        return;
      }

      final planAmount =
          double.tryParse(widget.planDetails['price'].toString()) ??
          0.0; // Create PayPal order
      final orderData = await _apiService.createPayPalOrder(
        planId: widget.planId,
        amount: planAmount,
        userId: currentUser.uid,
      );

      if (orderData['success'] == true && orderData['data'] != null) {
        final approvalUrl = orderData['data']['approval_url'];
        final orderId = orderData['data']['order_id'];

        if (approvalUrl != null && orderId != null) {
          // Launch custom PayPal WebView that can handle return URLs
          if (mounted) {
            final paymentResult = await Navigator.of(context).push<bool>(
              MaterialPageRoute(
                builder: (context) => PayPalWebViewScreen(
                  approvalUrl: approvalUrl,
                  orderId: orderId,
                  onPaymentComplete: (success, transactionId) {},
                ),
              ),
            );

            if (paymentResult == true) {
              // Payment was successful — capture and navigate directly to receipt
              try {
                final captureResult = await _apiService.capturePayPalPayment(
                  orderId: orderId,
                  userId: currentUser.uid,
                  planId: widget.planId,
                );

                if (captureResult['success'] == true) {
                  final paymentData =
                      captureResult['data'] as Map<String, dynamic>? ?? {};
                  final receiptInfo =
                      paymentData['receipt'] as Map<String, dynamic>? ?? {};

                  // Refresh subscription status
                  try {
                    await ref
                        .read(subscriptionProvider.notifier)
                        .checkSubscriptionStatus(
                          currentUser.uid,
                          forceRefresh: true,
                        );
                  } catch (_) {}

                  // Navigate directly using receipt data from capture response
                  if (mounted) {
                    Navigator.of(context).pushReplacement(
                      MaterialPageRoute(
                        builder: (context) => ReceiptScreen(
                          receiptData: {
                            'receipt_number': paymentData['receipt_id']
                                ?.toString(),
                            'transaction_id':
                                receiptInfo['transaction_id'] ??
                                paymentData['transaction_id'] ??
                                'paypal_$orderId',
                            'amount':
                                receiptInfo['amount'] ??
                                widget.planDetails['price'],
                            'currency': receiptInfo['currency'] ?? 'USD',
                            'payment_method':
                                receiptInfo['payment_method'] ?? 'paypal',
                            'created_at':
                                receiptInfo['purchase_date'] ??
                                DateTime.now().toIso8601String(),
                          },
                          planName: widget.planName,
                        ),
                      ),
                    );
                  }
                } else {
                  _showErrorDialog(
                    'Payment capture failed: ${captureResult['message']}',
                  );
                }
              } catch (e) {
                _showErrorDialog('Payment capture failed: $e');
              }
            } else {
              _showErrorDialog('PayPal payment was cancelled');
            }
          }
        } else {
          _showErrorDialog('PayPal approval URL not found');
        }
      } else {
        _showErrorDialog(
          orderData['message'] ?? 'Failed to create PayPal order',
        );
      }
    } catch (e) {
      _showErrorDialog('PayPal payment failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _processStripePayment() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _selectedPaymentMethod = 'stripe';
    });

    try {
      // Get current user
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) {
        _showErrorDialog('Please sign in to continue with payment');
        return;
      }

      // Create Stripe payment intent with increased timeout tolerance
      final paymentIntentData = await _apiService.createStripePaymentIntent(
        planId: widget.planId,
        amount: double.tryParse(widget.planDetails['price'].toString()) ?? 0.0,
        userId: currentUser.uid,
      );

      if (paymentIntentData['success'] == true &&
          paymentIntentData['data'] != null) {
        final clientSecret = paymentIntentData['data']['client_secret'];
        final paymentIntentId = paymentIntentData['data']['payment_intent_id'];
        final publishableKey = paymentIntentData['data']['publishable_key'];

        if (clientSecret != null && publishableKey != null) {
          // Initialize Stripe with the publishable key from backend
          try {
            // Set publishable key
            Stripe.publishableKey = publishableKey;

            // Apply settings with better error handling
            await Stripe.instance.applySettings();
          } catch (e) {
            _showErrorDialog(
              'Failed to initialize payment system. Please try again.',
            );
            return;
          }

          // Show custom card input bottom sheet instead of generic payment sheet
          if (mounted) {
            final result = await showStripeCardInputSheet(
              context: context,
              amount:
                  double.tryParse(widget.planDetails['price'].toString()) ??
                  0.0,
              currency: 'USD',
              planName: widget.planName,
              clientSecret: clientSecret,
              onPaymentMethodCreated: (paymentMethod) async {
                // Payment completed successfully (paymentMethod can be null for confirmed payments)

                // Payment completed successfully
                final paymentResult = {
                  'success': true,
                  'transaction_id': paymentIntentId,
                  'amount': widget.planDetails['price'],
                  'payment_method': 'stripe',
                  'payment_method_id': paymentMethod?.id ?? 'stripe_confirmed',
                };

                _handlePaymentSuccess(paymentResult);
              },
            );

            // If sheet was dismissed without payment, don't show success
            if (result == null || result == false) {
              if (mounted) {
                setState(() {
                  _isProcessing = false;
                });
              }
              return;
            }
          }
        } else {
          _showErrorDialog(
            'Invalid payment configuration received from server',
          );
        }
      } else {
        _showErrorDialog(
          paymentIntentData['message'] ?? 'Failed to create payment session',
        );
      }
    } catch (e) {
      if (e.toString().contains('timeout') ||
          e.toString().contains('receive timeout')) {
        _showErrorDialog(
          'Payment server is taking longer than expected. Please check your internet connection and try again.',
        );
      } else {
        _showErrorDialog('Payment failed: $e');
      }
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _processInAppPurchase() async {
    if (_isProcessing) return;

    setState(() {
      _isProcessing = true;
      _selectedPaymentMethod = 'inapp';
    });

    StreamSubscription<PurchaseResult>? subscription;

    try {
      // Get current user
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) {
        _showErrorDialog('Please sign in to continue with payment');
        return;
      }

      // Listen to purchase result stream
      subscription = _purchaseService.purchaseResultStream.listen((
        result,
      ) async {
        if (result.isSuccess) {
          try {
            // Activate premium benefits locally immediately (user already paid)
            await _purchaseService.activateSubscriptionBenefits();

            // Verify with backend using the REAL receipt data from the store
            final verificationResult = await _apiService.verifyPurchase(
              userId: currentUser
                  .uid, // Firebase UID string - do NOT convert to int
              receiptData:
                  result.receiptData ?? result.productId ?? widget.planId,
              productId: result.productId ?? widget.planId,
              platform: Platform.isAndroid ? 'android' : 'ios',
              transactionId: result.transactionId,
              firebaseUid: currentUser.uid,
              userEmail: currentUser.email,
            );

            if (verificationResult != null &&
                verificationResult['success'] == true) {
              // Backend confirmed - show receipt screen
              final receiptData = Map<String, dynamic>.from(
                (verificationResult['data']?['receipt'] as Map?)
                        ?.cast<String, dynamic>() ??
                    {},
              );
              // Fallback fields if receipt from backend is sparse
              receiptData['transaction_id'] ??= result.transactionId;
              receiptData['payment_method'] ??= Platform.isAndroid
                  ? 'google_play'
                  : 'app_store';
              receiptData['created_at'] ??= DateTime.now().toIso8601String();

              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => ReceiptScreen(
                      receiptData: receiptData,
                      planName: widget.planName,
                    ),
                  ),
                );
              }
            } else {
              // Backend verification failed but store confirmed purchase -
              // still show receipt with store data (user already paid).
              if (mounted) {
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute(
                    builder: (context) => ReceiptScreen(
                      receiptData: {
                        'transaction_id': result.transactionId,
                        'payment_method': Platform.isAndroid
                            ? 'google_play'
                            : 'app_store',
                        'created_at': DateTime.now().toIso8601String(),
                      },
                      planName: widget.planName,
                    ),
                  ),
                );
              }
            }
          } catch (e) {
            // Network/server error - user already paid, show receipt with
            // the store transaction data so the screen is never fully blank.
            if (mounted) {
              Navigator.of(context).pushReplacement(
                MaterialPageRoute(
                  builder: (context) => ReceiptScreen(
                    receiptData: {
                      'transaction_id': result.transactionId,
                      'payment_method': Platform.isAndroid
                          ? 'google_play'
                          : 'app_store',
                      'created_at': DateTime.now().toIso8601String(),
                    },
                    planName: widget.planName,
                  ),
                ),
              );
            }
          }
        } else if (result.isError) {
          _showErrorDialog(result.errorMessage ?? 'In-app purchase failed');
        } else if (result.isCancelled) {
          // User cancelled, just hide loading
        }

        // Always reset processing state
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }

        // Cancel subscription after handling result
        subscription?.cancel();
      });

      // Process in-app purchase

      await _purchaseService.purchaseProduct(widget.planId);
    } catch (e) {
      _showErrorDialog('In-app purchase failed: $e');
      subscription?.cancel();

      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  void _handlePaymentSuccess(Map<String, dynamic> paymentResult) async {
    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) {
        _showErrorDialog('User not authenticated');
        return;
      }

      // Generate receipt on backend
      final rawReceiptData = await _apiService.createPaymentTransaction(
        userId: currentUser.uid,
        transactionId: paymentResult['transaction_id'].toString(),
        planId: widget.planId,
        paymentMethod: _selectedPaymentMethod,
        amount: double.tryParse(paymentResult['amount'].toString()) ?? 0.0,
        gateway: _selectedPaymentMethod,
        status: 'completed',
      );

      // Map API key 'receipt_id' → 'receipt_number' expected by ReceiptScreen.
      // If the API call failed (no transaction_id in response), fall back to
      // the local payment result so the receipt screen always shows real data.
      final receiptData = Map<String, dynamic>.from(rawReceiptData);
      receiptData['receipt_number'] ??= receiptData['receipt_id'];
      if (!receiptData.containsKey('transaction_id') ||
          receiptData['transaction_id'] == null) {
        receiptData['transaction_id'] = paymentResult['transaction_id'];
        receiptData['amount'] ??= paymentResult['amount'];
        receiptData['currency'] ??= 'USD';
        receiptData['payment_method'] ??= _selectedPaymentMethod;
        receiptData['created_at'] ??= DateTime.now().toIso8601String();
        receiptData['receipt_number'] ??=
            'TXN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}';
      }

      // Refresh subscription status
      try {
        await ref
            .read(subscriptionProvider.notifier)
            .checkSubscriptionStatus(currentUser.uid, forceRefresh: true);
      } catch (e) {
        // Don't block payment completion if subscription check fails
      }

      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ReceiptScreen(
              receiptData: receiptData,
              planName: widget.planName,
            ),
          ),
        );
      }
    } catch (e) {
      // If receipt generation fails entirely, still navigate to receipt with
      // the basic payment result data so the screen is never fully blank.
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => ReceiptScreen(
              receiptData: {
                'receipt_number':
                    'TXN-${DateTime.now().millisecondsSinceEpoch.toString().substring(7)}',
                'transaction_id': paymentResult['transaction_id'],
                'amount': paymentResult['amount'],
                'currency': 'USD',
                'payment_method': _selectedPaymentMethod,
                'created_at': DateTime.now().toIso8601String(),
              },
              planName: widget.planName,
            ),
          ),
        );
      }
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E293B),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [Color(0xFF10B981), Color(0xFF059669)],
                ),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check, size: 40, color: Colors.white),
            ),
            const SizedBox(height: 24),
            const Text(
              'Payment Successful!',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(
              'Your ${widget.planName} subscription has been activated successfully.',
              style: const TextStyle(fontSize: 16, color: Color(0xFF94A3B8)),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.of(context).popUntil(ModalRoute.withName('/home'));
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: const Color(0xFF1E293B),
        title: const Text(
          'Payment Error',
          style: TextStyle(color: Colors.white),
        ),
        content: Text(
          message,
          style: const TextStyle(color: Color(0xFF94A3B8)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  void _processVoucherRedemption() async {
    if (_isProcessing) return;

    setState(() {
      _selectedPaymentMethod = 'voucher';
    });

    // Show voucher code input dialog
    _showVoucherCodeDialog();
  }

  /// Helper method to safely parse features from JSON string or List
  String _parseFeatures(dynamic features) {
    try {
      if (features == null) return '';

      // If it's already a List
      if (features is List) {
        return features.map((f) => f.toString()).join(', ');
      }

      // If it's a JSON string, parse it first
      if (features is String) {
        final parsed = json.decode(features);
        if (parsed is List) {
          return parsed.map((f) => f.toString()).join(', ');
        }
        return features; // Return as-is if not a list
      }

      return features.toString();
    } catch (e) {
      // Fallback to string representation if parsing fails
      return features.toString();
    }
  }

  /// Helper method to safely get features as a List
  List<String> _getFeaturesAsList(dynamic features) {
    try {
      if (features == null) return [];

      // If it's already a List
      if (features is List) {
        return features.map((f) => f.toString()).toList();
      }

      // If it's a JSON string, parse it first
      if (features is String) {
        final parsed = json.decode(features);
        if (parsed is List) {
          return parsed.map((f) => f.toString()).toList();
        }
        return [features]; // Return as single item list if not a list
      }

      return [features.toString()];
    } catch (e) {
      return [];
    }
  }

  void _showVoucherCodeDialog() {
    String voucherCode = '';
    bool isValidating = false;
    bool isRedeeming = false;
    Map<String, dynamic>? voucherDetails;

    showDialog(
      context: context,
      barrierDismissible: !isValidating && !isRedeeming,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final isDarkMode = theme.brightness == Brightness.dark;
          final accentColor = ref.read(themeColorProvider);

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
                          Icons.confirmation_number,
                          color: accentColor,
                          size: 24,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Redeem Voucher Code',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: isDarkMode ? Colors.white : Colors.black87,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: (isValidating || isRedeeming)
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  setState(() {
                                    _selectedPaymentMethod = '';
                                  });
                                },
                          icon: Icon(
                            Icons.close,
                            color: isDarkMode ? Colors.white70 : Colors.black54,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    Text(
                      'Enter your voucher code to redeem instant access',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: isDarkMode ? Colors.white70 : Colors.black54,
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Voucher Input Field
                    TextField(
                      onChanged: (value) {
                        setDialogState(() {
                          voucherCode = value.trim().toUpperCase();
                          if (voucherDetails != null) {
                            voucherDetails = null;
                          }
                        });
                      },
                      style: TextStyle(
                        color: isDarkMode ? Colors.white : Colors.black87,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: 'XXXX-XXXX-XXXX',
                        hintStyle: TextStyle(
                          color: isDarkMode ? Colors.white38 : Colors.black38,
                        ),
                        filled: true,
                        fillColor: isDarkMode
                            ? Colors.white.withValues(alpha: 0.05)
                            : Colors.grey.withValues(alpha: 0.1),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? Colors.white24
                                : Colors.grey.shade300,
                          ),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                            color: isDarkMode
                                ? Colors.white24
                                : Colors.grey.shade300,
                          ),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: accentColor, width: 2),
                        ),
                        prefixIcon: Icon(
                          Icons.confirmation_number,
                          color: accentColor,
                        ),
                      ),
                    ),

                    // Validation Result
                    if (voucherDetails != null) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: accentColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.check_circle,
                                  color: accentColor,
                                  size: 20,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Valid Voucher Code',
                                  style: TextStyle(
                                    color: accentColor,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Product: ${voucherDetails!['product']['name']}',
                              style: TextStyle(
                                color: isDarkMode
                                    ? Colors.white
                                    : Colors.black87,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (voucherDetails!['product']['features'] !=
                                null) ...[
                              const SizedBox(height: 8),
                              Text(
                                'Features: ${_parseFeatures(voucherDetails!['product']['features'])}',
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white70
                                      : Colors.black54,
                                  fontSize: 13,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    // Action Buttons
                    Row(
                      children: [
                        // Cancel Button
                        Expanded(
                          child: TextButton(
                            onPressed: (isValidating || isRedeeming)
                                ? null
                                : () {
                                    Navigator.of(context).pop();
                                    setState(() {
                                      _selectedPaymentMethod = '';
                                    });
                                  },
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              'Cancel',
                              style: TextStyle(
                                color: isDarkMode
                                    ? Colors.white70
                                    : Colors.black54,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 16),

                        // Main Action Button - Always visible now
                        Expanded(
                          child: voucherDetails == null
                              ? ElevatedButton(
                                  onPressed:
                                      (isValidating || voucherCode.isEmpty)
                                      ? null
                                      : () async {
                                          setDialogState(() {
                                            isValidating = true;
                                          });

                                          try {
                                            final currentUser = ref.read(
                                              currentUserProvider,
                                            );
                                            if (currentUser == null) {
                                              _showErrorDialog(
                                                'Please sign in to continue',
                                              );
                                              return;
                                            }

                                            final response = await _apiService
                                                .validateVoucherCode(
                                                  voucherCode,
                                                );

                                            if (response['success'] &&
                                                response['valid']) {
                                              setDialogState(() {
                                                voucherDetails = response;
                                                isValidating = false;
                                              });
                                            } else {
                                              setDialogState(() {
                                                isValidating = false;
                                              });
                                              _showErrorDialog(
                                                response['message'] ??
                                                    'Invalid voucher code',
                                              );
                                            }
                                          } catch (e) {
                                            setDialogState(() {
                                              isValidating = false;
                                            });
                                            _showErrorDialog(
                                              'Failed to validate voucher code',
                                            );
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        (isValidating || voucherCode.isEmpty)
                                        ? (isDarkMode
                                              ? Colors.grey.shade700
                                              : Colors.grey.shade300)
                                        : accentColor,
                                    foregroundColor:
                                        (isValidating || voucherCode.isEmpty)
                                        ? (isDarkMode
                                              ? Colors.grey.shade400
                                              : Colors.grey.shade600)
                                        : Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: isValidating
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : const Text(
                                          'Validate',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                )
                              : ElevatedButton(
                                  onPressed: isRedeeming
                                      ? null
                                      : () async {
                                          setDialogState(() {
                                            isRedeeming = true;
                                          });

                                          try {
                                            final currentUser = ref.read(
                                              currentUserProvider,
                                            );
                                            if (currentUser == null) {
                                              _showErrorDialog(
                                                'Please sign in to continue',
                                              );
                                              return;
                                            }

                                            final response = await _apiService
                                                .redeemVoucherCode(
                                                  voucherCode,
                                                  currentUser.uid,
                                                );

                                            if (response['success']) {
                                              // IMMEDIATELY refresh subscription status after voucher redemption
                                              print(
                                                '[Voucher] Voucher redeemed successfully, refreshing subscription...',
                                              );
                                              try {
                                                await ref
                                                    .read(
                                                      subscriptionProvider
                                                          .notifier,
                                                    )
                                                    .checkSubscriptionStatus(
                                                      currentUser.uid,
                                                      forceRefresh: true,
                                                    );
                                                print(
                                                  '[Voucher] Subscription status refreshed successfully',
                                                );
                                              } catch (e) {
                                                print(
                                                  '[Voucher] Error refreshing subscription: $e',
                                                );
                                                // Don't block voucher redemption if subscription check fails
                                              }
                                              Navigator.of(
                                                context,
                                              ).pop(); // Close dialog

                                              // Navigate to success screen
                                              Navigator.of(
                                                context,
                                              ).pushReplacement(
                                                MaterialPageRoute(
                                                  builder: (context) => ReceiptScreen(
                                                    receiptData: {
                                                      'transaction_id':
                                                          'voucher_${DateTime.now().millisecondsSinceEpoch}',
                                                      'amount': 0,
                                                      'currency': 'USD',
                                                      'payment_method':
                                                          'voucher',
                                                      'status': 'completed',
                                                      'created_at':
                                                          DateTime.now()
                                                              .toIso8601String(),
                                                      'voucher_code':
                                                          voucherCode,
                                                      'subscription':
                                                          response['subscription'],
                                                    },
                                                    planName:
                                                        voucherDetails!['product']['name'],
                                                  ),
                                                ),
                                              );
                                            } else {
                                              setDialogState(() {
                                                isRedeeming = false;
                                              });
                                              _showErrorDialog(
                                                response['message'] ??
                                                    'Failed to redeem voucher',
                                              );
                                            }
                                          } catch (e) {
                                            setDialogState(() {
                                              isRedeeming = false;
                                            });
                                            _showErrorDialog(
                                              'Failed to redeem voucher code',
                                            );
                                          }
                                        },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: accentColor,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: isRedeeming
                                      ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor:
                                                AlwaysStoppedAnimation<Color>(
                                                  Colors.white,
                                                ),
                                          ),
                                        )
                                      : const Text(
                                          'Redeem',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeColor = ref.watch(themeColorProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : Colors.grey[50],
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: isDarkMode ? Colors.white : Colors.black87,
        elevation: 0,
        title: const Text('Payment Options'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPlanSummary(themeColor, isDarkMode),
                    const SizedBox(height: 32),
                    _buildPaymentMethods(themeColor, isDarkMode),
                    const SizedBox(height: 32),
                    _buildSecurityInfo(isDarkMode),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildPlanSummary(Color themeColor, bool isDarkMode) {
    return FadeInUp(
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: themeColor.withValues(alpha: 0.2),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: isDarkMode
                  ? Colors.black.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [themeColor, themeColor.withValues(alpha: 0.7)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.workspace_premium,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.planName,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black87,
                        ),
                      ),
                      Text(
                        widget.planPrice,
                        style: TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                          color: themeColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 16),
            Text(
              'Included Features:',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 12),
            ...List.generate(
              _getFeaturesAsList(widget.planDetails['features']).length,
              (index) {
                final feature = _getFeaturesAsList(
                  widget.planDetails['features'],
                )[index];
                return Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      Icon(Icons.check_circle, color: themeColor, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          feature,
                          style: TextStyle(
                            fontSize: 14,
                            color: isDarkMode
                                ? const Color(0xFF94A3B8)
                                : Colors.grey[600],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaymentMethods(Color themeColor, bool isDarkMode) {
    return FadeInUp(
      delay: const Duration(milliseconds: 200),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Choose Payment Method',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 16),

          // Show loading state while fetching payment methods
          if (_isLoadingPaymentMethods) ...[
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 16),
            Text(
              'Loading payment methods...',
              style: TextStyle(
                color: isDarkMode ? Colors.white70 : Colors.black54,
              ),
              textAlign: TextAlign.center,
            ),
          ] else ...[
            // Dynamic payment methods
            ..._availablePaymentMethods.asMap().entries.map((entry) {
              final index = entry.key;
              final method = entry.value;

              return Column(
                children: [
                  _buildDynamicPaymentMethodCard(
                    method: method,
                    themeColor: themeColor,
                    isDarkMode: isDarkMode,
                  ),
                  if (index < _availablePaymentMethods.length - 1)
                    const SizedBox(height: 16),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }

  Widget _buildDynamicPaymentMethodCard({
    required Map<String, dynamic> method,
    required Color themeColor,
    required bool isDarkMode,
  }) {
    final methodId = method['id'] as String;
    final methodName = method['name'] as String;
    final methodDescription = method['description'] as String;
    final iconName = method['icon'] as String? ?? 'payment';
    final isEnabled = method['enabled'] as bool? ?? true;

    if (!isEnabled) return const SizedBox.shrink();

    // Map icon names to Flutter icons
    IconData icon = _getIconFromName(iconName);

    // Map method IDs to colors
    Color color = _getColorForMethod(methodId, themeColor);

    // Map method IDs to callback functions
    VoidCallback? onTap = _getCallbackForMethod(methodId);

    return _buildPaymentMethodCard(
      icon: icon,
      title: methodName,
      subtitle: methodDescription,
      onTap: onTap ?? () => _showUnavailableMethodDialog(methodName),
      isProcessing: _isProcessing && _selectedPaymentMethod == methodId,
      color: color,
      isDarkMode: isDarkMode,
    );
  }

  IconData _getIconFromName(String iconName) {
    switch (iconName.toLowerCase()) {
      case 'credit_card':
        return Icons.credit_card;
      case 'payment':
        return Icons.payment;
      case 'shopping_bag':
        return Icons.shopping_bag;
      case 'confirmation_number':
        return Icons.confirmation_number;
      default:
        return Icons.payment;
    }
  }

  Color _getColorForMethod(String methodId, Color themeColor) {
    switch (methodId.toLowerCase()) {
      case 'stripe':
        return const Color(0xFF635BFF);
      case 'paypal':
        return const Color(0xFF0070BA);
      case 'iap':
      case 'in_app_purchase':
        return const Color(0xFF4CAF50);
      case 'voucher':
        return themeColor;
      default:
        return themeColor;
    }
  }

  VoidCallback? _getCallbackForMethod(String methodId) {
    switch (methodId.toLowerCase()) {
      case 'stripe':
        return _processStripePayment;
      case 'paypal':
        return _processPayPalPayment;
      case 'iap':
      case 'in_app_purchase':
        return _processInAppPurchase;
      case 'voucher':
        return _processVoucherRedemption;
      default:
        return null;
    }
  }

  void _showUnavailableMethodDialog(String methodName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Payment Method Unavailable'),
        content: Text(
          '$methodName is currently not available. Please try another payment method.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  Widget _buildPaymentMethodCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required bool isProcessing,
    required Color color,
    required bool isDarkMode,
  }) {
    return Container(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isProcessing ? null : onTap,
        style: ElevatedButton.styleFrom(
          backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          foregroundColor: isDarkMode ? Colors.white : Colors.black87,
          elevation: 0,
          padding: const EdgeInsets.all(20),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: isDarkMode
                  ? Colors.white.withValues(alpha: 0.1)
                  : Colors.grey.withValues(alpha: 0.2),
              width: 1,
            ),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDarkMode
                          ? const Color(0xFF94A3B8)
                          : Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
            if (isProcessing)
              const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              Icon(
                Icons.arrow_forward_ios,
                size: 16,
                color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[600],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecurityInfo(bool isDarkMode) {
    return FadeInUp(
      delay: const Duration(milliseconds: 400),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF1E293B).withValues(alpha: 0.5)
              : Colors.grey[50],
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isDarkMode
                ? Colors.white.withValues(alpha: 0.1)
                : Colors.grey.withValues(alpha: 0.2),
            width: 1,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                Icon(
                  Icons.security,
                  color: isDarkMode ? Colors.green[400] : Colors.green[600],
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  'Secure Payment',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isDarkMode ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Your payment information is encrypted and secure. We never store your payment details.',
              style: TextStyle(
                fontSize: 12,
                color: isDarkMode ? const Color(0xFF94A3B8) : Colors.grey[600],
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock,
                  size: 16,
                  color: isDarkMode
                      ? const Color(0xFF94A3B8)
                      : Colors.grey[600],
                ),
                const SizedBox(width: 8),
                Text(
                  '256-bit SSL encryption',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode
                        ? const Color(0xFF94A3B8)
                        : Colors.grey[600],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
