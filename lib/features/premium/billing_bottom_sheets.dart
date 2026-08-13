// lib/features/premium/billing_bottom_sheets.dart
// All payment bottom sheets — WebViews open AS bottom sheets (quickro-POS style).

import 'dart:async';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../../services/billing_service.dart';
import '../../core/services/purchase_service.dart';
import '../../shared/providers/theme_provider.dart';
import '../../providers/subscription_provider.dart';
import '../../core/config/app_config.dart';
import '../../screens/auth/sign_in_screen.dart';

// ─── PAYMENT METHOD SHEET ─────────────────────────────────────────────────────

Future<void> showPaymentMethodSheet(
  BuildContext context,
  WidgetRef ref,
  String productId,
  Map<String, dynamic> planData,
) {
  // Require sign-in before payment
  if (FirebaseAuth.instance.currentUser == null) {
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SignInScreen()));
    return Future.value();
  }

  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _PaymentMethodSheet(
      productId: productId,
      planData: planData,
      externalRef: ref,
    ),
  );
}

class _PaymentMethodSheet extends ConsumerStatefulWidget {
  const _PaymentMethodSheet({
    required this.productId,
    required this.planData,
    required this.externalRef,
  });
  final String productId;
  final Map<String, dynamic> planData;
  final WidgetRef externalRef;
  @override
  ConsumerState<_PaymentMethodSheet> createState() =>
      _PaymentMethodSheetState();
}

class _PaymentMethodSheetState extends ConsumerState<_PaymentMethodSheet> {
  bool _loading = false;
  bool _loadingMethods = true;
  String? _error;
  // Enabled method IDs fetched from admin (e.g. ['stripe', 'paypal', 'iap'])
  List<String> _enabledIds = [];

  @override
  void initState() {
    super.initState();
    _fetchEnabledMethods();
  }

