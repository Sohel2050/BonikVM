import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:dio/dio.dart';
import '../models/app_notification.dart';
import '../api/api_service.dart';
import '../config/app_config.dart';
import '../navigation/app_navigator.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal() {
    // Initialize Dio for API calls
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 10),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-API-Token': AppConfig.apiKey,
        },
      ),
    );
    _notificationController =
        StreamController<List<AppNotification>>.broadcast();
  }

  static NotificationService get instance => _instance;

  // Stream controller for notification updates
  late StreamController<List<AppNotification>> _notificationController;
  Stream<List<AppNotification>> get notificationStream =>
      _notificationController.stream;

  // Stream that fires when a subscription-related push notification arrives
  // (crypto approved / rejected). Consumers listen and refresh premium state.
  final StreamController<Map<String, dynamic>> _subscriptionEventController =
      StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get subscriptionEventStream =>
      _subscriptionEventController.stream;

  // HTTP client for API calls
  late Dio _dio;

  // Firebase Messaging
  final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;

  // Local Notifications
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  // Notification channels
  static const String _vpnChannelId = 'vpn_channel';
  static const String _generalChannelId = 'general_channel';
  static const String _securityChannelId = 'security_channel';

  // Storage keys
  static const String _tokenKey = 'fcm_token';
  static const String _deviceIdKey = 'device_id';

  bool _isInitialized = false;
  String? _currentToken;
  String? _userId;

  // Admin settings
  bool _notificationsEnabled = true;
  bool _firebaseEnabled = true;

  /// Initialize notification service
  Future<void> initialize({String? userId}) async {
    if (_isInitialized) {
      return;
    }

    try {
      _userId = userId;

      // Check admin settings first
      await _checkAdminSettings();

      // Skip initialization if notifications are disabled
      if (!_notificationsEnabled || !_firebaseEnabled) {
        _isInitialized = true; // Mark as initialized to prevent retries
        return;
      }

      // Initialize local notifications
      await _initializeLocalNotifications();

      // Initialize Firebase messaging
      await _initializeFirebaseMessaging();

      // Request permissions
      await _requestPermissions();

      // Get and register FCM token
      await _handleTokenRegistration();

      // Set up message handlers
      _setupMessageHandlers();

      _isInitialized = true;
    } catch (e) {
      rethrow;
    }
  }

  /// Check admin notification settings
  Future<void> _checkAdminSettings() async {
    try {
      final settings = await ApiService.instance.getNotificationSettings();

      _notificationsEnabled = settings['notifications_enabled'] ?? true;
      _firebaseEnabled = settings['firebase_enabled'] ?? true;
    } catch (e) {
      // Keep default values if API fails
      _notificationsEnabled = true;
      _firebaseEnabled = true;
    }
  }

  /// Initialize local notifications
  Future<void> _initializeLocalNotifications() async {
    try {
      const androidSettings = AndroidInitializationSettings(
        '@mipmap/ic_launcher',
      );
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );
    } catch (e) {
      if (e.toString().contains('TypeToken') ||
          e.toString().contains('Gson') ||
          e.toString().contains('plugin')) {
        return; // Continue without local notifications
      }
      rethrow;
    }

    // Create notification channels for Android
    if (Platform.isAndroid) {
      await _createNotificationChannels();
    }
  }

  /// Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    if (androidPlugin != null) {
      // VPN channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _vpnChannelId,
          'VPN Notifications',
          description: 'VPN connection status and server information',
          importance: Importance.high,
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFF00FF00),
        ),
      );

      // General channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _generalChannelId,
          'General Notifications',
          description: 'General app notifications and updates',
          importance: Importance.defaultImportance,
          enableVibration: true,
        ),
      );

      // Security channel
      await androidPlugin.createNotificationChannel(
        const AndroidNotificationChannel(
          _securityChannelId,
          'Security Alerts',
          description: 'Security alerts and important notices',
          importance: Importance.max,
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFFFF0000),
        ),
      );
    }
  }

  /// Initialize Firebase messaging
  Future<void> _initializeFirebaseMessaging() async {
    // Configure Firebase messaging
    await _firebaseMessaging.setForegroundNotificationPresentationOptions(
      alert: true,
      badge: false, // Disabled to prevent duplicate badges
      sound: true,
    );
  }

  /// Request notification permissions
  Future<void> _requestPermissions() async {
    try {
      final settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: false, // Disabled to prevent duplicate badges
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        throw Exception('Notification permissions denied');
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Handle FCM token registration
  Future<void> _handleTokenRegistration() async {
    try {
      // Get FCM token
      final token = await _firebaseMessaging.getToken();
      if (token != null) {
        _currentToken = token;

        // Save token locally
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);

        // Get device info
        final deviceInfo = await _getDeviceInfo();
        final deviceId = deviceInfo['device_id'] ?? 'unknown';

        // Register token with backend
        try {
          // Get current Firebase user ID if available
          final currentUser = FirebaseAuth.instance.currentUser;
          final userId = currentUser?.uid;

          await ApiService.instance.registerFcmToken(
            token,
            deviceId,
            userId: userId,
          );
        } catch (e) {}
      }

      // Subscribe to broadcast topic so admin can send to all users in one FCM call
      try {
        await _firebaseMessaging.subscribeToTopic('all_users');
      } catch (e) {
        /* non-fatal */
      }

      // Listen for token refresh
      _firebaseMessaging.onTokenRefresh.listen((newToken) async {
        _currentToken = newToken;

        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, newToken);

        // Register new token with backend
        try {
          // Get current Firebase user ID if available
          final currentUser = FirebaseAuth.instance.currentUser;
          final userId = currentUser?.uid;

          final deviceInfo = await _getDeviceInfo();
          final deviceId = deviceInfo['device_id'] ?? 'unknown';
          await ApiService.instance.registerFcmToken(
            newToken,
            deviceId,
            userId: userId,
          );
        } catch (e) {}
      });
    } catch (e) {}
  }

  /// Get device information
  Future<Map<String, String>> _getDeviceInfo() async {
    final deviceInfoPlugin = DeviceInfoPlugin();
    final prefs = await SharedPreferences.getInstance();

    String deviceId = prefs.getString(_deviceIdKey) ?? '';

    if (deviceId.isEmpty) {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfoPlugin.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfoPlugin.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown_ios';
      }

      await prefs.setString(_deviceIdKey, deviceId);
    }

    return {'device_id': deviceId, 'platform': Platform.operatingSystem};
  }

  /// Setup message handlers
  void _setupMessageHandlers() {
    // Handle foreground messages
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

    // Handle background message taps
    FirebaseMessaging.onMessageOpenedApp.listen(_handleMessageOpenedApp);

    // Handle app launch from terminated state
    _handleAppLaunchedFromMessage();
  }

  /// Handle foreground messages
  Future<void> _handleForegroundMessage(RemoteMessage message) async {
    try {
      // Create notification from message - handle both with and without notification payload
      final appNotification = AppNotification(
        id:
            message.messageId ??
            DateTime.now().millisecondsSinceEpoch.toString(),
        title:
            message.notification?.title ??
            message.data['title'] ??
            'Notification',
        body: message.notification?.body ?? message.data['body'] ?? '',
        type: message.data['type'] ?? 'general',
        isRead: false,
        createdAt: DateTime.now(),
        data: message.data,
      );

      // Save notification to local storage
      await saveNotification(appNotification);

      // Notify listeners about the new notification
      final updatedNotifications = await getNotifications();
      _notificationController.add(updatedNotifications);
    } catch (e) {
      if (kDebugMode) {
        print('Error saving notification: $e');
      }
    }

    // Show local notification for foreground messages
    await _showLocalNotification(message);

    // Handle specific message types
    await _handleNotificationAction(message);
  }

  /// Handle message when app is opened from notification
  Future<void> _handleMessageOpenedApp(RemoteMessage message) async {
    // Navigate to notifications screen when user taps a background notification
    appNavigatorKey.currentState?.pushNamed('/notifications');
    await _handleNotificationAction(message);
  }

  /// Handle app launched from terminated state via notification
  Future<void> _handleAppLaunchedFromMessage() async {
    final initialMessage = await _firebaseMessaging.getInitialMessage();
    if (initialMessage != null) {
      await _handleNotificationAction(initialMessage);
    }
  }

  /// Handle notification action based on type
  Future<void> _handleNotificationAction(RemoteMessage message) async {
    final messageType = message.data['type'] ?? 'general';

    switch (messageType) {
      case 'vpn_connection':
        await _handleVpnNotification(message);
        break;
      case 'subscription':
      case 'subscription_activated':
        await _handleSubscriptionNotification(message);
        break;
      case 'crypto_rejected':
        await _handleCryptoRejectedNotification(message);
        break;
      case 'security':
        await _handleSecurityNotification(message);
        break;
      case 'maintenance':
        await _handleMaintenanceNotification(message);
        break;
      case 'promotion':
        await _handlePromotionNotification(message);
        break;
      default:
        break;
    }
  }

  /// Handle VPN-related notifications
  Future<void> _handleVpnNotification(RemoteMessage message) async {
    // Handle VPN notification
  }

  /// Handle subscription notifications (including crypto approval)
  Future<void> _handleSubscriptionNotification(RemoteMessage message) async {
    // Signal listeners so they can refresh subscription state from the API.
    _subscriptionEventController.add({
      'type': 'subscription_activated',
      'data': message.data,
    });
  }

  /// Handle crypto payment rejection notification
  Future<void> _handleCryptoRejectedNotification(RemoteMessage message) async {
    _subscriptionEventController.add({
      'type': 'crypto_rejected',
      'data': message.data,
    });
  }

  /// Handle security notifications
  Future<void> _handleSecurityNotification(RemoteMessage message) async {}

  /// Handle maintenance notifications
  Future<void> _handleMaintenanceNotification(RemoteMessage message) async {}

  /// Handle promotion notifications
  Future<void> _handlePromotionNotification(RemoteMessage message) async {}

  /// Show local notification
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    final messageType = message.data['type'] ?? 'general';
    AndroidNotificationDetails androidDetails;

    // Set notification details based on type
    switch (messageType) {
      case 'vpn_connection':
        androidDetails = const AndroidNotificationDetails(
          _vpnChannelId,
          'VPN Notifications',
          channelDescription: 'VPN connection status',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFF00FF00),
        );
        break;
      case 'security':
        androidDetails = const AndroidNotificationDetails(
          _securityChannelId,
          'Security Alerts',
          channelDescription: 'Security notifications',
          importance: Importance.max,
          priority: Priority.max,
          icon: '@mipmap/launcher_icon',
          enableVibration: true,
          enableLights: true,
          ledColor: Color(0xFFFF0000),
        );
        break;
      default:
        androidDetails = const AndroidNotificationDetails(
          _generalChannelId,
          'General Notifications',
          channelDescription: 'General app notifications',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/launcher_icon',
          enableVibration: true,
          enableLights: true,
        );
        break;
    }

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: false, // Disabled to prevent duplicate badges
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      message.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  /// Handle notification tap
  Future<void> _onNotificationTapped(NotificationResponse response) async {
    // Navigate to the notifications screen
    appNavigatorKey.currentState?.pushNamed('/notifications');

    if (response.payload != null) {
      try {
        final data = jsonDecode(response.payload!);

        // Handle navigation based on notification data
        await _handleNotificationAction(
          RemoteMessage(data: Map<String, String>.from(data)),
        );
      } catch (e) {}
    }
  }

  /// Update user ID (called when user logs in/out)
  void updateUserId(String? userId) {
    _userId = userId;
  }

  /// Get current FCM token
  String? get currentToken => _currentToken;

  /// Check if service is initialized
  bool get isInitialized => _isInitialized;

  /// Get notifications from backend
  Future<List<AppNotification>> getNotifications() async {
    try {
      // First try to get from backend API
      if (_userId != null) {
        try {
          final response = await _dio.get(
            '/api/${AppConfig.apiVersion}/notifications/user/$_userId',
          );
          if (response.statusCode == 200 && response.data['success'] == true) {
            final responseData = response.data['data'];
            // Backend returns { data: { notifications: [...] } }
            final List<dynamic> notificationsList =
                (responseData is Map
                    ? responseData['notifications']
                    : responseData) ??
                [];
            final notifications = notificationsList
                .map((json) => AppNotification.fromJson(json))
                .toList();

            // Save to local storage as backup
            await _saveNotificationsLocally(notifications);
            return notifications;
          }
        } catch (e) {
          // Continue to local fallback
        }
      }

      // Fallback to local storage
      final prefs = await SharedPreferences.getInstance();
      final String? notificationsJson = prefs.getString('app_notifications');

      if (notificationsJson == null) {
        return [];
      }

      final List<dynamic> notificationsList = jsonDecode(notificationsJson);
      return notificationsList
          .map((json) => AppNotification.fromJson(json))
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Save notifications to local storage
  Future<void> _saveNotificationsLocally(
    List<AppNotification> notifications,
  ) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = jsonEncode(
        notifications.map((n) => n.toJson()).toList(),
      );
      await prefs.setString('app_notifications', notificationsJson);
    } catch (e) {}
  }

  /// Save notification locally
  Future<void> saveNotification(AppNotification notification) async {
    try {
      final notifications = await getNotifications();
      notifications.insert(0, notification); // Add to beginning

      // Keep only last 100 notifications
      if (notifications.length > 100) {
        notifications.removeRange(100, notifications.length);
      }

      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = jsonEncode(
        notifications.map((n) => n.toJson()).toList(),
      );
      await prefs.setString('app_notifications', notificationsJson);

      // Notify listeners about the update
      _notificationController.add(notifications);

      if (kDebugMode) {
        print('Notification saved successfully: ${notification.title}');
      }
    } catch (e) {
      if (kDebugMode) {
        print('Error saving notification: $e');
      }
    }
  }

  /// Delete a specific notification
  Future<void> deleteNotification(String notificationId) async {
    try {
      final notifications = await getNotifications();
      notifications.removeWhere((n) => n.id == notificationId);

      final prefs = await SharedPreferences.getInstance();
      final notificationsJson = jsonEncode(
        notifications.map((n) => n.toJson()).toList(),
      );
      await prefs.setString('app_notifications', notificationsJson);

      // Notify listeners about the update
      _notificationController.add(notifications);
    } catch (e) {
      rethrow;
    }
  }

  /// Delete all notifications
  Future<void> deleteAllNotifications() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('app_notifications');

      // Notify listeners about the update
      _notificationController.add([]);
    } catch (e) {
      rethrow;
    }
  }

  /// Mark notification as read
  Future<void> markNotificationAsRead(String notificationId) async {
    try {
      final notifications = await getNotifications();
      final index = notifications.indexWhere((n) => n.id == notificationId);

      if (index != -1) {
        notifications[index] = notifications[index].copyWith(isRead: true);

        final prefs = await SharedPreferences.getInstance();
        final notificationsJson = jsonEncode(
          notifications.map((n) => n.toJson()).toList(),
        );
        await prefs.setString('app_notifications', notificationsJson);
      }
    } catch (e) {}
  }

  /// Dispose notification service
  void dispose() {
    _notificationController.close();
  }
}

/// Background message handler (must be top-level function)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}
