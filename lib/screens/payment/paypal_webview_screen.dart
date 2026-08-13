import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class PayPalWebViewScreen extends StatefulWidget {
  final String approvalUrl;
  final String orderId;
  final Function(bool success, String? transactionId) onPaymentComplete;

  const PayPalWebViewScreen({
    Key? key,
    required this.approvalUrl,
    required this.orderId,
    required this.onPaymentComplete,
  }) : super(key: key);

  @override
  State<PayPalWebViewScreen> createState() => _PayPalWebViewScreenState();
}

class _PayPalWebViewScreenState extends State<PayPalWebViewScreen> {
  late final WebViewController _controller;
  bool _isLoading = true;
  bool _paymentProcessed = false;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
  }

  void _initializeWebView() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            if (progress == 100) {
              setState(() {
                _isLoading = false;
              });
            }
          },
          onPageStarted: (String url) {
            _checkForReturnUrl(url);
          },
          onPageFinished: (String url) {
            _checkForReturnUrl(url);
          },
          onNavigationRequest: (NavigationRequest request) {
            _checkForReturnUrl(request.url);
            return NavigationDecision.navigate;
          },
        ),
      )
      ..loadRequest(Uri.parse(widget.approvalUrl));
  }

  void _checkForReturnUrl(String url) {
    if (_paymentProcessed) return;

    // Match our specific server return path OR PayerID query param (only present after real approval)
    // Avoid broad checks like url.contains('success') which fire on intermediate PayPal pages.
    final isSuccess =
        url.contains('/payments/paypal/success') ||
        url.contains('axevpn://payment/success') ||
        (url.contains('PayerID=') && !url.contains('cancel'));

    final isCancel =
        url.contains('/payments/paypal/cancel') ||
        url.contains('axevpn://payment/cancel') ||
        url.contains('paypal.com/checkoutnow/error');

    if (isSuccess) {
      _paymentProcessed = true;
      _handlePaymentComplete(true);
    } else if (isCancel) {
      _paymentProcessed = true;
      _handlePaymentComplete(false);
    }
  }

  void _handlePaymentComplete(bool success) {
    if (!mounted) return;

    // Close the WebView and return result to the caller
    Navigator.of(context).pop(success);

    // Call the completion callback
    widget.onPaymentComplete(success, success ? widget.orderId : null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PayPal Payment'),
        backgroundColor: const Color(0xFF003087), // PayPal blue
        foregroundColor: Colors.white,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            // User manually closed - treat as cancelled
            if (!_paymentProcessed) {
              _paymentProcessed = true;
              Navigator.of(context).pop();
              widget.onPaymentComplete(false, null);
            }
          },
        ),
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_isLoading)
            Container(
              color: Colors.white,
              child: const Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(
                        Color(0xFF003087),
                      ),
                    ),
                    SizedBox(height: 16),
                    Text(
                      'Loading PayPal...',
                      style: TextStyle(fontSize: 16, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