  Future<void> _fetchEnabledMethods() async {
    try {
      final ids = await BillingService().getEnabledPaymentMethodIds();
      if (mounted) {
        setState(() {
          _enabledIds = ids;
          _loadingMethods = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingMethods = false);
    }
  }

  bool _isEnabled(String id) => _enabledIds.contains(id.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeColorProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final name = widget.planData['display_name'] ?? widget.productId;
    final price = widget.planData['web_price']?.toString() ?? '';

    return _Sheet(
      isDark: isDark,
      maxFraction: 0.70,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Handle(isDark: isDark),
          // Summary row
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: theme.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.workspace_premium, color: theme, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Pay for $name',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                          color: isDark
                              ? Colors.white
                              : const Color(0xFF1A1A2E),
                        ),
                      ),
                      if (price.isNotEmpty)
                        Text(
                          '\$$price',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (_error != null)
            _ErrorBar(
              message: _error!,
              onDismiss: () => setState(() => _error = null),
            ),
          if (_loadingMethods || _loading)
            const Padding(
              padding: EdgeInsets.all(36),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (Platform.isIOS) ...[
            // iOS: Apple policy requires in-app purchase only
            _MethodTile(brand: _Brand.appStore, isDark: isDark, onTap: _doIap),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              child: Text(
                'On iOS, purchases are processed through the App Store.',
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ] else
            _buildAndroidMethods(isDark),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildAndroidMethods(bool isDark) {
    final tiles = <Widget>[];

    void addTile(Widget tile) {
      if (tiles.isNotEmpty) tiles.add(_Divider(isDark: isDark));
      tiles.add(tile);
    }

    if (_isEnabled('stripe')) {
      addTile(
        _MethodTile(brand: _Brand.stripe, isDark: isDark, onTap: _doStripe),
      );
    }
    if (_isEnabled('paypal')) {
      addTile(
        _MethodTile(brand: _Brand.paypal, isDark: isDark, onTap: _doPaypal),
      );
    }
    if (_isEnabled('crypto')) {
      addTile(
        _MethodTile(
          brand: _Brand.crypto,
          isDark: isDark,
          onTap: () {
            Navigator.pop(context);
            showCryptoSheet(context, ref, widget.productId, widget.planData);
          },
        ),
      );
    }
    // Google Play IAP — keyed as 'iap' or 'in_app_purchase' from the API
    if (_isEnabled('iap') || _isEnabled('in_app_purchase')) {
      addTile(
        _MethodTile(brand: _Brand.googlePlay, isDark: isDark, onTap: _doIap),
      );
    }

    if (tiles.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        child: Center(
          child: Text(
            'No payment methods are currently available.\nPlease contact support.',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
            ),
          ),
        ),
      );
    }

    return Column(mainAxisSize: MainAxisSize.min, children: tiles);
  }

  Future<void> _doStripe() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = AppConfig.baseUrl;
      final result = await BillingService().stripeCheckout(
        productId: widget.productId,
        successUrl: '$base/payment/success?session_id={CHECKOUT_SESSION_ID}',
        cancelUrl: '$base/payment/cancel',
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (result['checkout_url'] == null) {
        setState(
          () =>
              _error = result['message'] ?? 'Could not start Stripe checkout.',
        );
        return;
      }
      // ignore: use_build_context_synchronously
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        enableDrag:
            false, // prevent sheet drag from intercepting WebView scroll
        backgroundColor: Colors.transparent,
        useSafeArea: false,
        builder: (_) => _WebViewSheet(
          url: result['checkout_url'] as String,
          title: 'Stripe Checkout',
          successPattern: '/payment/success',
          cancelPattern: '/payment/cancel',
          onSuccess: (url) async {
            final sid = Uri.parse(url).queryParameters['session_id'];
            if (sid != null) await BillingService().confirmStripeSession(sid);
            return true;
          },
        ),
      );
      if (ok == true && mounted) {
        widget.externalRef.read(subscriptionProvider.notifier).refresh();
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Payment successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _doPaypal() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final base = AppConfig.baseUrl;
      final result = await BillingService().createPaypalOrder(
        productId: widget.productId,
        returnUrl: '$base/payment/paypal/return',
        cancelUrl: '$base/payment/paypal/cancel',
      );
      if (!mounted) return;
      setState(() => _loading = false);
      if (result['approve_url'] == null) {
        setState(
          () =>
              _error = result['message'] ?? 'Could not start PayPal checkout.',
        );
        return;
      }
      final orderId = result['order_id'] as String?;
      // ignore: use_build_context_synchronously
      final ok = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        enableDrag:
            false, // prevent sheet drag from intercepting WebView scroll
        backgroundColor: Colors.transparent,
        useSafeArea: false,
        builder: (_) => _WebViewSheet(
          url: result['approve_url'] as String,
          title: 'PayPal Checkout',
          successPattern: '/payment/paypal/return',
          cancelPattern: '/payment/paypal/cancel',
          onSuccess: (url) async {
            if (orderId != null) {
              await BillingService().capturePaypalOrder(orderId);
            }
            return true;
          },
        ),
      );
      if (ok == true && mounted) {
        widget.externalRef.read(subscriptionProvider.notifier).refresh();
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('PayPal payment successful!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  Future<void> _doIap() async {
    // Determine the store-specific product ID from plan data
    final storeProductId = Platform.isIOS
        ? (widget.planData['app_store_product_id'] ??
              widget.planData['ios_price_id'] ??
              widget.productId)
        : (widget.planData['google_play_product_id'] ??
              widget.planData['android_price_id'] ??
              widget.productId);

    final purchaseService = PurchaseService();

    // Ensure the store product is loaded before attempting purchase.
    // _productIds may have been empty at init, so force-load the specific ID now.
    try {
      await purchaseService.ensureProductLoaded(storeProductId.toString());
    } catch (_) {}

    // Listen to purchase result
    late final StreamSubscription<PurchaseResult> sub;
    sub = purchaseService.purchaseResultStream.listen((result) async {
      sub.cancel();
      if (!mounted) return;
      if (result.isSuccess || result.isRestored) {
        // Verify with backend and refresh subscription
        try {
          if (result.receiptData != null) {
            await BillingService().verifyIap(
              productId: widget.productId,
              receiptData: result.receiptData!,
              transactionId: result.transactionId ?? '',
              platform: Platform.isIOS ? 'app_store' : 'google_play',
            );
          }
        } catch (_) {}
        if (!mounted) return;
        widget.externalRef.read(subscriptionProvider.notifier).refresh();
        // ignore: use_build_context_synchronously
        Navigator.pop(context);
        // ignore: use_build_context_synchronously
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Purchase successful!'),
            backgroundColor: Colors.green,
          ),
        );
      } else if (result.isError) {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = result.errorMessage ?? 'Purchase failed';
        });
      }
      // pending: keep spinner
    });

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await purchaseService.purchaseProduct(storeProductId.toString());
    } catch (e) {
      sub.cancel();
      if (mounted) {
        setState(() {
          _loading = false;
          _error = e.toString();
        });
      }
    }
  }
}

