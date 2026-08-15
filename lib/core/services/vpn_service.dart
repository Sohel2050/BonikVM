import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import 'package:axevpn_flutter/v2ray_flutter.dart';
import 'package:axevpn_flutter/openconnect_flutter.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../api/api_service.dart';
import 'purchase_service.dart';
import 'vpn_state_persistence_service.dart';
import 'vpn_state.dart';

class VpnService {
  static final VpnService _instance = VpnService._internal();
  factory VpnService() => _instance;
  VpnService._internal() {
    // Emit initial state immediately to prevent loading state
    _stateController.add(_vpnState);
  }

  static VpnService get instance => _instance;

  OpenVPN? _openVPN;
  WireGuard? _wireGuard;
  V2Ray? _v2ray;
  OpenConnect? _openConnect;
  Completer<bool>? _ocCompleter;
  VpnState _vpnState = VpnState.disconnected;
  VpnServer? _currentServer;
  DateTime? _connectionStartTime;
  Timer? _connectionTimer;
  Timer? _statusUpdateTimer; // Add status update timer
  Timer? _statusCheckTimer; // Add status check timer for polling
  String? _deviceId;
  bool _isInitialized = false;
  bool _isAutoConnect = false;
  bool _isUserDisconnecting =
      false; // guard: suppress connected events during intentional disconnect
  Duration _totalConnectionTime = Duration.zero;

  // Last raw status from the OpenVPN plugin — preserves byte traffic counters
  VpnStatus? _lastPluginStatus;

  // When set, transient 'disconnected' stage events arriving before this
  // timestamp are suppressed.  Android fires a disconnected event at the very
  // start of every new connection (the VPN process transitions through its
  // previous state) which would otherwise flash a spurious CONNECTION ERROR.
  DateTime? _suppressDisconnectedUntil;

  // State persistence service
  final VpnStatePersistenceService _persistence = VpnStatePersistenceService();

  // Notification system
  FlutterLocalNotificationsPlugin? _localNotifications;
  static const String _vpnChannelId = 'vpn_channel';
  static const String _vpnForegroundChannelId = 'vpn_foreground_channel';

  // Stream controllers for state management
  final _stateController = StreamController<VpnState>.broadcast();
  final _statusController = StreamController<VpnStatus?>.broadcast();

  // Getters
  VpnState get vpnState => _vpnState;
  VpnServer? get currentServer => _currentServer;
  DateTime? get connectionStartTime => _connectionStartTime;

  /// Stream of VPN states. Always emits the current state immediately on subscribe
  /// so that widgets that attach after initialization still see the correct state
  /// (e.g. app reopen while VPN foreground service is still running).
  Stream<VpnState> get vpnStateStream async* {
    yield _vpnState;
    yield* _stateController.stream;
  }

  Stream<VpnStatus?> get vpnStatusStream => _statusController.stream;

  Future<void> initialize() async {
    try {
      // Get device ID for logging
      _deviceId = await _getDeviceId();

      // Initialize local notifications
      await _initializeNotifications();

      // Initialize OpenVPN plugin immediately for iOS
      if (Platform.isIOS) {
        try {
          _openVPN = OpenVPN(
            onVpnStatusChanged: _onVpnStatusChanged,
            onVpnStageChanged: _onVpnStageChanged,
          );


          await _openVPN!.initialize(
            groupIdentifier: "group.com.albonik.vpn",
            providerBundleIdentifier: "com.albonik.vpn.VPNExtension",
            localizedDescription: "VPN MASTER Connection",
          );

          // Test if VPN profile is installed
          try {
            final stage = await _openVPN!.stage();
          } catch (e) {
          }
        } catch (e) {
        }
      }

      // Simple initialization without complex engine setup
      _isInitialized = true;

      // Recover VPN state: queries the actual plugin stage so that
      // the UI shows 'connected' when the VPN foreground service is still
      // running after the app was killed or moved to the background.
      await _loadSavedVpnState();

      // Emit the actual (possibly recovered) state – do NOT force disconnected.
      _stateController.add(_vpnState);
    } catch (e) {
      _isInitialized = false;

      // Even on error, emit disconnected state
      _vpnState = VpnState.disconnected;
      _stateController.add(_vpnState);
    }
  }

  /// Load saved VPN state on app initialization.
  ///
  /// Queries the actual OpenVPN plugin stage so that the app correctly shows
  /// 'connected' when the VPN foreground service is still running after the
  /// app was killed or moved to the background.
  Future<void> _loadSavedVpnState() async {
    try {
      final savedState = await _persistence.loadVpnState();
      if (savedState == null) {
        _vpnState = VpnState.disconnected;
        return;
      }

      final wasConnected = savedState['isConnected'] as bool? ?? false;
      final server = savedState['server'] as VpnServer?;
      final startTime = savedState['startTime'] as DateTime?;
      final connectionDuration = savedState['connectionDuration'] as Duration?;

      if (!wasConnected) {
        _vpnState = VpnState.disconnected;
        await _persistence.clearVpnState();
        return;
      }

      // Was connected — verify against the actual plugin stage.
      // For Android the plugin is lazy-initialised; init it now so we can
      // call stage() and read the foreground service state.
      if (Platform.isAndroid && _openVPN == null) {
        try {
          _openVPN = OpenVPN(
            onVpnStatusChanged: _onVpnStatusChanged,
            onVpnStageChanged: _onVpnStageChanged,
          );
          await _openVPN!.initialize();
        } catch (e) {
          _openVPN = null;
        }
      }

      bool isActuallyConnected = false;
      if (_openVPN != null) {
        try {
          final currentStage = await _openVPN!.stage();
          isActuallyConnected = (currentStage == VPNStage.connected);
        } catch (e) {
        }
      }

      // If OpenVPN is not connected, check WireGuard (tunnel may still be up).
      if (!isActuallyConnected && Platform.isAndroid) {
        try {
          final tempWg = WireGuard(
            onVpnStageChanged: (_, __) {},
            onVpnStatusChanged: (_) {},
          );
          await tempWg.initialize();
          final wgStage = await tempWg.stage();
          if (wgStage == WGStage.connected) {
            isActuallyConnected = true;
            // Re-use or create the real WireGuard instance so callbacks work.
            _wireGuard ??= WireGuard(
              onVpnStageChanged: _onWireGuardStageChanged,
              onVpnStatusChanged: _onWireGuardStatusChanged,
            );
            await _wireGuard!.initialize();
          }
        } catch (e) {
        }
      }

      // If OpenVPN is not connected, check OC (e.g. previous session used Poland/OC).
      if (!isActuallyConnected && Platform.isAndroid) {
        try {
          final tempOc = OpenConnect(
            onVpnStatusChanged: (_) {},
            onVpnStageChanged: (_, __) {},
          );
          final ocRunning = await tempOc.isServiceRunning();
          if (ocRunning) {
            isActuallyConnected = true;
            // Initialise the real OC instance so event callbacks work.
            _openConnect ??= OpenConnect(
              onVpnStatusChanged:
                  (_) {}, // OpenConnectStatus — not the same as VpnStatus
              onVpnStageChanged: _onOpenConnectStageChanged,
            );
            await _openConnect!.initialize();
          }
        } catch (e) {
        }
      }

      if (isActuallyConnected) {
        _currentServer = server;
        _connectionStartTime = startTime ?? DateTime.now();
        _totalConnectionTime = connectionDuration ?? Duration.zero;
        _vpnState = VpnState.connected;
        _startStatusUpdater();
      } else {
        // VPN is not running — clear the stale saved state.
        _vpnState = VpnState.disconnected;
        await _persistence.clearVpnState();
      }
    } catch (e) {
      _vpnState = VpnState.disconnected;
      await _persistence.clearVpnState();
    }
  }

