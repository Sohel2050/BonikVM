import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'vpn_service.dart';

/// Background handler for notification actions (runs in a separate isolate).
/// Must be a top-level function annotated with @pragma('vm:entry-point').
/// VpnService cannot be used here — write a flag for the main isolate to pick up.
@pragma('vm:entry-point')
void onDidReceiveBackgroundNotificationResponse(NotificationResponse response) {
  if (response.actionId == 'disconnect') {
    SharedPreferences.getInstance().then((prefs) {
      prefs.setBool('pending_vpn_disconnect', true);
    });
  }
}

class VpnNotificationService {
  static final VpnNotificationService _instance =
      VpnNotificationService._internal();
  factory VpnNotificationService() => _instance;
  VpnNotificationService._internal();

  static const String _channelId = 'vpn_channel';
  static const String _channelName = 'VPN Connection';
  static const String _channelDescription =
      'VPN connection status and controls';
  static const int _notificationId = 1;

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;
  bool _isVpnConnected = false;
  DateTime? _connectionStartTime;
  bool _isShowingNotification = false;
  Timer? _pendingDisconnectTimer;

  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const InitializationSettings initializationSettings =
          InitializationSettings(android: initializationSettingsAndroid);

      try {
        await _flutterLocalNotificationsPlugin.initialize(
          initializationSettings,
          onDidReceiveNotificationResponse: _onNotificationTap,
          onDidReceiveBackgroundNotificationResponse:
              onDidReceiveBackgroundNotificationResponse,
        );
      } catch (e) {
        if (e.toString().contains('TypeToken') ||
            e.toString().contains('Gson') ||
            e.toString().contains('plugin')) {
          if (kDebugMode) {}
          _isInitialized = true;
          _startPendingDisconnectPoller();
          return;
        }
        rethrow;
      }

      await _createNotificationChannel();
      _isInitialized = true;
      _startPendingDisconnectPoller();
      if (kDebugMode) {}
    } catch (e) {
      if (kDebugMode) {}
      _isInitialized = true;
    }
  }

  void _startPendingDisconnectPoller() {
    _pendingDisconnectTimer?.cancel();
    _pendingDisconnectTimer = Timer.periodic(const Duration(seconds: 3), (
      _,
    ) async {
      final prefs = await SharedPreferences.getInstance();
      // Force a reload from disk — the background isolate wrote the flag to
      // disk, but this isolate's in-memory cache may not have picked it up yet.
      await prefs.reload();
      if (prefs.getBool('pending_vpn_disconnect') == true) {
        await prefs.remove('pending_vpn_disconnect');
        try {
          await VpnService.instance.disconnect();
        } catch (_) {}
      }
    });
  }

  Future<void> _createNotificationChannel() async {
    const AndroidNotificationChannel channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      description: _channelDescription,
      importance: Importance.low,
      enableVibration: false,
      playSound: false,
      showBadge: false,
    );

    await _flutterLocalNotificationsPlugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(channel);
  }

  void _onNotificationTap(NotificationResponse response) {
    if (response.actionId == 'disconnect') {
      _handleDisconnectAction();
    }
  }

  Future<void> _handleDisconnectAction() async {
    try {
      if (kDebugMode) {}
      await _disconnectVpnFromNotification();
    } catch (e) {
      if (kDebugMode) {}
    }
  }

  Future<void> _disconnectVpnFromNotification() async {
    try {
      await VpnService.instance.disconnect();
      if (kDebugMode) {}
    } catch (e) {
      if (kDebugMode) {}
    }
  }

  Future<void> showVpnConnectedNotification({
    required String serverName,
    required String serverLocation,
    String? serverFlag,
  }) async {
    if (!_isInitialized) await initialize();
    if (_isVpnConnected && _isShowingNotification) return;

    _isVpnConnected = true;
    _isShowingNotification = true;
    _connectionStartTime = DateTime.now();

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      enableVibration: false,
      playSound: false,
      showWhen: false,
      icon: '@mipmap/launcher_icon',
      styleInformation: const BigTextStyleInformation(
        'Tap to manage your VPN connection',
        contentTitle: 'VPN Connected',
      ),
      actions: const [
        AndroidNotificationAction(
          'disconnect',
          'Disconnect',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    await _flutterLocalNotificationsPlugin.show(
      _notificationId,
      'VPN Connected',
      'Connected to $serverName  $serverLocation',
      NotificationDetails(android: androidDetails),
    );

    _startTimeUpdater(serverName, serverLocation);
  }

  void _startTimeUpdater(String serverName, String serverLocation) {
    Future.delayed(const Duration(seconds: 30), () {
      if (_isVpnConnected && _connectionStartTime != null) {
        _updateConnectionTime(serverName, serverLocation);
        _startTimeUpdater(serverName, serverLocation);
      }
    });
  }

  Future<void> _updateConnectionTime(
    String serverName,
    String serverLocation,
  ) async {
    if (!_isVpnConnected || _connectionStartTime == null) return;

    final duration = DateTime.now().difference(_connectionStartTime!);
    final timeString = _formatDuration(duration);

    final androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      enableVibration: false,
      playSound: false,
      showWhen: false,
      icon: '@mipmap/launcher_icon',
      styleInformation: BigTextStyleInformation(
        'Connected for $timeString - Tap to manage',
        contentTitle: 'VPN Connected',
      ),
      actions: const [
        AndroidNotificationAction(
          'disconnect',
          'Disconnect',
          showsUserInterface: true,
          cancelNotification: false,
        ),
      ],
    );

    await _flutterLocalNotificationsPlugin.show(
      _notificationId,
      'VPN Connected',
      'Connected to $serverName  $serverLocation',
      NotificationDetails(android: androidDetails),
    );
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);

    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
  }

  Future<void> showVpnConnectingNotification({
    required String serverName,
    required String serverLocation,
  }) async {
    if (!_isInitialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: true,
      autoCancel: false,
      enableVibration: false,
      playSound: false,
      showWhen: false,
      icon: '@mipmap/launcher_icon',
      styleInformation: BigTextStyleInformation(
        'Please wait while we establish the connection',
        contentTitle: 'Connecting to VPN...',
      ),
    );

    await _flutterLocalNotificationsPlugin.show(
      _notificationId,
      'Connecting to VPN...',
      'Connecting to $serverName  $serverLocation',
      const NotificationDetails(android: androidDetails),
    );
  }

  Future<void> hideVpnNotification() async {
    _isVpnConnected = false;
    _isShowingNotification = false;
    _connectionStartTime = null;
    await _flutterLocalNotificationsPlugin.cancel(_notificationId);
  }

  Future<void> showVpnDisconnectedNotification() async {
    if (!_isInitialized) await initialize();

    const androidDetails = AndroidNotificationDetails(
      _channelId,
      _channelName,
      channelDescription: _channelDescription,
      importance: Importance.low,
      priority: Priority.low,
      ongoing: false,
      autoCancel: true,
      enableVibration: false,
      playSound: false,
      showWhen: true,
      icon: '@mipmap/launcher_icon',
      timeoutAfter: 3000,
    );

    await _flutterLocalNotificationsPlugin.show(
      _notificationId,
      'VPN Disconnected',
      'Your VPN connection has been terminated',
      const NotificationDetails(android: androidDetails),
    );

    Future.delayed(const Duration(seconds: 3), () {
      hideVpnNotification();
    });
  }
}