// ─── WEBVIEW SHEET ────────────────────────────────────────────────────────────

class _WebViewSheet extends StatefulWidget {
  const _WebViewSheet({
    required this.url,
    required this.title,
    required this.successPattern,
    required this.cancelPattern,
    required this.onSuccess,
  });
  final String url;
  final String title;
  final String successPattern;
  final String cancelPattern;
  final Future<bool> Function(String url) onSuccess;

  @override
  State<_WebViewSheet> createState() => _WebViewSheetState();
}

class _WebViewSheetState extends State<_WebViewSheet> {
  late final WebViewController _ctrl;
  bool _loading = true;
  double _progress = 0;
  bool _handled = false;

  @override
  void initState() {
    super.initState();
    _ctrl = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (p) {
            if (mounted) {
              setState(() {
                _progress = p / 100.0;
                _loading = p < 100;
              });
            }
          },
          onNavigationRequest: (req) async {
            if (_handled) return NavigationDecision.prevent;
            final url = req.url;
            if (url.contains(widget.successPattern)) {
              _handled = true;
              final ok = await widget.onSuccess(url);
              if (mounted) Navigator.pop(context, ok);
              return NavigationDecision.prevent;
            }
            if (url.contains(widget.cancelPattern)) {
              _handled = true;
              if (mounted) Navigator.pop(context, false);
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.url));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return SizedBox(
      height: MediaQuery.of(context).size.height,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF0D1117) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            _Handle(isDark: isDark),
            // Title bar
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 8, 8),
              child: Row(
                children: [
                  const Icon(Icons.lock_outline, color: Colors.green, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: Icon(
                      Icons.close,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    onPressed: () => Navigator.pop(context, false),
                  ),
                ],
              ),
            ),
            // Progress bar
            SizedBox(
              height: 3,
              child: _loading
                  ? LinearProgressIndicator(
                      value: _progress > 0 ? _progress : null,
                      backgroundColor: Colors.transparent,
                      color: const Color(0xFF6772E5),
                    )
                  : const SizedBox.shrink(),
            ),
            const Divider(height: 1),
            Expanded(child: WebViewWidget(controller: _ctrl)),
          ],
        ),
      ),
    );
  }
}

// ─── RECEIPTS SHEET ───────────────────────────────────────────────────────────

Future<void> showReceiptsSheet(BuildContext context) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) => const _ReceiptsSheet(),
);

class _ReceiptsSheet extends ConsumerStatefulWidget {
  const _ReceiptsSheet();
  @override
  ConsumerState<_ReceiptsSheet> createState() => _ReceiptsSheetState();
}

