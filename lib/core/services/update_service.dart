import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_update/in_app_update.dart';

import '../api/api_service.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();

  factory UpdateService() => _instance;

  UpdateService._internal();

  static UpdateService get instance => _instance;

  // Only used for periodic checks while app is running.
  // App startup always checks immediately.
  static const Duration _periodicCheckInterval = Duration(hours: 6);

  static const String _skipVersionKey = 'skip_update_version';

  Timer? _periodicCheckTimer;

  bool _isCheckingForUpdates = false;

  // ============================================================
  // INITIALIZE

  // ============================================================

  Future<void> initialize() async {
    try {
      // প্রতিবার app start হলে update check হবে
      await checkForUpdates();

      // App চলমান অবস্থায় periodic check
      _schedulePeriodicChecks();
    } catch (e) {
      debugPrint('UpdateService: Initialize error: $e');
    }
  }

  // ============================================================
  // CHECK FOR UPDATES
  // ============================================================

  Future<void> checkForUpdates({
    BuildContext? context,
    bool showNoUpdateDialog = false,
  }) async {
    if (_isCheckingForUpdates) {
      debugPrint('UpdateService: Already checking for updates');
      return;
    }

    _isCheckingForUpdates = true;

    try {
      // ----------------------------------------------------------
      // 1. ALWAYS check admin/backend first
      // ----------------------------------------------------------

      final adminUpdate = await _checkAdminForceUpdate();

      debugPrint(
        'UpdateService: Admin update = '
        '${adminUpdate?.latestVersion}, '
        'force = ${adminUpdate?.isForceUpdate}',
      );

      // ----------------------------------------------------------
      // 2. FORCE UPDATE
      // ----------------------------------------------------------

      if (adminUpdate != null && adminUpdate.isForceUpdate) {
        if (context != null && context.mounted) {
          await _showUpdateDialog(context, adminUpdate);
        } else {
          debugPrint(
            'UpdateService: Force update detected but no context available',
          );
        }

        // VERY IMPORTANT:
        // Do NOT check Google Play here.
        // Do NOT save skip/update state.
        return;
      }

      // ----------------------------------------------------------
      // 3. OPTIONAL UPDATE
      //

      // ----------------------------------------------------------

      if (Platform.isAndroid) {
        await _checkGooglePlayUpdate(context, showNoUpdateDialog);
      } else {
        if (adminUpdate != null && adminUpdate.shouldUpdate) {
          if (context != null && context.mounted) {
            await _showUpdateDialog(context, adminUpdate);
          }
        } else if (showNoUpdateDialog && context != null && context.mounted) {
          _showNoUpdateDialog(
            context,
            'You are using the latest version of VPN MASTER.',
          );
        }
      }
    } catch (e) {
      debugPrint('UpdateService: Error checking for updates: $e');

      if (showNoUpdateDialog && context != null && context.mounted) {
        _showNoUpdateDialog(
          context,
          'Failed to check for updates. Please try again later.',
        );
      }
    } finally {
      _isCheckingForUpdates = false;
    }
  }

  // ============================================================
  // GOOGLE PLAY OPTIONAL UPDATE
  // ============================================================
  Future<void> _checkGooglePlayUpdate(
    BuildContext? context,
    bool showNoUpdateDialog,
  ) async {
    try {
      final AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();

      debugPrint(
        'UpdateService: Play update availability: '
        '${updateInfo.updateAvailability}',
      );

      debugPrint(
        'UpdateService: Immediate update allowed: '
        '${updateInfo.immediateUpdateAllowed}',
      );

      debugPrint(
        'UpdateService: Flexible update allowed: '
        '${updateInfo.flexibleUpdateAllowed}',
      );

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        if (context != null && context.mounted) {
          await _showPlayStoreUpdateDialog(context, updateInfo);
        } else if (updateInfo.immediateUpdateAllowed) {
          await _performImmediateUpdate();
        }
      } else {
        debugPrint('UpdateService: No Google Play update available');

        if (showNoUpdateDialog && context != null && context.mounted) {
          _showNoUpdateDialog(
            context,
            'You are using the latest version of VPN MASTER.',
          );
        }
      }
    } catch (e) {
      debugPrint('UpdateService: Google Play update check failed: $e');

      // If Play check fails, use backend optional update.
      await _checkWithCustomAPI(context, showNoUpdateDialog);
    }
  }

  //

  // ============================================================
  // GOOGLE PLAY UPDATE DIALOG
  // ============================================================

  Future<void> _showPlayStoreUpdateDialog(
    BuildContext context,
    AppUpdateInfo updateInfo,
  ) async {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.system_update,
                  color: Theme.of(context).primaryColor,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'Update Available',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A new version of VPN MASTER is available on Google Play Store!',
                style: TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: Theme.of(context).primaryColor,
                      size: 16,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Update includes bug fixes and performance improvements',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          actions: [
            if (updateInfo.flexibleUpdateAllowed)
              TextButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _performFlexibleUpdate();
                },
                child: const Text('Update Later'),
              ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(dialogContext);

                if (updateInfo.immediateUpdateAllowed) {
                  await _performImmediateUpdate();
                } else {
                  await _openPlayStore();
                }
              },
              child: const Text('Update Now'),
            ),
          ],
        );
      },
    );
  }

  //

  // ============================================================

  Future<void> _performImmediateUpdate() async {
    try {
      debugPrint('UpdateService: Starting immediate update');

      await InAppUpdate.performImmediateUpdate();
    } catch (e) {
      debugPrint('UpdateService: Immediate update failed: $e');

      await _openPlayStore();
    }
  }

  // ============================================================
  // FLEXIBLE UPDATE
  // ============================================================

  Future<void> _performFlexibleUpdate() async {
    try {
      debugPrint('UpdateService: Starting flexible update');

      await InAppUpdate.startFlexibleUpdate();

      await InAppUpdate.completeFlexibleUpdate();

      debugPrint('UpdateService: Flexible update completed');
    } catch (e) {
      debugPrint('UpdateService: Flexible update failed: $e');

      await _openPlayStore();
    }
  }

  // ============================================================
  // OPEN PLAY STORE
  // ============================================================

  Future<void> _openPlayStore() async {
    const playStoreUrl =
        'https://play.google.com/store/apps/details?id=com.albonik.vpn';

    await _openAppStore(playStoreUrl);
  }

  Future<void> _openAppStore(String downloadUrl) async {
    try {
      final uri = Uri.parse(downloadUrl);

      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        debugPrint('UpdateService: Could not open store URL');
      }
    } catch (e) {
      debugPrint('UpdateService: Open store failed: $e');
    }
  }

  // ============================================================
  // CUSTOM API FALLBACK
  // ============================================================

  Future<void> _checkWithCustomAPI(
    BuildContext? context,
    bool showNoUpdateDialog,
  ) async {
    try {
      final updateInfo = await _checkAdminForceUpdate();

      if (updateInfo != null && updateInfo.shouldUpdate) {
        if (context != null && context.mounted) {
          await _showUpdateDialog(context, updateInfo);
        }
      } else {
        debugPrint('UpdateService: No API update available');
        if (showNoUpdateDialog && context != null && context.mounted) {
          _showNoUpdateDialog(
            context,
            'You are using the latest version of VPN MASTER.',
          );
        }
      }
    } catch (e) {
      debugPrint('UpdateService: Custom API check failed: $e');

      if (showNoUpdateDialog && context != null && context.mounted) {
        _showNoUpdateDialog(
          context,
          'Failed to check for updates. Please try again later.',
        );
      }
    }
  }

  // ============================================================
  // ADMIN / BACKEND UPDATE CHECK
  //

  Future<UpdateInfo?> _checkAdminForceUpdate() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();

      final currentVersion = packageInfo.version;

      final platform = Platform.isIOS ? 'ios' : 'android';

      debugPrint('UpdateService: Current version = $currentVersion');

      debugPrint('UpdateService: Platform = $platform');

      final data = await ApiService.instance.getUpdateInfo(
        platform: platform,
        version: currentVersion,
      );

      debugPrint('UpdateService: Backend response = $data');

      final updateAvailable = data['update_available'] == true;

      if (!updateAvailable) {
        debugPrint('UpdateService: Backend says no update');

        return null;
      }

      final latestVersion =
          data['latest_version']?.toString() ?? currentVersion;

      final downloadUrl = (data['download_url']?.toString() ?? '').isNotEmpty
          ? data['download_url'].toString()
          : Platform.isAndroid
          ? 'https://play.google.com/store/apps/details?id=com.albonik.vpn'
          : 'https://apps.apple.com/app/axe-vpn/id123456789';

      final isForceUpdate = data['is_force_update'] == true;

      debugPrint('UpdateService: Latest version = $latestVersion');

      debugPrint('UpdateService: Force update = $isForceUpdate');

      return UpdateInfo(
        latestVersion: latestVersion,
        latestBuildNumber: 1,
        releaseNotes: const [
          'Bug fixes and performance improvements',
          'Enhanced VPN connection stability',
        ],
        downloadUrl: downloadUrl,
        isForceUpdate: isForceUpdate,
      );
    } catch (e) {
      debugPrint('UpdateService: Admin update check failed: $e');

      return null;
    }
  }

  //

  // UPDATE DIALOG
  // ============================================================

  Future<void> _showUpdateDialog(
    BuildContext context,
    UpdateInfo updateInfo,
  ) async {
    final packageInfo = await PackageInfo.fromPlatform();

    return showDialog<void>(
      context: context,
      barrierDismissible: !updateInfo.isForceUpdate,
      builder: (BuildContext dialogContext) {
        return PopScope(
          canPop: !updateInfo.isForceUpdate,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: updateInfo.isForceUpdate
                        ? Colors.red.withValues(alpha: 0.1)
                        : Theme.of(context).primaryColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    updateInfo.isForceUpdate
                        ? Icons.warning
                        : Icons.system_update,
                    color: updateInfo.isForceUpdate
                        ? Colors.red
                        : Theme.of(context).primaryColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    updateInfo.isForceUpdate
                        ? 'Critical Update'
                        : 'Update Available',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  updateInfo.isForceUpdate
                      ? 'A critical update is required to continue using VPN MASTER.'
                      : 'A new version of VPN MASTER is available!',
                  style: TextStyle(
                    fontSize: 16,
                    color: Theme.of(
                      context,
                    ).textTheme.bodyLarge?.color?.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(
                        context,
                      ).primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Current Version:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            packageInfo.version,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'New Version:',
                            style: TextStyle(fontWeight: FontWeight.w500),
                          ),
                          Text(
                            updateInfo.latestVersion,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  "What's New:",
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                ...updateInfo.releaseNotes.map(
                  (note) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          margin: const EdgeInsets.only(top: 6),
                          width: 4,
                          height: 4,
                          decoration: const BoxDecoration(
                            color: Colors.blue,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: const TextStyle(fontSize: 14, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              // Optional update only
              if (!updateInfo.isForceUpdate) ...[
                TextButton(
                  onPressed: () async {
                    final prefs = await SharedPreferences.getInstance();

                    await prefs.setInt(
                      _skipVersionKey,
                      updateInfo.latestBuildNumber,
                    );

                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }

                    if (context.mounted) {
                      _showToast(context, 'Update skipped.');
                    }
                  },
                  child: const Text('Skip'),
                ),

                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();

                    _showToast(
                      context,
                      'Update reminder will appear again later.',
                    );
                  },
                  child: const Text('Later'),
                ),
              ],

              // Update button
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();

                  // IMPORTANT:
                  // We DO NOT save anything here.
                  //
                  // If user opens Play Store and comes back
                  // without updating, next app launch will
                  // check backend again and show force dialog.
                  await _openAppStore(updateInfo.downloadUrl);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: updateInfo.isForceUpdate
                      ? Colors.red
                      : Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                ),
                child: Text(
                  updateInfo.isForceUpdate ? 'Update Required' : 'Update Now',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  //

  // NO UPDATE DIALOG
  // ============================================================

  void _showNoUpdateDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: const Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 24),
              SizedBox(width: 12),
              Text('Up to Date'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // TOAST
  // ============================================================

  void _showToast(BuildContext context, String message) {
    final scaffoldMessenger = ScaffoldMessenger.of(context);

    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 3),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  // ============================================================
  // PERIODIC CHECK
  // ============================================================

  void _schedulePeriodicChecks() {
    _periodicCheckTimer?.cancel();

    _periodicCheckTimer = Timer.periodic(_periodicCheckInterval, (_) async {
      await checkForUpdates();
    });
  }

  // ============================================================
  // MANUAL CHECK
  // ============================================================

  Future<void> manualUpdateCheck(BuildContext context) async {
    await checkForUpdates(context: context, showNoUpdateDialog: true);
  }

  // ============================================================
  // FORCE CHECK
  // ============================================================

  Future<void> forceUpdateCheck(BuildContext context) async {
    await checkForUpdates(context: context, showNoUpdateDialog: true);
  }

  // ============================================================
  // CLEAR SKIPPED VERSION
  // ============================================================

  Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();

    await prefs.remove(_skipVersionKey);
  }

  // ============================================================
  // DISPOSE
  //

  void dispose() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = null;
  }
}

// ================================================================
// UPDATE INFO MODEL
// ================================================================

class UpdateInfo {
  final String latestVersion;
  final int latestBuildNumber;
  final List<String> releaseNotes;
  final String downloadUrl;
  final bool isForceUpdate;

  UpdateInfo({
    required this.latestVersion,
    required this.latestBuildNumber,
    required this.releaseNotes,
    required this.downloadUrl,
    this.isForceUpdate = false,
  });

  bool get shouldUpdate => latestBuildNumber > 0;
}
