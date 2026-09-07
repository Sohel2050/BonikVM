import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Google Play VPN policy requires a "prominent disclosure" shown to the
/// user, inside the app, before the VPN connection is established for the
/// first time — explaining that the app routes traffic through a VPN and
/// what data (if any) is collected. This must be shown BEFORE the OS-level
/// VPN permission prompt, and the user must actively acknowledge it.
class VpnDisclosureDialog {
  static const _prefsKey = 'vpn_disclosure_acknowledged_v1';

  /// Shows the disclosure dialog if the user hasn't acknowledged it yet.
  /// Returns true if it's safe to proceed with connecting (either the user
  /// just agreed, or had already agreed in a previous session). Returns
  /// false if the user dismissed/declined — the caller should not proceed
  /// with connecting in that case.
  static Future<bool> showIfNeeded(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final alreadyAcknowledged = prefs.getBool(_prefsKey) ?? false;
    if (alreadyAcknowledged) return true;

    if (!context.mounted) return false;

    final agreed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('VPN & Data Disclosure'),
          content: const SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'This app provides VPN functionality and routes your '
                  'internet traffic through the VPN when connected.',
                ),
                SizedBox(height: 12),
                Text(
                  'Account Information: If you create an account, we may '
                  'collect information such as your name and email address '
                  'for account-related purposes.',
                ),
                SizedBox(height: 12),
                Text(
                  'VPN Traffic: We do not collect or store your internet '
                  'browsing activity or VPN traffic while the VPN is '
                  'connected.',
                ),
                SizedBox(height: 12),
                Text(
                  'By tapping "I Understand & Agree", you acknowledge this '
                  'disclosure and continue to the VPN connection request.',
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I Understand & Agree'),
            ),
          ],
        ),
      ),
    );

    if (agreed == true) {
      await prefs.setBool(_prefsKey, true);
      return true;
    }
    return false;
  }
}
