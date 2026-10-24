import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

Future<bool?> showStripeCardInputSheet({
  required BuildContext context,
  required Function(PaymentMethod?) onPaymentMethodCreated,
  String? clientSecret,
  required double amount,
  required String currency,
  required String planName,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    isDismissible: true,
    enableDrag: true,
    builder: (context) => StripeCardInputSheet(
      onPaymentMethodCreated: onPaymentMethodCreated,
      clientSecret: clientSecret,
      amount: amount,
      currency: currency,
      planName: planName,
    ),
  );
}

class StripeCardInputSheet extends StatefulWidget {
  final Function(PaymentMethod?) onPaymentMethodCreated;
  final String? clientSecret;
  final double amount;
  final String currency;
  final String planName;

  const StripeCardInputSheet({
    super.key,
    required this.onPaymentMethodCreated,
    this.clientSecret,
    required this.amount,
    required this.currency,
    required this.planName,
  });

  @override
  State<StripeCardInputSheet> createState() => _StripeCardInputSheetState();
}

class _StripeCardInputSheetState extends State<StripeCardInputSheet> {
  final CardFormEditController _controller = CardFormEditController();

  bool _isProcessing = false;
  bool _isCardComplete = false;
  String? _lastError;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onCardChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onCardChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onCardChanged() {
    final details = _controller.details;
    setState(() {
      _isCardComplete = details.complete;
      _lastError = null;
    });
  }

  Future<void> _processPayment() async {
    if (!_isCardComplete || _isProcessing) return;

    HapticFeedback.selectionClick();
    setState(() {
      _isProcessing = true;
      _lastError = null;
    });

    try {
      if (widget.clientSecret != null) {
        await Stripe.instance.confirmPayment(
          paymentIntentClientSecret: widget.clientSecret!,
          data: const PaymentMethodParams.card(
            paymentMethodData: PaymentMethodData(),
          ),
        );

        if (!mounted) return;
        HapticFeedback.lightImpact();
        widget.onPaymentMethodCreated(null);
        Navigator.of(context).pop(true);
      } else {
        final pm = await Stripe.instance.createPaymentMethod(
          params: const PaymentMethodParams.card(
            paymentMethodData: PaymentMethodData(),
          ),
        );

        if (!mounted) return;
        HapticFeedback.lightImpact();
        widget.onPaymentMethodCreated(pm);
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      final msg = e.toString();
      if (msg.toLowerCase().contains('cancel')) {
        if (mounted) {
          Navigator.of(context).pop(false);
        }
      } else {
        setState(() => _lastError = msg);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Payment error: $msg'),
              backgroundColor: Colors.red,
            ),
          );
          HapticFeedback.heavyImpact();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isProcessing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;

    return PopScope(
      canPop: !_isProcessing,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Content
            Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.credit_card,
                          color: Color(0xFF10B981),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Enter Card Details',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.lock,
                                  size: 14,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'Secure payment',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // Plan summary
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.planName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: isDark ? Colors.white : Colors.black87,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'VPN Subscription',
                                style: TextStyle(
                                  fontSize: 13,
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF10B981),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${widget.currency.toUpperCase()} ${widget.amount.toStringAsFixed(2)}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Card form
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark
                          ? const Color(0xFF334155)
                          : const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: CardFormField(
                      controller: _controller,
                      enablePostalCode: false,
                      countryCode: 'US',
                      style: CardFormStyle(
                        backgroundColor: Colors.transparent,
                        textColor: isDark ? Colors.white : Colors.black87,
                        fontSize: 16,
                        placeholderColor: isDark
                            ? Colors.grey[500]
                            : Colors.grey[400],
                        borderRadius: 0,
                        borderWidth: 0,
                        borderColor: Colors.transparent,
                        cursorColor: const Color(0xFF10B981),
                      ),
                    ),
                  ),

                  if (_lastError != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.error_outline,
                            color: Colors.red,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lastError!,
                              style: const TextStyle(
                                color: Colors.red,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],

                  const SizedBox(height: 24),

                  // Pay button
                  SizedBox(
                    width: double.infinity,
                    height: 54,
                    child: ElevatedButton(
                      onPressed: (_isCardComplete && !_isProcessing)
                          ? _processPayment
                          : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF10B981),
                        disabledBackgroundColor: isDark
                            ? Colors.grey[800]
                            : Colors.grey[300],
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      child: _isProcessing
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : Text(
                              'Pay ${widget.currency.toUpperCase()} ${widget.amount.toStringAsFixed(2)}',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // Cancel button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: _isProcessing
                          ? null
                          : () => Navigator.of(context).pop(false),
                      child: Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: bottomPadding > 0 ? bottomPadding : 8),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
