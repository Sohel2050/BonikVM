// Windows checkout: webview_flutter has no Windows implementation, so
// Stripe/PayPal checkout opens in the system browser instead of an in-app
// WebView. There's no way to intercept the browser's navigation to detect
// the success redirect, so this polls subscription status in the
// background instead and shows a sheet the user can dismiss once done.
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/subscription_provider.dart';
import '../../core/services/admob_service.dart';

/// Opens [checkoutUrl] in the system browser, then polls subscription
/// status until it reflects a premium plan (or the user cancels). Returns
/// true if a premium subscription was detected within the timeout.
///
/// [onManualConfirm], if provided, is used by providers (PayPal) whose
/// payment isn't finalized just by the browser loading a return page —
/// it's called when the user taps "I've completed payment" and should
/// perform the actual capture/confirm API call. If it completes without
/// throwing, the sheet closes as successful immediately rather than
/// waiting for the next poll.
Future<bool> launchWindowsCheckoutAndWait({
  required BuildContext context,
  required WidgetRef ref,
  required String checkoutUrl,
  required String providerName,
  Future<void> Function()? onManualConfirm,
}) async {
  final launched = await launchUrl(
    Uri.parse(checkoutUrl),
    mode: LaunchMode.externalApplication,
  );
  if (!launched) return false;
  if (!context.mounted) return false;

  final wasPremiumBefore = ref.read(subscriptionProvider).isPremium;

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    isDismissible: true,
    enableDrag: true,
    builder: (_) => _WaitingForCheckoutSheet(
      providerName: providerName,
      wasPremiumBefore: wasPremiumBefore,
      onManualConfirm: onManualConfirm,
    ),
  );

  if (result == true) {
    await AdMobService.instance.refreshAdSettings();
  }
  return result == true;
}

class _WaitingForCheckoutSheet extends ConsumerStatefulWidget {
  const _WaitingForCheckoutSheet({
    required this.providerName,
    required this.wasPremiumBefore,
    this.onManualConfirm,
  });
  final String providerName;
  final bool wasPremiumBefore;
  final Future<void> Function()? onManualConfirm;

  @override
  ConsumerState<_WaitingForCheckoutSheet> createState() =>
      _WaitingForCheckoutSheetState();
}

class _WaitingForCheckoutSheetState
    extends ConsumerState<_WaitingForCheckoutSheet> {
  Timer? _poll;
  int _elapsedSeconds = 0;
  bool _confirming = false;
  String? _confirmError;
  static const _timeoutSeconds = 300; // 5 minutes

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 4), (_) => _check());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _manualConfirm() async {
    if (widget.onManualConfirm == null) return;
    setState(() {
      _confirming = true;
      _confirmError = null;
    });
    try {
      await widget.onManualConfirm!();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _confirming = false;
          _confirmError = 'Could not confirm payment: $e';
        });
      }
    }
  }

  Future<void> _check() async {
    _elapsedSeconds += 4;
    final authState = ref.read(subscriptionProvider.notifier);
    await authState.refresh();
    if (!mounted) return;

    final isPremiumNow = ref.read(subscriptionProvider).isPremium;
    if (isPremiumNow && !widget.wasPremiumBefore) {
      Navigator.of(context).pop(true);
      return;
    }
    if (_elapsedSeconds >= _timeoutSeconds) {
      _poll?.cancel();
      setState(() {}); // trigger rebuild to show the "still waiting" copy
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final timedOut = _elapsedSeconds >= _timeoutSeconds;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade700 : Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            if (!timedOut) ...[
              const SizedBox(
                width: 40,
                height: 40,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              const SizedBox(height: 20),
              Text(
                'Waiting for ${widget.providerName} checkout',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Complete your payment in the browser window that just '
                'opened. This will update automatically once it\'s confirmed.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
            ] else ...[
              Icon(
                Icons.hourglass_empty,
                size: 40,
                color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
              ),
              const SizedBox(height: 16),
              Text(
                'Still waiting',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: isDark ? Colors.white : const Color(0xFF1A1A2E),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'If you\'ve already paid, it can take a moment to confirm. '
                'You can safely close this and check My Receipts later.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: isDark
                      ? Colors.grey.shade400
                      : Colors.grey.shade600,
                ),
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() {
                    _elapsedSeconds = 0;
                  });
                  _poll = Timer.periodic(
                    const Duration(seconds: 4),
                    (_) => _check(),
                  );
                },
                child: const Text('Keep waiting'),
              ),
            ],
            if (widget.onManualConfirm != null) ...[
              const SizedBox(height: 16),
              if (_confirmError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _confirmError!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirming ? null : _manualConfirm,
                  child: _confirming
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text("I've completed payment"),
                ),
              ),
            ],
            const SizedBox(height: 12),
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
          ],
        ),
      ),
    );
  }
}
