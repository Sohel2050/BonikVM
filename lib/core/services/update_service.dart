import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:in_app_update/in_app_update.dart';

class UpdateService {
  static final UpdateService _instance = UpdateService._internal();
  factory UpdateService() => _instance;
  UpdateService._internal();

  static UpdateService get instance => _instance;

  // Update check intervals
  static const Duration _checkInterval = Duration(hours: 6);
  static const String _lastCheckKey = 'last_update_check';
  static const String _skipVersionKey = 'skip_update_version';

  Timer? _periodicCheckTimer;
  bool _isCheckingForUpdates = false;

  /// Initialize the update service
  Future<void> initialize() async {
    try {


      // Check for updates on app start
      await _checkForUpdatesIfNeeded();

      // Schedule periodic checks
      _schedulePeriodicChecks();


    } catch (e) {

    }
  }

  /// Check for updates with automatic scheduling
  Future<void> _checkForUpdatesIfNeeded() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheck = prefs.getInt(_lastCheckKey) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;

      // Check if enough time has passed since last check
      if (now - lastCheck < _checkInterval.inMilliseconds) {

        return;
      }

      await prefs.setInt(_lastCheckKey, now);
      await checkForUpdates();
    } catch (e) {

    }
  }

  /// Check for updates through API and Google Play
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
      if (Platform.isAndroid) {
        // Use Google Play In-App Updates for Android
        await _checkGooglePlayUpdate(context, showNoUpdateDialog);
      } else {
        // For iOS or other platforms, use API-based check
        await _checkWithCustomAPI(context, showNoUpdateDialog);
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

  /// Check for updates using Google Play In-App Updates
  Future<void> _checkGooglePlayUpdate(
    BuildContext? context,
    bool showNoUpdateDialog,
  ) async {
    try {
      // Check if update is available
      final AppUpdateInfo updateInfo = await InAppUpdate.checkForUpdate();
      
      debugPrint('UpdateService: Update available: ${updateInfo.updateAvailability}');
      debugPrint('UpdateService: Immediate update allowed: ${updateInfo.immediateUpdateAllowed}');
      debugPrint('UpdateService: Flexible update allowed: ${updateInfo.flexibleUpdateAllowed}');

      if (updateInfo.updateAvailability == UpdateAvailability.updateAvailable) {
        if (context != null && context.mounted) {
          await _showPlayStoreUpdateDialog(context, updateInfo);
        } else {
          // If no context, try immediate update
          if (updateInfo.immediateUpdateAllowed) {
            await InAppUpdate.performImmediateUpdate();
          }
        }
      } else {
        debugPrint('UpdateService: No update available');
        if (showNoUpdateDialog && context != null && context.mounted) {
          _showNoUpdateDialog(
            context,
            'You are using the latest version of VPN MASTER.',
          );
        }
      }
    } catch (e) {
      debugPrint('UpdateService: Google Play update check failed: $e');
      // Fallback to custom API check
      await _checkWithCustomAPI(context, showNoUpdateDialog);
    }
  }

  /// Show Google Play update dialog
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
                  style: TextStyle(
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
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  children: [
                    Row(
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

  /// Perform immediate update
  Future<void> _performImmediateUpdate() async {
    try {
      debugPrint('UpdateService: Starting immediate update');
      await InAppUpdate.performImmediateUpdate();
    } catch (e) {
      debugPrint('UpdateService: Immediate update failed: $e');
      await _openPlayStore();
    }
  }

  /// Perform flexible update
  Future<void> _performFlexibleUpdate() async {
    try {
      debugPrint('UpdateService: Starting flexible update');
      await InAppUpdate.startFlexibleUpdate();
      
      // Listen for download completion
      InAppUpdate.completeFlexibleUpdate().then((_) {
        debugPrint('UpdateService: Flexible update completed');
      }).catchError((e) {
        debugPrint('UpdateService: Flexible update completion failed: $e');
      });
    } catch (e) {
      debugPrint('UpdateService: Flexible update failed: $e');
      await _openPlayStore();
    }
  }

  /// Open Play Store for manual update
  Future<void> _openPlayStore() async {
    const playStoreUrl = 'https://play.google.com/store/apps/details?id=com.albonik.vpn';
    final uri = Uri.parse(playStoreUrl);
    
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      debugPrint('UpdateService: Could not open Play Store');
    }
  }

  /// Check for updates with custom API (fallback method)
  Future<void> _checkWithCustomAPI(
    BuildContext? context,
    bool showNoUpdateDialog,
  ) async {
    try {
      // Get current app version
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildNumber = int.tryParse(packageInfo.buildNumber) ?? 0;

      // Check with API for latest version
      final updateInfo = await _checkWithAPI(currentBuildNumber);

      if (updateInfo != null && updateInfo.shouldUpdate) {
        if (context != null && context.mounted) {
          await _showUpdateDialog(context, updateInfo);
        } else {
          debugPrint('UpdateService: Update available but no context for dialog');
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

  /// Check for updates with API
  Future<UpdateInfo?> _checkWithAPI(int currentBuildNumber) async {
    try {
      // TODO: Implement API call to check for updates
      // This would typically call your backend to get the latest version info

      // For now, simulate an update check


      // Simulated response - replace with actual API call
      final latestBuildNumber = currentBuildNumber; // No update available

      if (latestBuildNumber > currentBuildNumber) {
        return UpdateInfo(
          latestVersion: '1.0.${latestBuildNumber}',
          latestBuildNumber: latestBuildNumber,
          releaseNotes: [
            'Bug fixes and performance improvements',
            'Enhanced VPN connection stability',
            'Updated security features',
          ],
          downloadUrl: Platform.isAndroid
              ? 'https://play.google.com/store/apps/details?id=com.albonik.vpn'
              : 'https://apps.apple.com/app/axe-vpn/id123456789',
          isForceUpdate: false,
        );
      }

      return null;
    } catch (e) {

      return null;
    }
  }

  /// Show update dialog
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
                      : 'A new version of VPN MASTERis available!',
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
                    color: Theme.of(context).primaryColor.withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: Theme.of(context).primaryColor.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Current Version:',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                          ),
                          Text(
                            packageInfo.version,
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'New Version:',
                            style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color,
                            ),
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
                Text(
                  'What\'s New:',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: Theme.of(context).textTheme.bodyLarge?.color,
                  ),
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
                          decoration: BoxDecoration(
                            color: Theme.of(context).primaryColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            note,
                            style: TextStyle(
                              fontSize: 14,
                              color: Theme.of(
                                context,
                              ).textTheme.bodyMedium?.color?.withValues(alpha: 0.7),
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
            actions: [
              // Only show skip/later if not force update
              if (!updateInfo.isForceUpdate) ...[
                TextButton(
                  onPressed: () async {
                    // Mark this version as skipped
                    final prefs = await SharedPreferences.getInstance();
                    await prefs.setInt(
                      _skipVersionKey,
                      updateInfo.latestBuildNumber,
                    );
                    Navigator.of(dialogContext).pop();

                    _showToast(
                      context,
                      'Update skipped. You can update manually from settings.',
                    );
                  },
                  child: Text(
                    'Skip',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.6),
                    ),
                  ),
                ),

                TextButton(
                  onPressed: () {
                    Navigator.of(dialogContext).pop();
                    _showToast(
                      context,
                      'Update reminder will appear again later.',
                    );
                  },
                  child: Text(
                    'Later',
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
                    ),
                  ),
                ),
              ],

              // Update button
              ElevatedButton(
                onPressed: () async {
                  Navigator.of(dialogContext).pop();
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

  /// Open app store for update
  Future<void> _openAppStore(String downloadUrl) async {
    try {
      final uri = Uri.parse(downloadUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);

      } else {

      }
    } catch (e) {

    }
  }

  /// Show no update dialog
  void _showNoUpdateDialog(BuildContext context, String message) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.green, size: 24),
              const SizedBox(width: 12),
              const Text('Up to Date'),
            ],
          ),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  /// Show toast message
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

  /// Schedule periodic update checks
  void _schedulePeriodicChecks() {
    _periodicCheckTimer?.cancel();
    _periodicCheckTimer = Timer.periodic(_checkInterval, (timer) {
      _checkForUpdatesIfNeeded();
    });}

  /// Manually check for updates (called from settings)
  Future<void> manualUpdateCheck(BuildContext context) async {

    await checkForUpdates(context: context, showNoUpdateDialog: true);
  }

  /// Force update check (bypass time restrictions)
  Future<void> forceUpdateCheck(BuildContext context) async {


    // Reset last check time
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_lastCheckKey);

    await checkForUpdates(context: context, showNoUpdateDialog: true);
  }

  /// Clear skipped version
  Future<void> clearSkippedVersion() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_skipVersionKey);

  }

  /// Dispose resources
  void dispose() {
    _periodicCheckTimer?.cancel();

  }
}

/// Update information model
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