  /// Initialize local notifications for VPN status
  Future<void> _initializeNotifications() async {
    try {
      _localNotifications = FlutterLocalNotificationsPlugin();

      // Android initialization
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      // iOS initialization
      const DarwinInitializationSettings initializationSettingsIOS =
          DarwinInitializationSettings(
            requestSoundPermission: false,
            requestBadgePermission: false,
            requestAlertPermission: false,
          );

      const InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsIOS,
          );

      await _localNotifications!.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: _onNotificationTapped,
      );

      // Create notification channels for Android
      if (Platform.isAndroid) {
        await _createNotificationChannels();
      }
    } catch (e) {}
  }

  /// Create notification channels for Android
  Future<void> _createNotificationChannels() async {
    if (_localNotifications == null) return;

    // VPN status notifications channel
    const AndroidNotificationChannel vpnChannel = AndroidNotificationChannel(
      _vpnChannelId,
      'VPN Status',
      description: 'VPN connection status notifications',
      importance: Importance.high,
      playSound: true,
      enableVibration: true,
      showBadge: false, // Disable badge to prevent duplicates
    );

    // VPN foreground service channel
    const AndroidNotificationChannel foregroundChannel =
        AndroidNotificationChannel(
          _vpnForegroundChannelId,
          'VPN Connection',
          description: 'Active VPN connection status',
          importance: Importance.low,
          playSound: false,
          enableVibration: false,
          showBadge: false,
        );

    await _localNotifications!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(vpnChannel);

    await _localNotifications!
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(foregroundChannel);
  }

  /// Handle notification taps
  void _onNotificationTapped(NotificationResponse notificationResponse) {
    // Handle disconnect action from notification
    if (notificationResponse.actionId == 'disconnect') {
      disconnect();
    }

    // Handle notification tap - could navigate to connection details
  }

  /// Simple OpenVPN initialization that happens on first connection
  Future<void> _ensureOpenVPNReady() async {
    if (_openVPN != null) return;

    try {
      _openVPN = OpenVPN(
        onVpnStatusChanged: _onVpnStatusChanged,
        onVpnStageChanged: _onVpnStageChanged,
      );

      // Initialize based on platform
      if (Platform.isIOS) {
        await _openVPN!.initialize(
          groupIdentifier: "group.com.albonik.vpn",
          providerBundleIdentifier: "com.albonik.vpn.VPNExtension",
          localizedDescription: "VPN MASTER Connection",
        );
      } else if (Platform.isAndroid) {
        await _openVPN!.initialize();
      }
    } catch (e) {
      // Retry once more for Android
      if (Platform.isAndroid && _openVPN != null) {
        try {
          await _openVPN!.initialize();
        } catch (e2) {
          throw Exception('Failed to initialize OpenVPN: $e2');
        }
      } else {
        throw Exception('Failed to initialize OpenVPN: $e');
      }
    }
  }

  Future<String> _getDeviceId() async {
    final prefs = await SharedPreferences.getInstance();
    String? deviceId = prefs.getString('device_id');

    if (deviceId == null) {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? 'unknown';
      } else {
        deviceId = 'unknown_device';
      }
      await prefs.setString('device_id', deviceId);
    }

    return deviceId;
  }

  void _onVpnStatusChanged(VpnStatus? status) {
    // Save raw plugin status so _startStatusUpdater can use the latest bytes.
    // Do NOT emit to _statusController here — _startStatusUpdater already
    // emits every second with the latest byte counters. Emitting here too
    // would cause two near-simultaneous events per second, making the speed
    // service calculate 0 KB/s on the duplicate (same-bytes) event.
    if (status != null) _lastPluginStatus = status;
  }

  Future<void> _onVpnStageChanged(VPNStage stage, String rawStage) async {

    switch (stage) {
      case VPNStage.prepare:
        _updateVpnState(VpnState.connecting);
        break;
      case VPNStage.connecting:
        _updateVpnState(VpnState.connecting);
        break;
      case VPNStage.authenticating:
        _updateVpnState(VpnState.authenticating);
        break;
      case VPNStage.connected:
        if (_isUserDisconnecting) {
          break;
        }
        _updateVpnState(VpnState.connected);
        // Only set connection start time if not already set (e.g. restored on app relaunch).
        _connectionStartTime ??= DateTime.now();
        _cancelConnectionTimer();
        _logConnection();
        // Note: OpenVPN plugin already shows its own notification with speed
        // stats + disconnect button. Showing a second Flutter notification
        // here would duplicate it, so we skip _showVpnConnectedNotification().
        _startStatusUpdater(); // Start periodic status updates

        // Save VPN state to persistence to prevent premium bypass
        if (_currentServer != null) {
          final connectionDuration = _connectionStartTime != null
              ? DateTime.now().difference(_connectionStartTime!)
              : null;

          await _persistence.saveVpnState(
            isConnected: true,
            server: _currentServer,
            startTime: _connectionStartTime,
            premiumTimeLeft: null, // Will be handled by purchase service
            connectionDuration: connectionDuration,
          );
        }
        break;
      case VPNStage.disconnected:
        // If we disconnected while trying to connect, this is an error —
        // UNLESS we are in the startup grace period.  Android fires a
        // 'disconnected' event at the very beginning of every new connection
        // as the VPN process passes through its previous state.  Treating that
        // as an error would flash a spurious CONNECTION ERROR screen.
        if (_vpnState == VpnState.connecting ||
            _vpnState == VpnState.authenticating) {
          final inGracePeriod =
              _suppressDisconnectedUntil != null &&
              DateTime.now().isBefore(_suppressDisconnectedUntil!);
          if (inGracePeriod) {
            break;
          }
          _updateVpnState(VpnState.error);
        } else {
          _suppressDisconnectedUntil = null;
          _updateVpnState(VpnState.disconnected);
        }

        _cancelConnectionTimer();
        _stopStatusUpdater(); // Stop periodic updates

        _logDisconnection();
        _showVpnDisconnectedNotification();
        _clearPersistentNotification();

        // Clear VPN state from persistence when disconnected
        await _persistence.clearVpnState();
        break;
      case VPNStage.denied:
        _updateVpnState(VpnState.denied);
        _cancelConnectionTimer();
        break;
      case VPNStage.error:
        _cancelConnectionTimer();
        _updateVpnState(VpnState.error);

        // Provide more specific error information
        if (rawStage.toLowerCase().contains('auth')) {
        } else if (rawStage.toLowerCase().contains('timeout')) {
        } else if (rawStage.toLowerCase().contains('network')) {
        }
        break;
      default:
        if (rawStage.toLowerCase().contains('wait')) {
          _updateVpnState(VpnState.waitConnection);
        } else if (rawStage.toLowerCase().contains('reconnect')) {
          _updateVpnState(VpnState.reconnecting);
        } else if (rawStage.toLowerCase().contains('noprocess')) {
          if (_vpnState == VpnState.connected) {}
        }
        break;
    }
  }

  void _updateVpnState(VpnState newState) {
    if (_vpnState != newState) {
      _vpnState = newState;
      // Defer stream emission to avoid mutating render objects during layout
      // (fixes: RenderRepaintBoundary mutated in RenderSliverFillViewport.performLayout)
      scheduleMicrotask(() {
        if (!_stateController.isClosed) {
          _stateController.add(_vpnState);
        }
      });
    }
  }

  /// Check if a server can be accessed based on user's premium status
  Future<bool> canAccessServer(VpnServer server) async {
    try {
      final purchaseService = PurchaseService();
      final isPremium = await purchaseService.checkPremiumStatus();

      if (isPremium) {
        return true;
      }

      // For free users, allow all connections for now
      return true;
    } catch (e) {
      return true;
    }
  }

  /// Quick connect to best free server
  Future<bool> quickConnect() async {
    try {
      final purchaseService = PurchaseService();
      final isPremium = await purchaseService.checkPremiumStatus();

      // Get list of servers and find best free server
      final servers = await ApiService.instance.getServers();
      if (servers.isNotEmpty) {
        // Free users can only quick-connect to free servers.
        // Premium users can quick-connect to any active server.
        final candidateServers = (isPremium
                ? servers.where((s) => s.isActive)
                : servers.where((s) => !s.premium && s.isActive))
            .toList();

        if (candidateServers.isNotEmpty) {
          candidateServers.sort((a, b) => a.order.compareTo(b.order));
          final bestServer = candidateServers.first;

          // Mark as auto-connect since user didn't manually select server
          _isAutoConnect = true;
          final result = await connectToServer(bestServer);
          _isAutoConnect = false;

          return result;
        }
      }
      return false;
    } catch (e) {
      _isAutoConnect = false;
      return false;
    }
  }

  Future<bool> connectToServer(VpnServer server, [int retryCount = 0]) async {
    try {
      // Check if service is initialized
      if (!_isInitialized) {
        await initialize();
      }

      // DEBUG: Log protocol detection

      // CRITICAL: Check protocol type and route to appropriate engine
      if (server.vpnProtocolType == 'wireguard') {
        return await _connectWireGuard(server);
      }

      if (server.vpnProtocolType == 'v2ray') {
        return await _connectV2Ray(server);
      }

      if (server.vpnProtocolType == 'openconnect') {
        return await _connectOpenConnect(server);
      }


      // Check if user can access this server
      final canAccess = await canAccessServer(server);
      if (!canAccess) {
        throw Exception('Premium subscription required to access this server');
      }

      // Always disconnect first unless we're in a clean disconnected/denied state.
      // This ensures vpnHelper.stopVPN() is called (resets vpnStart=false) so the
      // next startVPN() call is not silently skipped by VPNHelper.
      if (_vpnState != VpnState.disconnected && _vpnState != VpnState.denied) {
        await disconnect();
        await Future.delayed(const Duration(seconds: 2));
      }

      _currentServer = server;
      _updateVpnState(VpnState.connecting);

      // Check VPN permission first (Android)
      if (Platform.isAndroid) {
        final hasPermission = await isVpnPermissionGranted();
        if (!hasPermission) {
          final granted = await requestVpnPermission();
          if (!granted) {
            _updateVpnState(VpnState.denied);
            throw Exception(
              'VPN permission denied. Please grant VPN permission in settings.',
            );
          }
        }
      }

      // Android fires a spurious 'disconnected' event the moment the OpenVPN
      // event listener is registered (initial state flush).  Set the grace period
      // NOW — before _ensureOpenVPNReady() — so that event is silenced.
      if (Platform.isAndroid) {
        _suppressDisconnectedUntil = DateTime.now().add(
          const Duration(seconds: 5),
        );
      }

      // For iOS, ensure we're using the correct initialization
      if (Platform.isIOS && _openVPN == null) {
        await _ensureOpenVPNReady();
      }

      // Ensure OpenVPN is ready
      await _ensureOpenVPNReady();

      if (_openVPN == null) {
        throw Exception('OpenVPN initialization failed - cannot connect');
      }

      // For iOS: If this is a retry due to immediate disconnect, try reconfiguring
      if (Platform.isIOS && retryCount == 1) {
        await reconfigureVpn();
      }

      // Enhanced config fetching with multiple fallbacks
      String config = '';

      try {
        // Try to fetch config from API first
        config = await _fetchServerConfig(server);

        if (config.isEmpty) {
          throw Exception('Failed to fetch VPN configuration from server');
        }
      } catch (configError) {
        // OneConnect servers must use their embedded config — never fall back
        if (server.isOneConnect) {
          rethrow;
        }
        config = _createMinimalWorkingConfig(server);
      } // Start connection timeout timer (longer timeout for better reliability)
      _startConnectionTimer();

      // Enhanced connection with better error handling

      await _simpleConnect(config, server);

      // Set connection start time for logging
      _connectionStartTime = DateTime.now();

      return true;
    } catch (e) {
      _updateVpnState(VpnState.error);
      _cancelConnectionTimer();

      // Enhanced retry logic with different approaches
      if (retryCount < 2) {
        await Future.delayed(Duration(seconds: 3 + retryCount));

        if (retryCount == 0) {
          // First retry: Switch protocol (skip for OneConnect whose config embeds the protocol)
          if (server.isOneConnect) {
            return false;
          }

          final alternativeServer = VpnServer(
            id: server.id,
            name: server.name,
            ip: server.ip,
            country: server.country,
            countryCode: server.countryCode,
            flag: server.flag,
            premium: server.premium,
            latency: server.latency,
            configUrl: server.configUrl,
            isActive: server.isActive,
            load: server.load,
            protocol: server.protocol.toLowerCase() == 'tcp' ? 'UDP' : 'TCP',
            tcpPort: server.tcpPort,
            udpPort: server.udpPort,
            port: server.protocol.toLowerCase() == 'tcp'
                ? int.tryParse(server.udpPort) ?? 1194
                : int.tryParse(server.tcpPort) ?? 443,
            vpnUsername: server.vpnUsername,
            vpnPassword: server.vpnPassword,
            useFile: server.useFile,
            freeConnectDuration: server.freeConnectDuration,
            connectedDevices: server.connectedDevices,
            order: server.order,
          );

          return await connectToServer(alternativeServer, retryCount + 1);
        } else {
          // Second retry: Use ultra-basic config

          return await connectToServer(server, retryCount + 1);
        }
      }

      return false;
    }
  }

  /// Enhanced connection method with better error handling and logging
  /// Decrypt OneConnect credentials (every char at odd index, then reversed)
  static String _decryptOneConnect(String encrypted) {
    String str = '';
    for (int i = 0; i < encrypted.length; i++) {
      if ((i + 1) % 2 == 0) str = '$str${encrypted[i]}';
    }
    return str.split('').reversed.join();
  }

  Future<void> _simpleConnect(String config, VpnServer server) async {
    try {
      if (_openVPN == null) {
        throw Exception('OpenVPN not initialized');
      }


      // Validate config has minimum requirements
      if (!config.contains('client') || !config.contains('remote')) {
        throw Exception(
          'Invalid OpenVPN configuration - missing required directives',
        );
      }

      // Check if config needs username/password — only match uncommented lines
      final needsAuth = RegExp(r'^(?!;)\s*auth-user-pass\b', multiLine: true).hasMatch(config);
      final hasEmbeddedAuth = config.contains('<auth-user-pass>');

      // Decrypt credentials for OneConnect servers (encrypted storage format)
      final String effectiveUsername = server.isOneConnect
          ? _decryptOneConnect(server.vpnUsername)
          : server.vpnUsername;
      final String effectivePassword = server.isOneConnect
          ? _decryptOneConnect(server.vpnPassword)
          : server.vpnPassword;

      if (server.isOneConnect) {
      }

      final hasCredentials =
          effectiveUsername.isNotEmpty && effectivePassword.isNotEmpty;
      final hasCertificates =
          config.contains('<cert>') ||
          config.contains('<ca>') ||
          config.contains('<key>');


      // Handle different authentication types
      String finalConfig = config;

      // If credentials are embedded in <auth-user-pass> tags, remove them
      // because openvpn_flutter doesn't support inline auth
      if (hasEmbeddedAuth) {
        // Remove the embedded auth block and replace with simple directive
        final authRegex = RegExp(
          r'<auth-user-pass>.*?</auth-user-pass>',
          multiLine: true,
          dotAll: true,
        );
        finalConfig = finalConfig.replaceAll(authRegex, 'auth-user-pass');
      }

      // Check for certificate authentication issues
      // If config has both certificates AND requires auth-user-pass,
      // the OpenVPN server is using HYBRID authentication
      // Both certificates and username/password are required
      if (hasCertificates && needsAuth && !hasCredentials) {
        // We have certs and need auth but don't have credentials - this is a problem
        throw Exception(
          'Server requires username/password authentication but credentials are missing',
        );
      }

      // Don't modify the config if it has proper certificates and auth setup
      // Just pass it through as-is
      if (hasCertificates && needsAuth && hasCredentials) {
        // Perfect setup: certificates + username/password (hybrid auth)
        // Keep the config as-is, credentials will be passed separately
      }

      // Handle edge cases
      if (needsAuth && !hasCredentials && !hasCertificates) {
        // Config needs auth but we have no credentials and no certs
        throw Exception(
          'Server requires authentication but no credentials or certificates available',
        );
      }

      await _openVPN!.connect(
        finalConfig,
        server.name,
        username: hasCredentials ? effectiveUsername : null,
        password: hasCredentials ? effectivePassword : null,
        bypassPackages: [],
        certIsRequired: hasCertificates,
      );



      // For iOS, verify the connect call actually started the extension
      if (Platform.isIOS) {
      }

      // iOS VPN extension needs time to initialize before reporting status
      // Don't start status check immediately, let the normal callbacks work first
      if (Platform.isIOS) {
        // Give iOS VPN extension 5 seconds to start before polling
        Future.delayed(const Duration(seconds: 5), () {
          if (_vpnState == VpnState.connecting ||
              _vpnState == VpnState.authenticating) {
            _startStatusCheckTimer();
          }
        });
      } else {
        // Android can check immediately
        _startStatusCheckTimer();
      }
    } catch (e) {
      // Provide more specific error information
      if (e.toString().contains('permission')) {
        throw Exception('VPN permission denied - please check app permissions');
      } else if (e.toString().contains('network')) {
        throw Exception('Network error - please check internet connection');
      } else if (e.toString().contains('config')) {
        throw Exception('Configuration error - server config may be invalid');
      } else if (e.toString().contains('auth')) {
        throw Exception('Authentication failed - check server credentials');
      } else {
        throw Exception('VPN connection failed: ${e.toString()}');
      }
    }
  }

  /// Fetch actual OpenVPN config from server (like native Android app does)
  Future<String> _fetchServerConfig(VpnServer server) async {
    try {
      // OneConnect servers embed their full OVPN config inside providerPayload
      if (server.isOneConnect) {
        final ovpnConfig =
            server.providerPayload?['ovpnConfiguration'] as String?;
        if (ovpnConfig != null && ovpnConfig.isNotEmpty) {
          return ovpnConfig;
        }
        throw Exception('OneConnect server has no embedded OVPN configuration');
      }

      // Use the same API endpoint as native Android app: /get?id=serverId
      final serverId = int.tryParse(server.id) ?? 0;

      try {
        // Try to get config from API first
        final config = await ApiService.instance.getServerConfig(serverId);

        if (config.isNotEmpty) {
          return config;
        } else {
          return _createMinimalWorkingConfig(server);
        }
      } catch (apiError) {
        // If API fails, try fallback endpoint or create minimal config
        try {
          return await _tryFallbackConfig(server);
        } catch (fallbackError) {
          return _createMinimalWorkingConfig(server);
        }
      }
    } catch (e) {
      return _createMinimalWorkingConfig(server);
    }
  }

  /// Try alternative config sources
  Future<String> _tryFallbackConfig(VpnServer server) async {
    try {
      // Try direct minimal config generation

      return _createMinimalWorkingConfig(server);
    } catch (e) {
      return _createMinimalWorkingConfig(server);
    }
  }

  /// Create minimal working OpenVPN config that actually connects
  String _createMinimalWorkingConfig(VpnServer server) {
    try {
      // Determine if we should include authentication based on server credentials
      final hasCredentials =
          server.vpnUsername.isNotEmpty && server.vpnPassword.isNotEmpty;
      final authLine = hasCredentials
          ? 'auth-user-pass\nauth-nocache'
          : '# No authentication required';

      // Create a simplified config that should work without authentication issues
      final config =
          '''client
dev tun
proto ${server.protocol.toLowerCase()}
remote ${server.ip} ${server.port}
resolv-retry infinite
nobind
persist-key
persist-tun
verb 3
pull
redirect-gateway def1
dhcp-option DNS 8.8.8.8
dhcp-option DNS 8.8.4.4
$authLine
# Simplified config for ${hasCredentials ? 'authenticated' : 'passwordless'} connection
# Protocol: ${server.protocol} on port ${server.port}
# Generated on: ${DateTime.now().toIso8601String()}
''';
      return config;
    } catch (e) {
      // Ultra-basic fallback config
      return '''client
dev tun
proto ${server.protocol.toLowerCase()}
remote ${server.ip} ${server.port}
resolv-retry infinite
nobind
persist-key
persist-tun
verb 1
pull
''';
    }
  }

  /// Connect to WireGuard server
  Future<bool> _connectWireGuard(VpnServer server) async {
    try {

      // ✅ CRITICAL: Set current server for disconnect routing
      _currentServer = server;
      _updateVpnState(VpnState.connecting);

      // Initialize WireGuard engine if not already done
      if (_wireGuard == null) {
        _wireGuard = WireGuard(
          onVpnStatusChanged: _onWireGuardStatusChanged,
          onVpnStageChanged: _onWireGuardStageChanged,
        );
        await _wireGuard!.initialize();
      }

      // Fetch WireGuard config
      final serverId = int.tryParse(server.id) ?? 0;
      final String config;
      try {
        config = await ApiService.instance.getServerConfig(serverId);
      } catch (e) {
        // Backend returned an error (e.g. config file not uploaded yet)
        throw Exception(
          'WireGuard config not available. '
          'Upload a .conf file for this server in the admin panel. ($e)',
        );
      }

      if (config.isEmpty) {
        throw Exception(
          'WireGuard configuration not available. '
          'Upload a .conf file for this server in the admin panel.',
        );
      }

      // Basic sanity check – must look like a WireGuard config
      if (!config.contains('[Interface]') && !config.contains('[Peer]')) {
        throw Exception(
          'Invalid WireGuard configuration returned by server. '
          'Please check the uploaded .conf file in the admin panel.',
        );
      }


      // Connect using WireGuard
      await _wireGuard!.connect(config, server.name);


      // Start connection monitoring
      _startConnectionTimer();

      return true;
    } catch (e) {
      _updateVpnState(VpnState.error);
      return false;
    }
  }

  /// Handle WireGuard status changes
  void _onWireGuardStatusChanged(WireGuardStatus? status) {
    if (status != null) {
      // Timer is driven by _startStatusUpdater using _connectionStartTime; no null emit here.
    }
  }

  /// Handle WireGuard stage changes
  void _onWireGuardStageChanged(WGStage stage, String raw) {

    switch (stage) {
      case WGStage.preparing:
      case WGStage.connecting:
        _updateVpnState(VpnState.connecting);
        break;
      case WGStage.connected:
        _cancelConnectionTimer();
        _connectionStartTime ??= DateTime.now(); // preserve start time on app restore
        _updateVpnState(VpnState.connected);
        _logConnection();
        _startStatusUpdater();
        break;
      case WGStage.disconnecting:
        _updateVpnState(VpnState.disconnecting);
        break;
      case WGStage.disconnected:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.disconnected);
        break;
      case WGStage.error:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.error);
        break;
      case WGStage.denied:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.denied);
        break;
      case WGStage.unknown:
        // Don't update state for unknown stage
        break;
    }
  }

  // ── V2Ray / Xray engine ───────────────────────────────────────────────

  Future<bool> _connectV2Ray(VpnServer server) async {
    try {
      _currentServer = server;
      _updateVpnState(VpnState.connecting);

      _v2ray ??= V2Ray(
        onVpnStatusChanged: (status) {
        },
        onVpnStageChanged: _onV2RayStageChanged,
      );
      await _v2ray!.initialize();

      // Build Xray-core JSON config from server fields
      final sub = server.v2raySubProtocol ?? 'vless';
      String configJson;
      switch (sub) {
        case 'vmess':
          configJson = V2Ray.buildVmessConfig(
            address: server.ip,
            port: server.v2rayPort ?? server.port,
            uuid: server.v2rayUuid ?? '',
            network: server.v2rayNetwork ?? 'tcp',
            security: server.v2raySecurity ?? 'tls',
            serverName: server.v2rayHost,
            path: server.v2rayPath,
          );
          break;
        case 'trojan':
          configJson = V2Ray.buildTrojanConfig(
            address: server.ip,
            port: server.v2rayPort ?? server.port,
            password: server.v2rayUuid ?? '',
            serverName: server.v2rayHost,
          );
          break;
        case 'shadowsocks':
          configJson = V2Ray.buildShadowsocksConfig(
            address: server.ip,
            port: server.v2rayPort ?? server.port,
            password: server.v2rayUuid ?? '',
            method: server.v2raySecurity ?? 'chacha20-ietf-poly1305',
          );
          break;
        case 'vless':
        default:
          configJson = V2Ray.buildVlessConfig(
            address: server.ip,
            port: server.v2rayPort ?? server.port,
            uuid: server.v2rayUuid ?? '',
            network: server.v2rayNetwork ?? 'tcp',
            security: server.v2raySecurity ?? 'reality',
            serverName: server.v2rayHost,
            publicKey: server.v2rayPublicKey,
            shortId: server.v2rayShortId,
          );
      }

      await _v2ray!.connect(
        configJson,
        server.name,
        subProtocol: V2RaySubProtocol.values.firstWhere(
          (e) => e.name == sub,
          orElse: () => V2RaySubProtocol.vless,
        ),
      );

      _startConnectionTimer();
      return true;
    } catch (e) {
      _updateVpnState(VpnState.error);
      return false;
    }
  }

  void _onV2RayStageChanged(V2RayStage stage, String raw) {
    switch (stage) {
      case V2RayStage.preparing:
      case V2RayStage.connecting:
        _updateVpnState(VpnState.connecting);
        break;
      case V2RayStage.connected:
        _cancelConnectionTimer();
        _connectionStartTime = DateTime.now();
        _updateVpnState(VpnState.connected);
        _logConnection();
        _startStatusUpdater();
        break;
      case V2RayStage.disconnecting:
        _updateVpnState(VpnState.disconnecting);
        break;
      case V2RayStage.disconnected:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.disconnected);
        break;
      case V2RayStage.error:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.error);
        break;
      case V2RayStage.denied:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.denied);
        break;
      case V2RayStage.unknown:
        break;
    }
  }

  // ── OpenConnect (Cisco AnyConnect) engine ─────────────────────────────

  Future<bool> _connectOpenConnect(VpnServer server) async {
    try {
      _currentServer = server;
      _updateVpnState(VpnState.connecting);

      // Cancel any previous pending completer but do NOT create a new one yet.
      // initialize() broadcasts OCStage.disconnected which would prematurely
      // complete a Completer created here — the new Completer is created AFTER
      // initialize() returns so that stale stage events are ignored.
      _ocCompleter?.complete(false);
      _ocCompleter = null;

      _openConnect ??= OpenConnect(
        onVpnStatusChanged: (status) {
        },
        onVpnStageChanged: _onOpenConnectStageChanged,
      );
      await _openConnect!.initialize();

      // Restore server reference — initialize()'s OCStage.disconnected handler
      // clears _currentServer; set it again before the real connection starts.
      _currentServer = server;

      // Now safe to create the Completer: no spurious stages will complete it.
      _ocCompleter = Completer<bool>();

      await _openConnect!.connect(
        serverUrl: server.ocServerUrl ?? 'https://${server.ip}:${server.port}',
        name: server.name,
        username: server.ocUsername ?? server.vpnUsername,
        password: server.ocPassword ?? server.vpnPassword,
        authGroup: server.ocAuthGroup,
        servercert: server.ocServercert,
      );

      // Wait up to 60 s for the tunnel to actually come up (or fail)
      final connected = await _ocCompleter!.future.timeout(
        const Duration(seconds: 60),
        onTimeout: () {
          _updateVpnState(VpnState.error);
          return false;
        },
      );
      _ocCompleter = null;
      return connected;
    } catch (e) {
      _ocCompleter = null;
      _updateVpnState(VpnState.error);
      return false;
    }
  }

  void _onOpenConnectStageChanged(OCStage stage, String raw) {
    switch (stage) {
      case OCStage.preparing:
      case OCStage.connecting:
      case OCStage.authenticating:
        _updateVpnState(VpnState.connecting);
        break;
      case OCStage.connected:
        _cancelConnectionTimer();
        _connectionStartTime = DateTime.now();
        _updateVpnState(VpnState.connected);
        _logConnection();
        _startStatusUpdater();
        if (_ocCompleter != null && !_ocCompleter!.isCompleted) {
          _ocCompleter!.complete(true);
        }
        break;
      case OCStage.disconnecting:
        _updateVpnState(VpnState.disconnecting);
        break;
      case OCStage.disconnected:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.disconnected);
        if (_ocCompleter != null && !_ocCompleter!.isCompleted) {
          _ocCompleter!.complete(false);
        }
        break;
      case OCStage.error:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.error);
        if (_ocCompleter != null && !_ocCompleter!.isCompleted) {
          _ocCompleter!.complete(false);
        }
        break;
      case OCStage.denied:
        _cancelConnectionTimer();
        _stopStatusUpdater();
        _connectionStartTime = null;
        _currentServer = null;
        _updateVpnState(VpnState.denied);
        if (_ocCompleter != null && !_ocCompleter!.isCompleted) {
          _ocCompleter!.complete(false);
        }
        break;
      case OCStage.unknown:
        break;
    }
  }

  /// Start connection timeout timer with enhanced monitoring
  void _startConnectionTimer() {
    _connectionTimer?.cancel();

    // Timeout for connection attempts (40 seconds for WireGuard, 60 for OpenVPN)
    final timeout = _currentServer?.vpnProtocolType == 'wireguard'
        ? const Duration(seconds: 40)
        : const Duration(seconds: 60);

    _connectionTimer = Timer(timeout, () {
      if (_vpnState == VpnState.connecting ||
          _vpnState == VpnState.authenticating ||
          _vpnState == VpnState.waitConnection) {

        // Force disconnect based on protocol
        if (_currentServer?.vpnProtocolType == 'wireguard' &&
            _wireGuard != null) {
          _wireGuard!.disconnect();
        } else if (_currentServer?.vpnProtocolType == 'openconnect' &&
            _openConnect != null) {
          _openConnect!.disconnect();
        } else if (_openVPN != null) {
          _openVPN!.disconnect();
        }

        _currentServer = null;
        _connectionStartTime = null;
        _updateVpnState(VpnState.error);
      }
    });
  }

  /// Cancel connection timer
  void _cancelConnectionTimer() {
    _connectionTimer?.cancel();
    _connectionTimer = null;
    _statusCheckTimer?.cancel();
    _statusCheckTimer = null;
  }

  /// Start polling VPN status to detect connection
  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();

    int checkCount = 0;
    const maxChecks = 25; // Check for up to 50 seconds (25 * 2 seconds)

    // Check status every 2 seconds during connection attempt
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 2), (
      timer,
    ) async {
      checkCount++;

      if (_vpnState == VpnState.connecting ||
          _vpnState == VpnState.authenticating) {
        // Only log every 5th check to reduce spam
        if (checkCount % 5 == 0) {
        }

        // Stop checking after max attempts
        if (checkCount >= maxChecks) {
          timer.cancel();
        }
      } else {
        // Stop checking once we're connected or disconnected
        timer.cancel();
      }
    });
  }

  Future<void> disconnect() async {
    _isUserDisconnecting = true;
    try {
      final protocol = _currentServer?.vpnProtocolType.toLowerCase();

      _updateVpnState(VpnState.disconnecting);
      _cancelConnectionTimer();

      // Try protocol-specific disconnect first, then run generic fallbacks.
      if (protocol == 'wireguard' && _wireGuard != null) {
        try {
          await _wireGuard!.disconnect();
        } catch (e) {
        }
      }

      if (protocol == 'v2ray' && _v2ray != null) {
        try {
          await _v2ray!.disconnect();
        } catch (e) {
        }
      }

      // OpenConnect fallback: always try when protocol is OC OR when stage is not disconnected.
      if (protocol == 'openconnect' || _vpnState != VpnState.disconnected) {
        try {
          _openConnect ??= OpenConnect(
            onVpnStatusChanged: (_) {},
            onVpnStageChanged: _onOpenConnectStageChanged,
          );
          final ocRunning = await _openConnect!.isServiceRunning();
          if (ocRunning || protocol == 'openconnect') {
            await _openConnect!.disconnect();
          }
        } catch (e) {
        }
      }

      // OpenVPN fallback: do not depend on _currentServer being present.
      try {
        _openVPN ??= OpenVPN(
          onVpnStatusChanged: _onVpnStatusChanged,
          onVpnStageChanged: _onVpnStageChanged,
        );
        if (Platform.isAndroid) {
          await _openVPN!.initialize();
        } else if (Platform.isIOS) {
          await _openVPN!.initialize(
            groupIdentifier: "group.com.albonik.vpn",
            providerBundleIdentifier: "com.albonik.vpn.VPNExtension",
            localizedDescription: "VPN MASTER Connection",
          );
        }
        _openVPN!.disconnect();
        for (int i = 0; i < 30; i++) {
          await Future.delayed(const Duration(milliseconds: 100));
          if (_vpnState == VpnState.disconnected) break;
        }
      } catch (e) {
      }

      // Clear server and connection state
      _currentServer = null;
      _connectionStartTime = null;

      // If native plugin never fired disconnected, force state now
      if (_vpnState != VpnState.disconnected) {
        _stopStatusUpdater();
        _clearPersistentNotification();
        _updateVpnState(VpnState.disconnected);
      }

      // Clear VPN state from persistence to prevent stale state
      await _persistence.clearVpnState();

    } catch (e) {
      _updateVpnState(VpnState.error);
    } finally {
      _isUserDisconnecting = false;
    }
  }

  Future<void> _logConnection() async {
    if (_currentServer != null && _deviceId != null) {
      try {
        // Use the _isAutoConnect flag to determine connection type
        // Manual connections (false) are tracked in country stats
        // Auto connections (true) are not tracked in country stats
        await ApiService.instance.logConnect(
          _currentServer!.id,
          _deviceId!,
          isAuto: _isAutoConnect,
        );
      } catch (e) {}
    }
  }

  Future<void> _logDisconnection() async {
    if (_currentServer != null &&
        _deviceId != null &&
        _connectionStartTime != null) {
      try {
        final duration = DateTime.now().difference(_connectionStartTime!);
        await ApiService.instance.logDisconnect(
          _currentServer!.id,
          _deviceId!,
          duration,
        );
      } catch (e) {}
    }
    _connectionStartTime = null;
  }

  Future<bool> isConnected() async {
    try {
      return _vpnState == VpnState.connected;
    } catch (e) {
      return false;
    }
  }

  Future<VpnStatus?> getVpnStatus() async {
    try {
      final duration = _connectionStartTime != null
          ? DateTime.now().difference(_connectionStartTime!).toString()
          : '00:00:00';

      return VpnStatus(
        connectedOn: _connectionStartTime ?? DateTime.now(),
        duration: duration,
      );
    } catch (e) {
      return null;
    }
  }

  // Check if VPN permission is granted (Android)
  Future<bool> isVpnPermissionGranted() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('axe_vpn/vpn_permission');
        return await platform.invokeMethod('isVpnPermissionGranted') ?? false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  // Request VPN permission (Android)
  Future<bool> requestVpnPermission() async {
    try {
      if (Platform.isAndroid) {
        const platform = MethodChannel('axe_vpn/vpn_permission');
        return await platform.invokeMethod('requestVpnPermission') ?? false;
      }
      return true;
    } catch (e) {
      return false;
    }
  }

  /// Reconfigure VPN (iOS) - fixes "Update Required" issue
  Future<bool> reconfigureVpn() async {
    if (!Platform.isIOS) return false;

    try {

      // Re-initialize OpenVPN which will recreate the profile
      _openVPN = OpenVPN(
        onVpnStatusChanged: _onVpnStatusChanged,
        onVpnStageChanged: _onVpnStageChanged,
      );

      await _openVPN!.initialize(
        groupIdentifier: "group.com.albonik.vpn",
        providerBundleIdentifier: "com.albonik.vpn.VPNExtension",
        localizedDescription: "VPN MASTER Connection",
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  void dispose() {
    _connectionTimer?.cancel();
    _stateController.close();
    _statusController.close();
  }

  /// Re-sync the Flutter VPN state with the actual native service state.
  ///
  /// Called when the app resumes from background so that:
  ///  - If the user tapped Disconnect in the notification while the app was
  ///    minimised, the UI immediately reflects the disconnected state.
  ///  - If the OC foreground service died for any reason, the UI shows NOT
  ///    PROTECTED instead of a stale PROTECTED screen.
  ///
  /// Only runs when the app believes it is connected — avoids interfering
  /// with a fresh connection attempt.
  Future<void> resyncVpnState() async {
    if (!Platform.isAndroid) return;
    if (_vpnState != VpnState.connected) return;

    try {
      bool isActuallyConnected = false;

      // Check OpenVPN stage
      if (_openVPN != null) {
        final stage = await _openVPN!.stage();
        isActuallyConnected = (stage == VPNStage.connected);
      }

      // Check OC stage (static flag is updated by the Java service)
      // We query via method channel to avoid re-initialising the plugin.
      if (!isActuallyConnected && _openConnect != null) {
        try {
          final ocStage = await _openConnect!.stage();
          isActuallyConnected = (ocStage == OCStage.connected);
        } catch (_) {}
      }

      // Check WireGuard stage
      if (!isActuallyConnected && _wireGuard != null) {
        try {
          final wgStage = await _wireGuard!.stage();
          isActuallyConnected = (wgStage == WGStage.connected);
        } catch (_) {}
      }

      if (!isActuallyConnected) {
        _updateVpnState(VpnState.disconnected);
        _stopStatusUpdater();
        await _persistence.clearVpnState();
      }
    } catch (e) {
    }
  }

  /// Auto-connect to the best available server
  Future<bool> autoConnect() async {
    try {
      // Get list of servers
      final apiService = ApiService.instance;
      final servers = await apiService.getServers();

      if (servers.isEmpty) {
        return false;
      }

      // Filter active free servers if user is not premium
      final purchaseService = PurchaseService();
      final isPremium = await purchaseService.checkPremiumStatus();

      List<VpnServer> availableServers;
      if (isPremium) {
        availableServers = servers.where((s) => s.isActive).toList();
      } else {
        availableServers = servers
            .where((s) => s.isActive && !s.premium)
            .toList();
      }

      if (availableServers.isEmpty) {
        return false;
      }

      // Sort by order (lower is better) and select the best one
      availableServers.sort((a, b) => a.order.compareTo(b.order));
      final bestServer = availableServers.first;

      // Set a flag to indicate this is an auto-connect for logging
      _isAutoConnect = true;
      final result = await connectToServer(bestServer);
      _isAutoConnect = false;

      return result;
    } catch (e) {
      _isAutoConnect = false;
      return false;
    }
  }

  /// Handle kill switch functionality
  Future<void> handleKillSwitch(bool enable) async {
    try {
      if (enable) {
        // In a real implementation, you would block internet traffic here
        // This could involve setting firewall rules or routing all traffic through a blocked interface
        await _enableKillSwitch();
      } else {
        await _disableKillSwitch();
      }
    } catch (e) {}
  }

  Future<void> _enableKillSwitch() async {
    // Implementation would depend on platform
    // For Android: Could use VpnService to route all traffic through VPN interface
    // For iOS: Could use NEPacketTunnelProvider
  }

  Future<void> _disableKillSwitch() async {
    // Restore normal internet routing
  }

  /// Check if kill switch should be activated
  bool shouldActivateKillSwitch() {
    // Kill switch should activate if:
    // 1. VPN was connected and suddenly disconnected
    // 2. Kill switch setting is enabled
    // 3. Disconnection was not user-initiated
    return _vpnState == VpnState.disconnected && _currentServer != null;
  }

  /// Attempt to reconnect to the last connected server
  Future<bool> reconnectToLastServer() async {
    if (_currentServer != null) {
      return await connectToServer(_currentServer!);
    }
    return false;
  }

  /// Show VPN connected notification with server details
  Future<void> _showVpnConnectedNotification() async {
    if (_localNotifications == null || _currentServer == null) return;

    try {
      const AndroidNotificationDetails androidDetails =
          AndroidNotificationDetails(
            _vpnChannelId,
            'VPN Status',
            channelDescription: 'VPN connection status notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            showWhen: true,
            color: Color(0xFF10B981),
            icon: '@mipmap/ic_launcher',
          );

      const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      );

      const NotificationDetails platformDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      await _localNotifications!.show(
        0,
        '🔒 VPN Connected',
        'Connected to ${_currentServer!.name} (${_currentServer!.country})',
        platformDetails,
        payload: 'vpn_connected',
      );
    } catch (e) {}
  }

  /// Show VPN disconnected notification
  Future<void> _showVpnDisconnectedNotification() async {
    if (_localNotifications == null) return;

    try {
      const AndroidNotificationDetails androidPlatformChannelSpecifics =
          AndroidNotificationDetails(
            _vpnChannelId,
            'VPN Status',
            channelDescription: 'VPN connection status notifications',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            showWhen: true,
            color: Color(0xFFEF4444), // Red color
            icon: '@mipmap/ic_launcher',
          );

      const DarwinNotificationDetails iOSPlatformChannelSpecifics =
          DarwinNotificationDetails(
            subtitle: 'VPN connection ended',
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          );

      const NotificationDetails platformChannelSpecifics = NotificationDetails(
        android: androidPlatformChannelSpecifics,
        iOS: iOSPlatformChannelSpecifics,
      );

      final serverName = _currentServer?.name ?? 'VPN Server';
      final duration = _connectionStartTime != null
          ? DateTime.now().difference(_connectionStartTime!)
          : Duration.zero;

      final durationText = duration.inMinutes > 0
          ? '${duration.inMinutes}m ${duration.inSeconds % 60}s'
          : '${duration.inSeconds}s';

      await _localNotifications!.show(
        0, // Same ID to replace the connected notification
        '🔓 VPN Disconnected',
        'Disconnected from $serverName (Session: $durationText)',
        platformChannelSpecifics,
        payload: 'vpn_disconnected',
      );
    } catch (e) {}
  }

  /// Clear persistent notification when VPN disconnects
  Future<void> _clearPersistentNotification() async {
    if (_localNotifications == null) return;

    try {
      await _localNotifications!.cancel(
        0,
      ); // Cancel regular notification if any
      await _localNotifications!.cancel(1); // Cancel persistent notification
    } catch (e) {}
  }

  /// Start periodic status updates to keep UI synchronized
  void _startStatusUpdater() {
    _stopStatusUpdater(); // Stop any existing timer

    _statusUpdateTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_vpnState == VpnState.connected && _connectionStartTime != null) {
        final duration = DateTime.now().difference(_connectionStartTime!);
        final durationString = _formatDuration(duration);

        // Include the last-known byte counters from the plugin so the speed
        // service doesn't receive null-byte events every second and calculate
        // a spurious 0 KB/s reading.
        final status = VpnStatus(
          connectedOn: _connectionStartTime!,
          duration: durationString,
          byteIn: _lastPluginStatus?.byteIn,
          byteOut: _lastPluginStatus?.byteOut,
          packetsIn: _lastPluginStatus?.packetsIn,
          packetsOut: _lastPluginStatus?.packetsOut,
        );

        _statusController.add(status);
      }
    });
  }

  /// Stop periodic status updates
  void _stopStatusUpdater() {
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = null;
  }

  /// Format duration to HH:MM:SS format
  String _formatDuration(Duration duration) {
    final hours = duration.inHours.toString().padLeft(2, '0');
    final minutes = (duration.inMinutes % 60).toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$hours:$minutes:$seconds';
  }
}
