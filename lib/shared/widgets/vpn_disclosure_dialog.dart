import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/localization/app_localizations.dart';

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
          title: Text(tr('vd_title')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr('vd_p1'),
                ),
                SizedBox(height: 12),
                Text(
                  tr('vd_p2'),
                ),
                SizedBox(height: 12),
                Text(
                  tr('vd_p3'),
                ),
                SizedBox(height: 12),
                Text(
                  tr('vd_p4'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(tr('cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(tr('vd_agree')),
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
