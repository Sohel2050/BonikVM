import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:in_app_update/in_app_update.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateService {
static final UpdateService _instance = UpdateService._internal();

factory UpdateService() => _instance;

UpdateService._internal();

static UpdateService get instance => _instance;

// ============================================================
// GOOGLE PLAY PACKAGE
// ============================================================

static const String packageName = 'com.albonik.vpn';

static const String playStoreUrl =
'https://play.google.com/store/apps/details?id=$packageName';

bool _isCheckingForUpdates = false;

// ============================================================
// FORCE UPDATE CHECK
// ============================================================

static Future<ForceUpdateStatus> checkForceUpdateStatus() async {
if (!Platform.isAndroid) {
return const ForceUpdateStatus(
isRequired: false,
);
}

try {
final AppUpdateInfo playInfo =
await InAppUpdate.checkForUpdate();

debugPrint(
'UpdateService: availability='
'${playInfo.updateAvailability}',
);

debugPrint(
'UpdateService: immediateAllowed='
'${playInfo.immediateUpdateAllowed}',
);

debugPrint(
'UpdateService: flexibleAllowed='
'${playInfo.flexibleUpdateAllowed}',
);

if (playInfo.updateAvailability ==
UpdateAvailability.updateAvailable) {
final packageInfo =
await PackageInfo.fromPlatform();

return ForceUpdateStatus(
isRequired: true,
updateInfo: UpdateInfo(
currentVersion: packageInfo.version,
latestVersion: 'New version available',
latestBuildNumber: 0,
releaseNotes: const [
'Bug fixes and performance improvements',
'Enhanced VPN connection stability',
],
downloadUrl: playStoreUrl,
isForceUpdate: true,
),
);
}

return const ForceUpdateStatus(
isRequired: false,
);
} catch (e) {
// Google Play check fail করলে app permanently block হবে না।
debugPrint(
'UpdateService: Force update check failed: $e',
);

return const ForceUpdateStatus(
isRequired: false,
);
}
}

// ============================================================
// INITIALIZE
// ============================================================

Future<void> initialize() async {
try {
debugPrint(
'UpdateService: initialized',
);
} catch (e) {
debugPrint(
'UpdateService: initialization failed: $e',
);
}
}

// ============================================================
// CHECK FOR UPDATES
// ============================================================

Future<void> checkForUpdates({
BuildContext? context,
bool showNoUpdateDialog = false,
}) async {
if (!Platform.isAndroid) {
return;
}

if (_isCheckingForUpdates) {
debugPrint(
'UpdateService: already checking',
);
return;
}

_isCheckingForUpdates = true;

try {
final AppUpdateInfo updateInfo =
await InAppUpdate.checkForUpdate();

debugPrint(
'UpdateService: updateAvailability='
'${updateInfo.updateAvailability}',
);

debugPrint(
'UpdateService: immediateUpdateAllowed='
'${updateInfo.immediateUpdateAllowed}',
);

debugPrint(
'UpdateService: flexibleUpdateAllowed='
'${updateInfo.flexibleUpdateAllowed}',
);

// ========================================================
// UPDATE AVAILABLE
// ========================================================
  if (updateInfo.updateAvailability ==
      UpdateAvailability.updateAvailable) {
    // Try Google's official Immediate Update first.
    if (updateInfo.immediateUpdateAllowed) {
      try {
        debugPrint(
          'UpdateService: Starting immediate update',
        );

        await InAppUpdate.performImmediateUpdate();

        return;
      } catch (e) {
        debugPrint(
          'UpdateService: Immediate update failed: $e',
        );

        // If immediate update fails,
        // open Play Store.
        await _openPlayStore();

        return;
      }
    }

    // Immediate update not allowed.
    // Open official Play Store.
    debugPrint(
      'UpdateService: Immediate update not allowed',
    );

    await _openPlayStore();

    return;
  }

  // ========================================================
  // NO UPDATE
  // ========================================================

  debugPrint(
    'UpdateService: No update available',
  );

  if (showNoUpdateDialog &&
      context != null &&
      context.mounted) {
    await _showNoUpdateDialog(context);
  }
} catch (e) {
  debugPrint(
    'UpdateService: Google Play update check failed: $e',
  );

  // Don't crash the app.
} finally {
  _isCheckingForUpdates = false;
}
}

  // ============================================================
  // MANUAL GOOGLE PLAY CHECK
  // ============================================================

  Future<void> checkGooglePlayUpdate({
    BuildContext? context,
  }) async {
    await checkForUpdates(
      context: context,
      showNoUpdateDialog: true,
    );
  }

  // ============================================================
  // OPEN PLAY STORE
  // ============================================================

  Future<void> _openPlayStore() async {
    final Uri uri = Uri.parse(playStoreUrl);

    try {
      final bool launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched) {
        debugPrint(
          'UpdateService: Could not open Play Store',
        );
      }
    } catch (e) {
      debugPrint(
        'UpdateService: Play Store launch failed: $e',
      );
    }
  }

  // Public method if another screen needs Play Store button.
  Future<void> openPlayStore() async {
    await _openPlayStore();
  }

  // ============================================================
  // NO UPDATE DIALOG
  // ============================================================

  Future<void> _showNoUpdateDialog(
      BuildContext context,
      ) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.check_circle_outline,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  'VPN MASTER',
                ),
              ),
            ],
          ),
          content: const Text(
            'You are using the latest version of VPN MASTER.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text(
                'OK',
              ),
            ),
          ],
        );
      },
    );
  }
}

// ================================================================
// FORCE UPDATE STATUS
// ================================================================

class ForceUpdateStatus {
  final bool isRequired;
  final UpdateInfo? updateInfo;

  const ForceUpdateStatus({
    required this.isRequired,
    this.updateInfo,
  });
}
// ================================================================
// UPDATE INFO
// ================================================================

class UpdateInfo {
  final String currentVersion;
  final String latestVersion;
  final int latestBuildNumber;
  final List<String> releaseNotes;
  final String downloadUrl;
  final bool isForceUpdate;

  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.isForceUpdate,
  });

  bool get shouldUpdate {
    return isForceUpdate;
  }
}