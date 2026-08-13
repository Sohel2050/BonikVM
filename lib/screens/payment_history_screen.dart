import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:intl/intl.dart';
import '../core/api/api_service.dart';
import '../providers/auth_providers.dart';

class PaymentHistoryScreen extends ConsumerStatefulWidget {
  const PaymentHistoryScreen({Key? key}) : super(key: key);

  @override
  ConsumerState<PaymentHistoryScreen> createState() =>
      _PaymentHistoryScreenState();
}

class _PaymentHistoryScreenState extends ConsumerState<PaymentHistoryScreen> {
  final ApiService _apiService = ApiService();
  List<Map<String, dynamic>> _receipts = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadPaymentHistory();
  }

  Future<void> _loadPaymentHistory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final currentUser = ref.read(currentUserProvider);
      if (currentUser == null) {
        setState(() {
          _errorMessage = 'Please sign in to view payment history';
          _isLoading = false;
        });
        return;
      }

      // For testing purposes, use the test Firebase UID we created
      // TODO: Replace with actual user UID once proper user authentication is implemented
      String testUserId = 'debug-test-firebase-uid-999';


      final result = await _apiService.getUserReceipts(userId: testUserId);

      if (result['success'] == true && result['data'] != null) {
        final receiptsData = result['data']['receipts'] ?? [];
        setState(() {
          _receipts = List<Map<String, dynamic>>.from(receiptsData);
          _isLoading = false;
        });

      } else {
        setState(() {
          _errorMessage = result['message'] ?? 'Failed to load payment history';
          _isLoading = false;
        });
      }
    } catch (e) {

      setState(() {
        _errorMessage = 'Error loading payment history: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshPaymentHistory() async {
    await _loadPaymentHistory();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF0F172A)
          : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: const Text('Payment History'),
        backgroundColor: isDark ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDark ? Colors.white : Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            onPressed: _refreshPaymentHistory,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _buildBody(isDark),
    );
  }

  Widget _buildBody(bool isDark) {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF10B981)),
        ),
      );
    }

    if (_errorMessage != null) {
      return _buildErrorState(isDark);
    }

    if (_receipts.isEmpty) {
      return _buildEmptyState(isDark);
    }

    return _buildReceiptsList(isDark);
  }

  Widget _buildErrorState(bool isDark) {
    return FadeIn(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 64, color: Colors.red[400]),
            const SizedBox(height: 16),
            Text(
              'Error Loading Payment History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey[600]),
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: _refreshPaymentHistory,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.white,
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(bool isDark) {
    return FadeIn(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.receipt_long_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No Payment History',
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your payment receipts will appear here',
              style: TextStyle(color: Colors.grey[600]),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptsList(bool isDark) {
    return RefreshIndicator(
      onRefresh: _refreshPaymentHistory,
      color: const Color(0xFF10B981),
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _receipts.length,
        itemBuilder: (context, index) {
          final receipt = _receipts[index];
          return FadeInUp(
            duration: Duration(milliseconds: 300 + (index * 100)),
            child: _buildReceiptCard(receipt, isDark),
          );
        },
      ),
    );
  }

  Widget _buildReceiptCard(Map<String, dynamic> receipt, bool isDark) {
    final amount = receipt['amount']?.toString() ?? '0.00';
    final currency = receipt['currency']?.toString() ?? 'USD';
    final paymentMethod = receipt['payment_method']?.toString() ?? 'Unknown';
    final planName = receipt['plan_name']?.toString() ?? 'VPN Subscription';
    final status = receipt['status']?.toString() ?? 'unknown';
    final createdAt = receipt['created_at']?.toString();

    DateTime? date;
    if (createdAt != null) {
      try {
        date = DateTime.parse(createdAt);
      } catch (e) {

      }
    }

    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.help_outline;

    switch (status.toLowerCase()) {
      case 'completed':
      case 'success':
        statusColor = Colors.green;
        statusIcon = Icons.check_circle;
        break;
      case 'pending':
        statusColor = Colors.orange;
        statusIcon = Icons.access_time;
        break;
      case 'failed':
      case 'error':
        statusColor = Colors.red;
        statusIcon = Icons.error;
        break;
      case 'cancelled':
        statusColor = Colors.grey;
        statusIcon = Icons.cancel;
        break;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with amount and status
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '$currency ${double.tryParse(amount)?.toStringAsFixed(2) ?? amount}',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(statusIcon, size: 14, color: statusColor),
                    const SizedBox(width: 4),
                    Text(
                      status.toUpperCase(),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Plan name
          Text(
            planName,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),

          const SizedBox(height: 8),

          // Payment method and date
          Row(
            children: [
              Icon(
                _getPaymentMethodIcon(paymentMethod),
                size: 16,
                color: Colors.grey[600],
              ),
              const SizedBox(width: 8),
              Text(
                _formatPaymentMethod(paymentMethod),
                style: TextStyle(color: Colors.grey[600], fontSize: 14),
              ),
              const Spacer(),
              if (date != null)
                Text(
                  DateFormat('MMM dd, yyyy').format(date),
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
            ],
          ),

          // Transaction ID if available
          if (receipt['transaction_id'] != null) ...[
            const SizedBox(height: 8),
            Text(
              'ID: ${receipt['transaction_id']}',
              style: TextStyle(
                color: Colors.grey[500],
                fontSize: 12,
                fontFamily: 'monospace',
              ),
            ),
          ],
        ],
      ),
    );
  }

  IconData _getPaymentMethodIcon(String paymentMethod) {
    switch (paymentMethod.toLowerCase()) {
      case 'stripe':
        return Icons.credit_card;
      case 'paypal':
        return Icons.account_balance_wallet;
      case 'iap':
      case 'in_app_purchase':
        return Icons.phone_android;
      case 'voucher':
      case 'voucher code':
        return Icons.card_giftcard;
      default:
        return Icons.payment;
    }
  }

  String _formatPaymentMethod(String paymentMethod) {
    switch (paymentMethod.toLowerCase()) {
      case 'stripe':
        return 'Credit Card';
      case 'paypal':
        return 'PayPal';
      case 'iap':
      case 'in_app_purchase':
        return 'In-App Purchase';
      case 'voucher':
      case 'voucher code':
        return 'voucher';
      default:
        return paymentMethod;
    }
  }
}

