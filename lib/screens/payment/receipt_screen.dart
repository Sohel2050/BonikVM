import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:share_plus/share_plus.dart';
import '../../shared/providers/theme_provider.dart';

class ReceiptScreen extends ConsumerStatefulWidget {
  final Map<String, dynamic> receiptData;
  final String planName;

  const ReceiptScreen({
    Key? key,
    required this.receiptData,
    required this.planName,
  }) : super(key: key);

  @override
  ConsumerState<ReceiptScreen> createState() => _ReceiptScreenState();
}

class _ReceiptScreenState extends ConsumerState<ReceiptScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _setupAnimations();
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
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

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    final themeColor = ref.watch(themeColorProvider);
    final isDarkMode =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    return Scaffold(
      backgroundColor: isDarkMode ? const Color(0xFF0F172A) : Colors.grey[50],
      appBar: AppBar(
        title: const Text('Payment Receipt'),
        backgroundColor: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        foregroundColor: isDarkMode ? Colors.white : Colors.black,
        elevation: 0,
        actions: [
          IconButton(icon: const Icon(Icons.share), onPressed: _shareReceipt),
        ],
      ),
      body: AnimatedBuilder(
        animation: _animationController,
        builder: (context, child) {
          return FadeTransition(
            opacity: _fadeAnimation,
            child: SlideTransition(
              position: _slideAnimation,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    // Success Header
                    _buildSuccessHeader(isDarkMode, themeColor),

                    const SizedBox(height: 32),

                    // Receipt Card
                    _buildReceiptCard(isDarkMode, themeColor),

                    const SizedBox(height: 32),

                    // Action Buttons
                    _buildActionButtons(isDarkMode, themeColor),

                    const SizedBox(height: 20),

                    // Footer Note
                    _buildFooterNote(isDarkMode),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSuccessHeader(bool isDarkMode, Color themeColor) {
    return FadeInUp(
      delay: const Duration(milliseconds: 200),
      child: Column(
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [themeColor, themeColor.withValues(alpha: 0.7)],
              ),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check, color: Colors.white, size: 50),
          ),
          const SizedBox(height: 24),
          Text(
            'Payment Successful!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.bold,
              color: isDarkMode ? Colors.white : Colors.black,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Welcome to ${widget.planName}',
            style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Resolves a receipt field by trying multiple possible key names.
  String? _receiptField(List<String> keys) {
    for (final key in keys) {
      final v = widget.receiptData[key];
      if (v != null && v.toString().isNotEmpty) return v.toString();
    }
    return null;
  }

  Widget _buildReceiptCard(bool isDarkMode, Color themeColor) {
    // Resolve receipt number from any of the possible key names backends use.
    final receiptNumber = _receiptField(['receipt_number', 'receipt_id', 'id']);
    // Resolve date from created_at OR purchase_date (backend uses both).
    final dateString = _receiptField([
      'created_at',
      'purchase_date',
      'payment_date',
    ]);

    return FadeInUp(
      delay: const Duration(milliseconds: 400),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 20,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Receipt Header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Receipt',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.white : Colors.black,
                  ),
                ),
                Text(
                  '#${receiptNumber ?? 'N/A'}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: themeColor,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 24),

            // Receipt Details
            _buildReceiptRow('Date', _formatDate(dateString), isDarkMode),
            _buildReceiptRow('Plan', widget.planName, isDarkMode),
            _buildReceiptRow(
              'Payment Method',
              _getPaymentMethodName(widget.receiptData['payment_method']),
              isDarkMode,
            ),
            _buildReceiptRow(
              'Transaction ID',
              widget.receiptData['transaction_id'] ?? 'N/A',
              isDarkMode,
            ),

            const SizedBox(height: 16),

            Divider(color: Colors.grey[300]),

            const SizedBox(height: 16),

            // Amount Section
            _buildReceiptRow(
              'Subtotal',
              '${widget.receiptData['currency'] ?? 'USD'} ${widget.receiptData['amount'] ?? '0.00'}',
              isDarkMode,
            ),

            if (widget.receiptData['tax_amount'] != null &&
                widget.receiptData['tax_amount'] > 0)
              _buildReceiptRow(
                'Tax',
                '${widget.receiptData['currency'] ?? 'USD'} ${widget.receiptData['tax_amount']}',
                isDarkMode,
              ),

            const SizedBox(height: 12),

            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: themeColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Total',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black,
                    ),
                  ),
                  Text(
                    '${widget.receiptData['currency'] ?? 'USD'} ${widget.receiptData['total_amount'] ?? widget.receiptData['amount'] ?? '0.00'}',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: themeColor,
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // Billing Info
            if (widget.receiptData['billing_info'] != null) ...[
              Text(
                'Billing Information',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: isDarkMode ? Colors.white : Colors.black,
                ),
              ),
              const SizedBox(height: 12),
              _buildReceiptRow(
                'Name',
                widget.receiptData['billing_info']['name'] ?? 'N/A',
                isDarkMode,
              ),
              _buildReceiptRow(
                'Email',
                widget.receiptData['billing_info']['email'] ?? 'N/A',
                isDarkMode,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptRow(String label, String value, bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 14, color: Colors.grey[600])),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: isDarkMode ? Colors.white : Colors.black,
              ),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(bool isDarkMode, Color themeColor) {
    return FadeInUp(
      delay: const Duration(milliseconds: 600),
      child: Column(
        children: [
          // Download Receipt Button
          // SizedBox(
          //   width: double.infinity,
          //   height: 52,
          //   child: ElevatedButton.icon(
          //     onPressed: _downloadReceipt,
          //     icon: const Icon(Icons.download),
          //     label: const Text('Download Receipt'),
          //     style: ElevatedButton.styleFrom(
          //       backgroundColor: themeColor,
          //       foregroundColor: Colors.white,
          //       shape: RoundedRectangleBorder(
          //         borderRadius: BorderRadius.circular(12),
          //       ),
          //     ),
          //   ),
          // ),

          // const SizedBox(height: 12),

          // Email Receipt Button
          // SizedBox(
          //   width: double.infinity,
          //   height: 52,
          //   child: OutlinedButton.icon(
          //     onPressed: _emailReceipt,
          //     icon: const Icon(Icons.email),
          //     label: const Text('Email Receipt'),
          //     style: OutlinedButton.styleFrom(
          //       foregroundColor: themeColor,
          //       side: BorderSide(color: themeColor),
          //       shape: RoundedRectangleBorder(
          //         borderRadius: BorderRadius.circular(12),
          //       ),
          //     ),
          //   ),
          // ),
          const SizedBox(height: 12),

          // Continue Button
          SizedBox(
            width: double.infinity,
            height: 52,
            child: TextButton(
              onPressed: () {
                // Navigate back to main app home screen
                Navigator.of(context).pushNamedAndRemoveUntil(
                  '/home', // Main app route
                  (route) => false, // Remove all previous routes
                );
              },
              child: Text(
                'Continue to App',
                style: TextStyle(
                  color: themeColor,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooterNote(bool isDarkMode) {
    return FadeInUp(
      delay: const Duration(milliseconds: 800),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isDarkMode
              ? const Color(0xFF1E293B).withValues(alpha: 0.5)
              : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.info_outline, color: Colors.grey[600], size: 20),
            const SizedBox(height: 8),
            Text(
              'This is your official receipt for tax and accounting purposes. Keep it for your records.',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(String? dateString) {
    if (dateString == null) return 'N/A';
    try {
      final date = DateTime.parse(dateString);
      return '${date.day}/${date.month}/${date.year} at ${date.hour}:${date.minute.toString().padLeft(2, '0')}';
    } catch (e) {
      return dateString;
    }
  }

  String _getPaymentMethodName(String? method) {
    switch (method) {
      case 'google_play':
      case 'iap':
        return 'Google Play Store';
      case 'app_store':
        return 'App Store';
      case 'paypal':
        return 'PayPal';
      case 'stripe':
        return 'Credit/Debit Card';
      case 'voucher':
      case 'Voucher Code':
        return 'voucher';
      default:
        return method ?? 'Unknown';
    }
  }

  void _shareReceipt() {
    final receiptNumber = _receiptField(['receipt_number', 'receipt_id', 'id']);
    final dateString = _receiptField([
      'created_at',
      'purchase_date',
      'payment_date',
    ]);
    final receiptText =
        '''
VPN MASTER Premium - Payment Receipt

Receipt #: ${receiptNumber ?? 'N/A'}
Date: ${_formatDate(dateString)}
Plan: ${widget.planName}
Payment Method: ${_getPaymentMethodName(widget.receiptData['payment_method'])}
Transaction ID: ${widget.receiptData['transaction_id'] ?? 'N/A'}

Amount: ${widget.receiptData['currency'] ?? 'USD'} ${widget.receiptData['amount'] ?? '0.00'}
Total: ${widget.receiptData['currency'] ?? 'USD'} ${widget.receiptData['total_amount'] ?? widget.receiptData['amount'] ?? '0.00'}

Thank you for your purchase!
    ''';

    Share.share(receiptText, subject: 'VPN MASTER Payment Receipt');
  }

  void _downloadReceipt() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Receipt download started...'),
        backgroundColor: Colors.green,
      ),
    );
    // TODO: Implement actual PDF download functionality
  }

  void _emailReceipt() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Receipt sent to your email!'),
        backgroundColor: Colors.blue,
      ),
    );
    // TODO: Implement email functionality
  }
}