class _ReceiptsSheetState extends ConsumerState<_ReceiptsSheet> {
  bool _loading = true;
  List<Map<String, dynamic>> _items = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    try {
      final res = await BillingService().getReceipts();
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        final list = (data?['receipts'] as List? ?? []);
        setState(() {
          _items = list.cast<Map<String, dynamic>>();
          _loading = false;
        });
      } else {
        setState(() {
          _error = res['message'] ?? 'Could not load receipts.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = ref.watch(themeColorProvider);

    return _Sheet(
      isDark: isDark,
      maxFraction: 0.88,
      child: Column(
        children: [
          _Handle(isDark: isDark),
          _SheetTitle(
            title: 'Payment Receipts',
            subtitle: 'Your subscription history',
            isDark: isDark,
          ),
          Flexible(
            child: _loading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _error != null
                ? Padding(
                    padding: const EdgeInsets.all(20),
                    child: _ErrorBar(message: _error!),
                  )
                : _items.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 48,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'No receipts yet.',
                          style: TextStyle(
                            color: Colors.grey.shade400,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
                    itemCount: _items.length,
                    itemBuilder: (_, i) => _ReceiptCard(
                      receipt: _items[i],
                      theme: theme,
                      isDark: isDark,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ReceiptCard extends StatelessWidget {
  const _ReceiptCard({
    required this.receipt,
    required this.theme,
    required this.isDark,
  });
  final Map<String, dynamic> receipt;
  final Color theme;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final plan = receipt['plan'] ?? receipt['product_id'] ?? '–';
    final source = receipt['source'] ?? '–';
    final amount = receipt['amount_paid'];
    final currency = receipt['currency'] ?? 'USD';
    final status = (receipt['payment_status'] as String? ?? '–').toUpperCase();
    final isActive = receipt['is_active'] == true;
    final expires = receipt['expires_at'];
    final created = receipt['created_at'];

    final statusColor = isActive
        ? Colors.green
        : (status == 'PENDING' ? Colors.orange : Colors.grey);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161B22) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isActive
              ? theme.withValues(alpha: 0.45)
              : (isDark ? const Color(0xFF30363D) : Colors.grey.shade200),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  plan.toString().toUpperCase(),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                  ),
                ),
              ),
              if (amount != null)
                Text(
                  '\$${amount.toString()} $currency',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: theme,
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _StatusPill(label: status, color: statusColor),
              const SizedBox(width: 8),
              Text(
                source.toString(),
                style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
              ),
              const Spacer(),
              if (expires != null)
                Text(
                  'exp ${_dtShort(expires.toString())}',
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                ),
            ],
          ),
          if (created != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                'Purchased ${_dtShort(created.toString())}',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
            ),
        ],
      ),
    );
  }

  static String _dtShort(String iso) {
    try {
      final d = DateTime.parse(iso);
      const m = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ];
      return '${d.day} ${m[d.month - 1]} ${d.year}';
    } catch (_) {
      return iso;
    }
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.label, required this.color});
  final String label;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w800,
        color: color,
        letterSpacing: 0.4,
      ),
    ),
  );
}

// ─── VOUCHER SHEET ────────────────────────────────────────────────────────────

Future<void> showVoucherSheet(BuildContext context, WidgetRef ref) =>
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _VoucherSheet(externalRef: ref),
    );

class _VoucherSheet extends ConsumerStatefulWidget {
  const _VoucherSheet({required this.externalRef});
  final WidgetRef externalRef;
  @override
  ConsumerState<_VoucherSheet> createState() => _VoucherSheetState();
}

