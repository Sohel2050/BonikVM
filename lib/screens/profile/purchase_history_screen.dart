import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../providers/subscription_provider.dart';
import '../../services/billing_service.dart';
import '../../shared/providers/app_providers.dart';

class PurchaseHistoryScreen extends ConsumerStatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  ConsumerState<PurchaseHistoryScreen> createState() =>
      _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends ConsumerState<PurchaseHistoryScreen> {
  List<Map<String, dynamic>> _purchases = [];
  Map<String, dynamic>? _subscriptionStatus;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPurchaseData();
  }

  Future<void> _loadPurchaseData() async {
    setState(() => _isLoading = true);

    try {
      final result = await BillingService().getReceipts();
      final subState = ref.read(subscriptionProvider);

      if (result['success'] == true) {
        final raw = (result['data']?['receipts'] as List? ?? [])
            .cast<Map<String, dynamic>>();
        // Map UserSubscription fields to the display format used by this screen
        final mapped = raw.map((r) {
          final isActive = r['is_active'] == true || r['is_active'] == 1;
          final paymentStatus = (r['payment_status'] ?? '').toString();
          final status = isActive
              ? 'active'
              : (paymentStatus.isEmpty ? 'expired' : paymentStatus);
          final source = (r['plan_source'] ?? r['source'] ?? '')
              .toString()
              .toLowerCase();
          return <String, dynamic>{
            'id': r['id'],
            'subscription_id': r['id'],
            'product_name': r['plan'] ?? r['product_id'] ?? 'Premium',
            'product_id': r['product_id'],
            'amount': r['amount_paid'] ?? r['amount'],
            'currency': r['currency'] ?? 'USD',
            'status': status,
            'payment_gateway': source,
            'platform': source,
            'transaction_id': r['transaction_id'],
            'starts_at': r['starts_at'],
            'expires_at': r['expires_at'],
            'plan': r['plan'],
            'plan_type': r['plan'],
          };
        }).toList();

        // Build subscription status from subscriptionProvider or first active receipt
        Map<String, dynamic>? statusMap;
        if (subState.isPremium && subState.subscription != null) {
          statusMap = {
            'active': true,
            'expires_at': subState.subscription!['expires_at'],
            'plan':
                subState.subscription!['benefits']?['name'] ??
                subState.subscription!['product_id'],
          };
        } else if (mapped.any((r) => r['status'] == 'active')) {
          final active = mapped.firstWhere((r) => r['status'] == 'active');
          statusMap = {
            'active': true,
            'expires_at': active['expires_at'],
            'plan': active['plan'],
          };
        }

        setState(() {
          _purchases = mapped;
          _subscriptionStatus = statusMap;
          _isLoading = false;
        });
      } else {
        setState(() {
          _purchases = [];
          _isLoading = false;
        });
      }

      final isPremium = _subscriptionStatus?['active'] ?? false;
      ref.read(premiumStatusProvider.notifier).setPremiumStatus(isPremium);
    } catch (e) {
      setState(() => _isLoading = false);
      _showError('Failed to load purchase data: $e');
    }
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateString);
      final d = date.day.toString().padLeft(2, '0');
      final m = date.month.toString().padLeft(2, '0');
      final y = date.year.toString();
      return '$d/$m/$y';
    } catch (_) {
      return dateString;
    }
  }

  MaterialColor _statusColor(String status) {
    switch ((status).toString().toLowerCase()) {
      case 'active':
      case 'completed':
        return Colors.green;
      case 'expired':
      case 'failed':
      case 'cancelled':
        return Colors.red;
      case 'pending':
        return Colors.orange;
      default:
        return Colors.grey;
    }
  }

  String _formatAmount(Map<String, dynamic> p) {
    final currency = (p['currency'] ?? '').toString().trim();
    final amount = p['amount'];
    final paymentGateway = (p['payment_gateway'] ?? '')
        .toString()
        .toLowerCase();

    // For voucher purchases, show "Redeemed"
    if (paymentGateway == 'voucher' || (amount is num && amount == 0)) {
      return 'Redeemed';
    }

    String amtStr;
    if (amount is num) {
      amtStr = amount.toStringAsFixed(amount % 1 == 0 ? 0 : 2);
    } else {
      amtStr = (amount ?? '').toString();
    }
    if (currency.isEmpty && amtStr.isEmpty) return '—';
    if (currency.isEmpty) return amtStr;
    if (amtStr.isEmpty) return currency;
    return '$currency $amtStr';
  }

  Chip _statusChip(String? status) {
    final st = (status ?? 'unknown');
    final c = _statusColor(st);
    return Chip(
      label: Text(
        st.toUpperCase(),
        style: TextStyle(
          color: c.shade900,
          fontWeight: FontWeight.w600,
          fontSize: 11,
        ),
      ),
      side: BorderSide(color: c.shade200),
      backgroundColor: c.shade50,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bg = isDark ? const Color(0xFF0F172A) : Colors.grey[50];
    final card = isDark ? const Color(0xFF1E293B) : Colors.white;
    final textPrimary = isDark ? Colors.white : Colors.black;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: const Text('Purchase History'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          IconButton(
            icon: _isLoading
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _loadPurchaseData,
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: user == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: 64, color: Colors.grey[400]),
                  const SizedBox(height: 16),
                  Text(
                    'Please sign in to view your purchases',
                    style: TextStyle(fontSize: 18, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _loadPurchaseData,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // User Info Card
                    Card(
                      color: card,
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 30,
                              backgroundImage: user.photoURL != null
                                  ? NetworkImage(user.photoURL!)
                                  : null,
                              child: user.photoURL == null
                                  ? Text(
                                      (user.displayName?.isNotEmpty == true
                                              ? user.displayName!.substring(
                                                  0,
                                                  1,
                                                )
                                              : 'U')
                                          .toUpperCase(),
                                      style: const TextStyle(fontSize: 24),
                                    )
                                  : null,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.displayName ?? 'User',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    user.email ?? '',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 16),

                    // Subscription Status
                    if (_subscriptionStatus != null) ...[
                      Text(
                        'Current Subscription',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: textPrimary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Card(
                        color: card,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color:
                                      (_subscriptionStatus!['active'] == true
                                              ? Colors.green
                                              : Colors.red)
                                          .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Icon(
                                  _subscriptionStatus!['active'] == true
                                      ? Icons.check_circle
                                      : Icons.cancel,
                                  color: _subscriptionStatus!['active'] == true
                                      ? Colors.green
                                      : Colors.red,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _subscriptionStatus!['active'] == true
                                          ? 'Premium Active'
                                          : 'No Active Subscription',
                                      style: TextStyle(
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold,
                                        color: textPrimary,
                                      ),
                                    ),
                                    if (_subscriptionStatus!['expires_at'] !=
                                        null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        'Expires: ${_formatDate(_subscriptionStatus!['expires_at'])}',
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],

                    // Purchase History
                    Text(
                      'Purchase History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),

                    if (_isLoading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(24.0),
                          child: CircularProgressIndicator(),
                        ),
                      )
                    else if (_purchases.isEmpty)
                      Card(
                        color: card,
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(
                                Icons.shopping_cart_outlined,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              Text(
                                'No Purchases Yet',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.grey[600],
                                ),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Your purchase history will appear here once you make a purchase.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey[500]),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      ListView.separated(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _purchases.length,
                        separatorBuilder: (context, index) =>
                            const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final p = _purchases[index];

                          // For display purposes:
                          // - If it's a voucher (amount = 0 or payment_gateway = voucher), show "Voucher"
                          // - Otherwise show the product name
                          final paymentGateway = (p['payment_gateway'] ?? '')
                              .toString()
                              .toLowerCase();
                          final rawAmount = p['amount'];
                          final isVoucher =
                              paymentGateway == 'voucher' ||
                              (rawAmount is num && rawAmount == 0);

                          final product = isVoucher
                              ? 'Voucher'
                              : (p['product_name'] ??
                                        p['product_id'] ??
                                        'Unknown Product')
                                    .toString();
                          final amount = _formatAmount(p);
                          final txn = (p['transaction_id'] ?? p['id'] ?? '')
                              .toString();
                          final originalStatus = (p['status'] ?? 'unknown')
                              .toString();
                          final platform = (p['platform'] ?? '').toString();

                          // Backend now returns 'cancelled' for deactivated vouchers,
                          // so we don't need special handling here
                          final status = originalStatus;

                          final cancellable =
                              originalStatus.toLowerCase() == 'active' &&
                              platform == 'android';

                          final itemCard = Card(
                            color: card,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // LINE 1: Plan • Amount (inline)
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Container(
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Colors.blue.withValues(
                                            alpha: 0.12,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: const Icon(
                                          Icons.shopping_bag,
                                          color: Colors.blue,
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Text(
                                          amount.trim().isEmpty
                                              ? product
                                              : '$product • $amount',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w700,
                                            color: textPrimary,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),

                                  // LINE 2: Transaction ID
                                  if (txn.isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    Row(
                                      children: [
                                        Text(
                                          'Transaction ID: ',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.grey[600],
                                          ),
                                        ),
                                        Expanded(
                                          child: Text(
                                            txn,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontFamily: 'monospace',
                                              color: Colors.grey[500],
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        IconButton(
                                          tooltip: 'Copy',
                                          splashRadius: 20,
                                          icon: const Icon(
                                            Icons.copy,
                                            size: 16,
                                          ),
                                          color: Colors.grey[500],
                                          onPressed: () async {
                                            final messenger =
                                                ScaffoldMessenger.of(context);
                                            await Clipboard.setData(
                                              ClipboardData(text: txn),
                                            );
                                            messenger.showSnackBar(
                                              const SnackBar(
                                                content: Text(
                                                  'Transaction ID copied',
                                                ),
                                              ),
                                            );
                                          },
                                        ),
                                      ],
                                    ),
                                  ],

                                  // LINE 3: View Receipt + Status (inline) (+ optional Cancel via long-press)
                                  const SizedBox(height: 10),
                                  Row(
                                    children: [
                                      _pillButton(
                                        label: 'View Receipt',
                                        icon: Icons.receipt_long,
                                        fg: Colors.blue,
                                        onTap: () => _viewReceipt(p),
                                      ),
                                      const SizedBox(width: 10),
                                      _statusChip(status),
                                      const Spacer(),
                                      if (cancellable)
                                        // Long-press to cancel; tap shows hint.
                                        GestureDetector(
                                          onLongPress: () =>
                                              _showCancelSubscriptionDialog(p),
                                          child: TextButton.icon(
                                            onPressed: _showHoldToCancelHint,
                                            icon: const Icon(
                                              Icons.cancel,
                                              size: 16,
                                            ),
                                            label: const Text('Cancel'),
                                            style: TextButton.styleFrom(
                                              foregroundColor: Colors.red,
                                              textStyle: const TextStyle(
                                                fontSize: 12,
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
                          );

                          // Long-press anywhere on card to trigger cancel (if eligible)
                          return GestureDetector(
                            onLongPress: cancellable
                                ? () => _showCancelSubscriptionDialog(p)
                                : null,
                            child: itemCard,
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
    );
  }

  // ---------- Hold-to-cancel hint ----------
  void _showHoldToCancelHint() {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.of(context);
    messenger.removeCurrentSnackBar();
    messenger.showSnackBar(
      const SnackBar(
        content: Text('Press and hold to cancel'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  // ---------- Modern Cancel Subscription Dialog (with "Deny") ----------

  void _showCancelSubscriptionDialog(Map<String, dynamic> purchase) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
          actionsPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          title: Row(
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.all(8),
                child: const Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Cancel Subscription',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'Are you sure you want to cancel your subscription for '
            '${purchase['plan_type'] ?? purchase['product_name'] ?? 'this plan'}?',
            style: TextStyle(color: isDark ? Colors.white70 : Colors.black87),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Deny',
                style: TextStyle(
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
              ),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.of(context).pop();
                await _cancelSubscription(purchase);
              },
              icon: const Icon(Icons.cancel),
              label: const Text('Cancel Subscription'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _cancelSubscription(Map<String, dynamic> purchase) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );

      await BillingService().cancelSubscription();
      // Refresh subscription state
      await ref.read(subscriptionProvider.notifier).refresh();

      if (!mounted) return;
      if (Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Subscription cancelled successfully'),
          backgroundColor: Colors.green,
        ),
      );
      _loadPurchaseData();
    } catch (e) {
      if (mounted && Navigator.canPop(context)) {
        Navigator.of(context).pop();
      }
      _showErrorSnackbar('Error: ${e.toString()}');
    }
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ---------- Modern Receipt View (Bottom Sheet) ----------

  void _viewReceipt(Map<String, dynamic> t) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF0B1220) : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final status = (t['status'] ?? 'unknown').toString();
        final statusClr = _statusColor(status);
        final amount = _formatAmount(t);
        final voucherInfo = t['voucher_info'] as Map<String, dynamic>?;

        // Determine if this is a voucher transaction
        final paymentGateway = (t['payment_gateway'] ?? '')
            .toString()
            .toLowerCase();
        final rawAmount = t['amount'];
        final isVoucher =
            paymentGateway == 'voucher' || (rawAmount is num && rawAmount == 0);
        final isVoucherDeactivated =
            voucherInfo != null && voucherInfo['deactivated'] == true;

        final product = isVoucher
            ? 'Voucher'
            : (t['product_name'] ?? t['product_id'] ?? 'Unknown Product')
                  .toString();
        final txnId = (t['transaction_id'] ?? t['id'] ?? 'N/A').toString();

        return SafeArea(
          child: DraggableScrollableSheet(
            expand: false,
            initialChildSize: 0.6,
            minChildSize: 0.4,
            maxChildSize: 0.95,
            builder: (_, controller) {
              return SingleChildScrollView(
                controller: controller,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Drag handle
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.white24 : Colors.black12,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // Header row
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: Colors.blue.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: const Icon(
                              Icons.receipt_long,
                              color: Colors.blue,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Transaction Receipt',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w700,
                                    color: isDark ? Colors.white : Colors.black,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: -6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Chip(
                                      label: Text(
                                        status.toUpperCase(),
                                        style: TextStyle(
                                          color: statusClr.shade900,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                        ),
                                      ),
                                      side: BorderSide(
                                        color: statusClr.shade200,
                                      ),
                                      backgroundColor: statusClr.shade50,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    Chip(
                                      label: Text(
                                        amount.isEmpty ? '—' : amount,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          fontSize: 11,
                                        ),
                                      ),
                                      side: BorderSide(
                                        color: (isDark
                                            ? Colors.white12
                                            : Colors.black12),
                                      ),
                                      backgroundColor: isDark
                                          ? Colors.white10
                                          : Colors.black12,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      visualDensity: VisualDensity.compact,
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Copy summary',
                            icon: const Icon(Icons.copy),
                            onPressed: () async {
                              final messenger = ScaffoldMessenger.of(context);
                              await Clipboard.setData(
                                ClipboardData(text: _generateReceiptText(t)),
                              );
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Receipt summary copied'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),

                      const SizedBox(height: 16),
                      Divider(color: isDark ? Colors.white12 : Colors.black12),

                      // Key fields
                      _receiptTile('Transaction ID', txnId, copyable: true),
                      _receiptTile('Product', product),
                      _receiptTile('Amount', amount),
                      _receiptTile(
                        'Currency',
                        (t['currency'] ?? 'N/A').toString(),
                      ),
                      _receiptTile('Status', status.toUpperCase()),
                      _receiptTile(
                        'Payment Method',
                        (t['payment_method'] ?? 'N/A').toString(),
                      ),
                      // Show voucher deactivation info if applicable
                      if (isVoucherDeactivated)
                        _receiptTile('Voucher Status', 'DEACTIVATED'),
                      _receiptTile(
                        'Purchase Date',
                        _formatDate((t['created_at'] ?? 'N/A').toString()),
                      ),
                      if (t['order_id'] != null)
                        _receiptTile('Order ID', t['order_id'].toString()),
                      if (t['transaction_id'] != null)
                        _receiptTile(
                          'Transaction Reference',
                          t['transaction_id'].toString(),
                        ),
                      if (t['purchase_token'] != null)
                        _receiptTile(
                          'Purchase Token',
                          t['purchase_token'].toString(),
                          copyable: true,
                        ),

                      const SizedBox(height: 12),
                      Divider(color: isDark ? Colors.white12 : Colors.black12),
                      const SizedBox(height: 8),

                      // Bottom actions
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () async {
                                await Clipboard.setData(
                                  ClipboardData(text: _generateReceiptText(t)),
                                );
                                if (!mounted) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text(
                                      'Receipt copied to clipboard',
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.copy),
                              label: const Text('Copy Receipt'),
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: const Icon(Icons.check_circle_outline),
                              label: const Text('Done'),
                              style: ElevatedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _receiptTile(String label, String value, {bool copyable = false}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 140,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
                fontFamily:
                    (label.toLowerCase().contains('id') ||
                        label.toLowerCase().contains('token'))
                    ? 'monospace'
                    : null,
              ),
            ),
          ),
          if (copyable)
            IconButton(
              tooltip: 'Copy',
              icon: const Icon(Icons.copy, size: 18),
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: value));
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(SnackBar(content: Text('$label copied')));
              },
            ),
        ],
      ),
    );
  }

  String _generateReceiptText(Map<String, dynamic> t) {
    // Determine if this is a voucher transaction
    final paymentGateway = (t['payment_gateway'] ?? '')
        .toString()
        .toLowerCase();
    final rawAmount = t['amount'];
    final isVoucher =
        paymentGateway == 'voucher' || (rawAmount is num && rawAmount == 0);

    final productDisplay = isVoucher
        ? 'Voucher'
        : (t['product_name'] ?? t['product_id'] ?? 'N/A').toString();

    final paymentMethodDisplay = isVoucher
        ? 'Voucher'
        : (t['payment_method'] ?? t['payment_gateway'] ?? 'N/A').toString();

    return '''
Transaction Receipt
==================
Transaction ID: ${(t['id'] ?? t['transaction_id'] ?? 'N/A').toString()}
Product: $productDisplay
Amount: ${_formatAmount(t)}
Currency: ${(t['currency'] ?? 'N/A').toString()}
Status: ${(t['status'] ?? 'N/A').toString()}
Payment Method: $paymentMethodDisplay
Purchase Date: ${_formatDate((t['created_at'] ?? 'N/A').toString())}
Order ID: ${(t['order_id'] ?? 'N/A').toString()}
Transaction Reference: ${(t['transaction_id'] ?? 'N/A').toString()}
Purchase Token: ${(t['purchase_token'] ?? 'N/A').toString()}
==================
Generated on: ${DateTime.now()}
''';
  }

  // ---------- Small UI Helpers ----------

  Widget _pillButton({
    required String label,
    required IconData icon,
    required Color fg,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: fg.withValues(alpha: 0.1),
          border: Border.all(color: fg.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: fg),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: .2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