class _VoucherSheetState extends ConsumerState<_VoucherSheet> {
  final _ctrl = TextEditingController();
  bool _loading = false;
  String? _error;
  String? _success;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _redeem() async {
    final code = _ctrl.text.trim().toUpperCase();
    if (code.isEmpty) {
      setState(() => _error = 'Please enter a voucher code.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _success = null;
    });
    try {
      final res = await BillingService().redeemVoucher(code);
      if (!mounted) return;
      if (res['success'] == true) {
        widget.externalRef.read(subscriptionProvider.notifier).refresh();
        setState(() {
          _success =
              res['message'] ?? 'Voucher applied! Your plan is now active.';
          _loading = false;
        });
      } else {
        setState(() {
          _error = res['message'] ?? 'Invalid or expired voucher code.';
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = ref.watch(themeColorProvider);
    final bottom = MediaQuery.of(context).viewInsets.bottom;

    return _Sheet(
      isDark: isDark,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Handle(isDark: isDark),
            _SheetTitle(
              title: 'Redeem Voucher',
              subtitle: 'Enter your voucher code below',
              isDark: isDark,
            ),
            if (_error != null)
              _ErrorBar(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
            if (_success != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Colors.green,
                        size: 20,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _success!,
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: TextField(
                controller: _ctrl,
                textCapitalization: TextCapitalization.characters,
                onChanged: (v) {
                  final up = v.toUpperCase();
                  if (up != v) {
                    _ctrl.value = _ctrl.value.copyWith(
                      text: up,
                      selection: TextSelection.collapsed(offset: up.length),
                    );
                  }
                },
                decoration: InputDecoration(
                  hintText: 'VPN-XXXX-XXXX',
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF0D1117)
                      : Colors.grey.shade100,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  prefixIcon: Icon(Icons.local_offer_outlined, color: theme),
                ),
                style: TextStyle(
                  fontFamily: 'monospace',
                  letterSpacing: 2.5,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 16),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: theme,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                  onPressed: _loading ? null : _redeem,
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : const Text(
                          'Redeem',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── CRYPTO SHEET ─────────────────────────────────────────────────────────────

Future<void> showCryptoSheet(
  BuildContext context,
  WidgetRef ref,
  String productId,
  Map<String, dynamic> planData,
) => showModalBottomSheet(
  context: context,
  isScrollControlled: true,
  backgroundColor: Colors.transparent,
  builder: (_) =>
      _CryptoSheet(productId: productId, planData: planData, externalRef: ref),
);

class _CryptoSheet extends ConsumerStatefulWidget {
  const _CryptoSheet({
    required this.productId,
    required this.planData,
    required this.externalRef,
  });
  final String productId;
  final Map<String, dynamic> planData;
  final WidgetRef externalRef;
  @override
  ConsumerState<_CryptoSheet> createState() => _CryptoSheetState();
}

class _CryptoSheetState extends ConsumerState<_CryptoSheet> {
  final _txCtrl = TextEditingController();
  final _picker = ImagePicker();
  String _coin = 'BTC';
  Map<String, dynamic> _wallets = {};
  bool _loadCfg = true;
  bool _submit = false;
  String? _error;
  String? _success;
  String? _proofPath;
  final _coins = ['BTC', 'ETH', 'USDT'];

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _txCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final res = await BillingService().getCryptoConfig();
      if (!mounted) return;
      if (res['success'] == true) {
        final data = res['data'] as Map<String, dynamic>?;
        setState(() {
          _wallets = (data?['wallets'] as Map?)?.cast<String, dynamic>() ?? {};
          _loadCfg = false;
        });
      } else {
        setState(() => _loadCfg = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loadCfg = false);
    }
  }

  Future<void> _pickProof() async {
    final f = await _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );
    if (f != null && mounted) setState(() => _proofPath = f.path);
  }

  Future<void> _submitPayment() async {
    final tx = _txCtrl.text.trim();
    if (tx.isEmpty) {
      setState(() => _error = 'Please enter the transaction hash.');
      return;
    }
    setState(() {
      _submit = true;
      _error = null;
    });
    try {
      final res = await BillingService().submitCryptoPayment(
        productId: widget.productId,
        txHash: tx,
        coin: _coin,
        proofImagePath: _proofPath,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          _success = 'Submitted! Admin will verify and activate within 24h.';
          _submit = false;
        });
      } else {
        setState(() {
          _error = res['message'] ?? 'Submission failed.';
          _submit = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _submit = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final name = widget.planData['display_name'] ?? widget.productId;
    final price = widget.planData['web_price']?.toString() ?? '';
    final wallet = _wallets[_coin.toLowerCase()] as String? ?? '';

    return _Sheet(
      isDark: isDark,
      maxFraction: 0.95,
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Handle(isDark: isDark),
            _SheetTitle(
              title: 'Crypto Payment',
              subtitle: '$name${price.isNotEmpty ? " · \$$price" : ""}',
              isDark: isDark,
            ),
            if (_error != null)
              _ErrorBar(
                message: _error!,
                onDismiss: () => setState(() => _error = null),
              ),
            if (_success != null)
              _GreenBar(message: _success!)
            else if (_loadCfg)
              const Padding(
                padding: EdgeInsets.all(40),
                child: Center(child: CircularProgressIndicator()),
              )
            else ...[
              // Coin picker
              _SectionLabel(label: 'Select Coin', isDark: isDark),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: Row(
                  children: _coins.map((c) {
                    final sel = c == _coin;
                    return Padding(
                      padding: const EdgeInsets.only(right: 10),
                      child: GestureDetector(
                        onTap: () => setState(() => _coin = c),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 20,
                            vertical: 11,
                          ),
                          decoration: BoxDecoration(
                            color: sel
                                ? Colors.amber.shade700
                                : (isDark
                                      ? const Color(0xFF1C2128)
                                      : Colors.grey.shade100),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: sel
                                  ? Colors.amber.shade700
                                  : Colors.transparent,
                              width: 2,
                            ),
                          ),
                          child: Text(
                            c,
                            style: TextStyle(
                              color: sel
                                  ? Colors.white
                                  : (isDark ? Colors.white70 : Colors.black87),
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
              // Wallet address
              if (wallet.isNotEmpty) ...[
                _SectionLabel(label: 'Send to $_coin Address', isDark: isDark),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                  child: GestureDetector(
                    onTap: () {
                      Clipboard.setData(ClipboardData(text: wallet));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Address copied!'),
                          duration: Duration(seconds: 2),
                        ),
                      );
                    },
                    child: Container(
                      padding: const EdgeInsets.all(13),
                      decoration: BoxDecoration(
                        color: isDark
                            ? const Color(0xFF0D1117)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              wallet,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Icon(Icons.copy, size: 16, color: Colors.amber),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
              // Amount note
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.info_outline,
                        color: Colors.amber,
                        size: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          price.isNotEmpty
                              ? 'Send exactly \$$price USD worth of $_coin to the address above.'
                              : 'Send the correct amount to the wallet address above.',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Colors.amber,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // TX Hash
              _SectionLabel(label: 'Transaction Hash / TXID', isDark: isDark),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: TextField(
                  controller: _txCtrl,
                  decoration: InputDecoration(
                    hintText: '0x…',
                    filled: true,
                    fillColor: isDark
                        ? const Color(0xFF0D1117)
                        : Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    prefixIcon: Icon(Icons.tag, color: Colors.amber.shade700),
                  ),
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ),
              // Proof image
              _SectionLabel(
                label: 'Proof Screenshot (Optional)',
                isDark: isDark,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                child: GestureDetector(
                  onTap: _pickProof,
                  child: Container(
                    height: 80,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF0D1117)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _proofPath != null
                            ? Colors.amber.shade600
                            : Colors.grey.withValues(alpha: 0.3),
                      ),
                    ),
                    child: _proofPath != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(14),
                            child: Image.file(
                              File(_proofPath!),
                              fit: BoxFit.cover,
                            ),
                          )
                        : Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.upload_file,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Tap to upload screenshot',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade400,
                                ),
                              ),
                            ],
                          ),
                  ),
                ),
              ),
              // Submit
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                child: SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber.shade700,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 4,
                    ),
                    icon: _submit
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2,
                            ),
                          )
                        : const Icon(Icons.send_rounded, color: Colors.white),
                    label: Text(
                      _submit ? 'Submitting…' : 'Submit for Verification',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                      ),
                    ),
                    onPressed: _submit ? null : _submitPayment,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─── BRAND DEFINITIONS ────────────────────────────────────────────────────────

enum _Brand { stripe, paypal, crypto, googlePlay, appStore }

class _MethodTile extends StatelessWidget {
  const _MethodTile({
    required this.brand,
    required this.isDark,
    required this.onTap,
  });
  final _Brand brand;
  final bool isDark;
  final VoidCallback onTap;

  static const _meta = {
    _Brand.stripe: (
      'Pay with Stripe',
      'Credit / Debit card',
      Color(0xFF6772E5),
      Icons.credit_card_rounded,
    ),
    _Brand.paypal: (
      'Pay with PayPal',
      'PayPal account or card',
      Color(0xFF003087),
      Icons.account_balance_wallet_rounded,
    ),
    _Brand.crypto: (
      'Pay with Crypto',
      'BTC / ETH / USDT',
      Color(0xFFF7931A),
      Icons.currency_bitcoin,
    ),
    _Brand.googlePlay: (
      'Google Play In-App',
      'Billed by Google Play',
      Color(0xFF4CAF50),
      Icons.android_rounded,
    ),
    _Brand.appStore: (
      'App Store In-App',
      'Billed by Apple App Store',
      Color(0xFF007AFF),
      Icons.apple_rounded,
    ),
  };

  @override
  Widget build(BuildContext context) {
    final (label, sub, color, icon) = _meta[brand]!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                      ),
                    ),
                    Text(
                      sub,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: Colors.grey.shade400,
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─── SHARED SHEET COMPONENTS ──────────────────────────────────────────────────

class _Sheet extends StatelessWidget {
  const _Sheet({
    required this.isDark,
    required this.child,
    this.maxFraction = 0.72,
  });
  final bool isDark;
  final Widget child;
  final double maxFraction;
  @override
  Widget build(BuildContext context) {
    final maxH = MediaQuery.of(context).size.height * maxFraction;
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxH),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161B22) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
        ),
        child: child,
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle({required this.isDark});
  final bool isDark;
  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      width: 40,
      height: 4,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}

class _SheetTitle extends StatelessWidget {
  const _SheetTitle({
    required this.title,
    required this.subtitle,
    required this.isDark,
  });
  final String title;
  final String subtitle;
  final bool isDark;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 8, 20, 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: isDark ? Colors.white : const Color(0xFF1A1A2E),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
        ),
      ],
    ),
  );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.isDark});
  final String label;
  final bool isDark;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
    child: Text(
      label,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        color: isDark ? Colors.grey.shade300 : Colors.grey.shade700,
      ),
    ),
  );
}

class _Divider extends StatelessWidget {
  const _Divider({required this.isDark});
  final bool isDark;
  @override
  Widget build(BuildContext context) => Divider(
    height: 1,
    indent: 20,
    endIndent: 20,
    color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.grey.shade100,
  );
}

class _ErrorBar extends StatelessWidget {
  const _ErrorBar({required this.message, this.onDismiss});
  final String message;
  final VoidCallback? onDismiss;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red, fontSize: 13),
            ),
          ),
          if (onDismiss != null)
            GestureDetector(
              onTap: onDismiss,
              child: const Icon(Icons.close, color: Colors.red, size: 16),
            ),
        ],
      ),
    ),
  );
}

class _GreenBar extends StatelessWidget {
  const _GreenBar({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
    child: Container(
      padding: const EdgeInsets.all(14),
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.green.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.green.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: Colors.green, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(
                color: Colors.green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
