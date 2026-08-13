import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../core/api/api_service.dart';
import '../../core/services/vpn_service.dart';
import '../../core/services/vpn_state.dart';
import '../../core/services/vpn_notification_service.dart';
import '../../core/services/network_speed_service.dart';
import '../../services/subscription_service.dart';
import '../../services/reward_video_service.dart';
import '../../services/premium_server_unlock_service.dart';
import '../../providers/auth_providers.dart';
import '../../providers/subscription_provider.dart';
import '../../services/ads_popup_config_service.dart';

// Ads Popup Config Provider - fetches from API with auth token
final adsPopupConfigProvider = FutureProvider<AdsPopupConfig>((ref) async {
  return AdsPopupConfigService().getAdsPopupConfig(forceRefresh: true);
});

// VPN Service Provider - Using OpenVPN only
final vpnServiceProvider = Provider<VpnService>((ref) {
  return VpnService.instance;
});

// VPN Notification Service Provider
final vpnNotificationServiceProvider = Provider<VpnNotificationService>((ref) {
  return VpnNotificationService();
});

// Network Speed Service Provider
final networkSpeedServiceProvider = Provider<NetworkSpeedService>((ref) {
  return NetworkSpeedService.instance;
});

// API Service Provider
final apiServiceProvider = Provider<ApiService>((ref) {
  return ApiService.instance;
});

// Subscription Service Provider
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  return SubscriptionService();
});

// VPN State Provider
final vpnStateProvider = StreamProvider<VpnState>((ref) {
  final vpnService = ref.watch(vpnServiceProvider);
  return vpnService.vpnStateStream;
});

// Network Speed Provider
final networkSpeedProvider = StreamProvider<NetworkSpeedData>((ref) {
  final speedService = ref.watch(networkSpeedServiceProvider);
  return speedService.speedStream;
});

// Subscription Status Provider
final subscriptionStatusProvider = FutureProvider.family<bool, String>((
  ref,
  userId,
) async {
  final subscriptionService = ref.watch(subscriptionServiceProvider);

  // Auto sync if needed
  await subscriptionService.autoSyncIfNeeded(userId);

  return subscriptionService.hasActiveSubscription;
});

// Active Subscription Provider
final activeSubscriptionProvider = StateProvider<Subscription?>((ref) {
  return null;
});

// Current Server Provider
final currentServerProvider =
    StateNotifierProvider<CurrentServerNotifier, VpnServer?>((ref) {
      return CurrentServerNotifier();
    });

class CurrentServerNotifier extends StateNotifier<VpnServer?> {
  CurrentServerNotifier() : super(null) {
    _loadPersistedServer();
  }

  Future<void> _loadPersistedServer() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final serverId = prefs.getString('current_server_id');
      if (serverId != null) {
        // The actual server object will need to be loaded when servers are available
        // This is handled in the home screen initialization
        debugPrint('📋 Found persisted server ID: $serverId');
      }
    } catch (e) {
      debugPrint('❌ Error loading persisted server: $e');
    }
  }

  Future<void> setServer(VpnServer? server) async {
    state = server;
    final prefs = await SharedPreferences.getInstance();
    if (server != null) {
      await prefs.setString('current_server_id', server.id);
      debugPrint('💾 Server saved: ${server.name}');
    } else {
      await prefs.remove('current_server_id');
      debugPrint('🗑️ Server selection cleared');
    }
  }

  Future<String?> getPersistedServerId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('current_server_id');
  }
}

// Servers List Provider - Robust version with error handling
final serversProvider = FutureProvider<List<VpnServer>>((ref) async {
  try {
    final apiService = ref.watch(apiServiceProvider);
    debugPrint('🌐 Fetching servers from API...');

    // Don't pass subscription status - get ALL servers and handle premium logic in UI
    final servers = await apiService.getServersWithProtocols();

    debugPrint('✅ Successfully loaded ${servers.length} servers');
    for (final server in servers) {
      debugPrint('📍 Server: ${server.name} - Premium: ${server.premium}');
    }

    return servers;
  } catch (e, stackTrace) {
    debugPrint('❌ Error loading servers: $e');
    debugPrint('🔍 Stack trace: $stackTrace');
    rethrow;
  }
});

// Enhanced Servers Provider with protocol filtering
final serversByProtocolProvider = Provider.family<List<VpnServer>, String?>((
  ref,
  protocolFilter,
) {
  final serversAsync = ref.watch(serversProvider);

  return serversAsync.when(
    data: (servers) {
      if (protocolFilter == null) return servers;

      switch (protocolFilter.toLowerCase()) {
        case 'openvpn':
          return servers.where((server) => server.supportsOpenVPN).toList();
        default:
          return servers;
      }
    },
    loading: () => [],
    error: (_, __) => [],
  );
});

// Favorite Servers Provider
final favoriteServersProvider =
    StateNotifierProvider<FavoriteServersNotifier, Set<String>>((ref) {
      return FavoriteServersNotifier();
    });

class FavoriteServersNotifier extends StateNotifier<Set<String>> {
  FavoriteServersNotifier() : super(<String>{}) {
    _loadFavorites();
  }

  Future<void> _loadFavorites() async {
    final prefs = await SharedPreferences.getInstance();
    final favorites = prefs.getStringList('favorite_servers') ?? [];
    state = favorites.toSet();
  }

  Future<void> toggleFavorite(String serverId) async {
    final newState = Set<String>.from(state);
    if (newState.contains(serverId)) {
      newState.remove(serverId);
    } else {
      newState.add(serverId);
    }
    state = newState;

    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('favorite_servers', newState.toList());
  }

  bool isFavorite(String serverId) {
    return state.contains(serverId);
  }
}

// Premium Status Provider
final premiumStatusProvider =
    StateNotifierProvider<PremiumStatusNotifier, bool>((ref) {
      return PremiumStatusNotifier(ref);
    });

class PremiumStatusNotifier extends StateNotifier<bool> {
  final Ref _ref;

  PremiumStatusNotifier(this._ref) : super(false) {
    _loadPremiumStatus();
    _listenToAuthChanges();
    _listenToSubscriptionChanges();
  }

  void _listenToSubscriptionChanges() {
    // Sync with subscription provider
    _ref.listen(subscriptionProvider, (previous, next) {
      if (next.isPremium != state) {
        print(
          '💎 Syncing premium status from subscription provider: ${next.isPremium}',
        );
        state = next.isPremium;
      }
    });
  }

  void _listenToAuthChanges() {
    // Listen to auth state changes
    _ref.listen(authStateProvider, (previous, next) {
      final user = next.firebaseUser;
      if (user == null) {
        // User logged out - clear premium status
        print('🔐 User logged out - clearing premium status');
        _clearPremiumStatus();
      } else {
        // User logged in - subscription provider will handle status updates
        print(
          '🔐 User logged in - subscription provider will sync premium status',
        );
      }
    });
  }

  Future<void> _loadPremiumStatus() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool('is_premium') ?? false;
      print('[PremiumStatus] Loaded from cache: isPremium=$state');
    } catch (e) {
      state = false;
    }
  }

  Future<void> _savePremiumStatus(bool isPremium) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('is_premium', isPremium);
    } catch (e) {
      print('[PremiumStatus] Error saving: $e');
    }
  }

  Future<void> setPremiumStatus(bool isPremium) async {
    if (state != isPremium) {
      state = isPremium;
      await _savePremiumStatus(isPremium);
      print('[PremiumStatus] Manually set: isPremium=$isPremium');
    }
  }

  Future<void> _clearPremiumStatus() async {
    state = false;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', false);
    await prefs.remove('premium_status');
    await prefs.remove('subscription_status');
    await prefs.remove('user_purchases');
    print('[PremiumStatus] Cleared premium status');
  }

  Future<void> forceRefresh() async {
    // Trigger subscription provider refresh instead
    final authState = _ref.read(authStateProvider);
    if (authState.firebaseUser != null) {
      await _ref
          .read(subscriptionProvider.notifier)
          .checkSubscriptionStatus(
            authState.firebaseUser!.uid,
            forceRefresh: true,
          );
    }
  }

  Future<void> clearPremiumStatus() async {
    await _clearPremiumStatus();
  }
}

// Auto Connect Provider
final autoConnectProvider = StateNotifierProvider<BooleanSettingNotifier, bool>(
  (ref) {
    return BooleanSettingNotifier('auto_connect', false);
  },
);

// Kill Switch Provider
final killSwitchProvider = StateNotifierProvider<BooleanSettingNotifier, bool>((
  ref,
) {
  return BooleanSettingNotifier('kill_switch', false);
});

// Notifications Provider
final notificationsProvider =
    StateNotifierProvider<BooleanSettingNotifier, bool>((ref) {
      return BooleanSettingNotifier('notifications', true);
    });

// Protocol Provider
final protocolProvider = StateNotifierProvider<BooleanSettingNotifier, bool>((
  ref,
) {
  return BooleanSettingNotifier(
    'use_udp_protocol',
    true,
  ); // true = UDP, false = TCP
});

class BooleanSettingNotifier extends StateNotifier<bool> {
  final String key;
  final bool defaultValue;

  BooleanSettingNotifier(this.key, this.defaultValue) : super(defaultValue) {
    _loadSetting();
  }

  Future<void> _loadSetting() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(key) ?? defaultValue;
  }

  Future<void> toggle() async {
    state = !state;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, state);
  }

  Future<void> setValue(bool value) async {
    state = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}

// App Settings Provider
final appSettingsProvider = FutureProvider<AppSettings>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return await apiService.getSettings();
});

// AdMob Config Provider
final adMobConfigProvider = FutureProvider<AdMobConfig>((ref) async {
  final apiService = ref.watch(apiServiceProvider);
  return await apiService.getAdIds();
});

// Connection Statistics Provider
final connectionStatsProvider =
    StateNotifierProvider<ConnectionStatsNotifier, ConnectionStats>((ref) {
      return ConnectionStatsNotifier();
    });

class ConnectionStatsNotifier extends StateNotifier<ConnectionStats> {
  ConnectionStatsNotifier() : super(ConnectionStats()) {
    _loadStats();
  }

  Future<void> _loadStats() async {
    final prefs = await SharedPreferences.getInstance();
    final totalConnections = prefs.getInt('total_connections') ?? 0;
    final totalTimeSeconds = prefs.getInt('total_time_seconds') ?? 0;
    final dataUsageMB = prefs.getDouble('data_usage_mb') ?? 0.0;

    state = ConnectionStats(
      totalConnections: totalConnections,
      totalTime: Duration(seconds: totalTimeSeconds),
      dataUsageMB: dataUsageMB,
    );
  }

  Future<void> incrementConnections() async {
    final newStats = state.copyWith(
      totalConnections: state.totalConnections + 1,
    );
    state = newStats;
    await _saveStats();
  }

  Future<void> addConnectionTime(Duration duration) async {
    final newStats = state.copyWith(
      totalTime: Duration(
        seconds: state.totalTime.inSeconds + duration.inSeconds,
      ),
    );
    state = newStats;
    await _saveStats();
  }

  Future<void> addDataUsage(double mb) async {
    final newStats = state.copyWith(dataUsageMB: state.dataUsageMB + mb);
    state = newStats;
    await _saveStats();
  }

  Future<void> _saveStats() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('total_connections', state.totalConnections);
    await prefs.setInt('total_time_seconds', state.totalTime.inSeconds);
    await prefs.setDouble('data_usage_mb', state.dataUsageMB);
  }
}

// Free Connection Timer Provider
final freeConnectionTimerProvider =
    StateNotifierProvider<
      FreeConnectionTimerNotifier,
      FreeConnectionTimerState
    >((ref) {
      return FreeConnectionTimerNotifier();
    });

class FreeConnectionTimerNotifier
    extends StateNotifier<FreeConnectionTimerState> {
  FreeConnectionTimerNotifier() : super(FreeConnectionTimerState());

  Timer? _timer;

  void startTimer(VpnServer server, bool isPremium) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('⏲️ FREE TIMER START REQUEST');
    debugPrint('   Server: ${server.name}');
    debugPrint('   Duration: ${server.freeConnectDuration} minutes');
    debugPrint('   Is Premium: $isPremium');
    debugPrint('═══════════════════════════════════════');

    if (isPremium) {
      // Premium users have no time limits
      debugPrint('👑 Premium user - no timer needed');
      state = FreeConnectionTimerState(
        isActive: false,
        isPremium: true,
        server: server,
      );
      return;
    }

    // For free users, check if server has time limit (0 = unlimited)
    if (server.freeConnectDuration == 0) {
      // Server allows unlimited free connection
      debugPrint('♾️ Server ${server.name} allows unlimited free connection');

      state = FreeConnectionTimerState(
        isActive: false,
        isPremium: false,
        server: server,
        remainingSeconds: 0,
        totalSeconds: 0,
      );
      return;
    }

    final duration = server.freeConnectDuration;
    final totalSeconds = duration * 60; // Convert minutes to seconds

    debugPrint(
      '✅ Starting free connection timer: ${duration} minutes (${totalSeconds} seconds) for ${server.name}',
    );

    state = FreeConnectionTimerState(
      isActive: true,
      isPremium: false,
      server: server,
      remainingSeconds: totalSeconds,
      totalSeconds: totalSeconds,
    );

    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.remainingSeconds <= 0) {
        timer.cancel();
        debugPrint('═══════════════════════════════════════');
        debugPrint('⏰ FREE CONNECTION TIMER EXPIRED!');
        debugPrint('   Server: ${state.server?.name}');
        debugPrint('   Disconnecting VPN immediately (background-safe)');
        debugPrint('═══════════════════════════════════════');
        // Disconnect directly from the notifier — works even when app is backgrounded
        try {
          VpnService.instance.disconnect();
        } catch (e) {
          debugPrint('⚠️ VPN disconnect error: $e');
        }
        state = state.copyWith(isActive: false, timerExpired: true);
      } else {
        // Log every 60 seconds
        if (state.remainingSeconds % 60 == 0) {
          final minutesLeft = state.remainingSeconds ~/ 60;
          debugPrint('⏲️ Free time remaining: $minutesLeft minutes');
        }
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      }
    });

    debugPrint('✅ Free connection timer started successfully');
  }

  /// Start timer with explicit seconds (used for ad-unlocked premium servers
  /// where duration comes from PremiumServerUnlockService, not server.freeConnectDuration)
  void startFromSeconds(VpnServer? server, int totalSeconds) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('⏲️ AD-UNLOCK TIMER START');
    debugPrint('   Server: ${server?.name}');
    debugPrint('   Duration: $totalSeconds seconds');
    debugPrint('═══════════════════════════════════════');

    if (totalSeconds <= 0) {
      stopTimer();
      return;
    }

    _timer?.cancel();
    state = FreeConnectionTimerState(
      isActive: true,
      isPremium: false,
      server: server,
      remainingSeconds: totalSeconds,
      totalSeconds: totalSeconds,
      isAdUnlockTimer: true,
    );

    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (state.remainingSeconds <= 0) {
        timer.cancel();
        debugPrint('⏰ AD-UNLOCK TIMER EXPIRED - server: ${state.server?.name}');
        debugPrint('   Disconnecting VPN (ad-unlock duration ended)');
        try {
          VpnService.instance.disconnect();
        } catch (e) {
          debugPrint('⚠️ VPN disconnect error: $e');
        }
        state = state.copyWith(isActive: false, timerExpired: true);
      } else {
        if (state.remainingSeconds % 60 == 0) {
          debugPrint(
            '⏲️ Ad-unlock remaining: ${state.remainingSeconds ~/ 60} min',
          );
        }
        state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
      }
    });

    debugPrint('✅ Ad-unlock timer started: $totalSeconds seconds');
  }

  void stopTimer() {
    _timer?.cancel();
    state = FreeConnectionTimerState();
  }

  void extendTime() {
    // This will be called when user purchases premium
    state = state.copyWith(isActive: false, isPremium: true);
    _timer?.cancel();
  }

  void addTime(int seconds) {
    debugPrint('═══════════════════════════════════════');
    debugPrint('⏱️ ADD TIME REQUEST');
    debugPrint('   Seconds to add: $seconds');
    debugPrint(
      '   Current state - Active: ${state.isActive}, Expired: ${state.timerExpired}',
    );
    debugPrint('   Current remaining: ${state.remainingSeconds}s');
    debugPrint('═══════════════════════════════════════');

    // ✅ CRITICAL FIX: Add time even if timer expired, then restart it
    if (state.timerExpired) {
      // Timer was expired, reset it with the new time
      debugPrint('🔄 Timer was expired, restarting with new time');
      _timer?.cancel();

      state = FreeConnectionTimerState(
        isActive: true,
        isPremium: false,
        server: state.server,
        remainingSeconds: seconds,
        totalSeconds: seconds,
        timerExpired: false,
      );

      // Restart the timer with the extended time
      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (state.remainingSeconds <= 0) {
          timer.cancel();
          debugPrint('⏰ FREE CONNECTION TIMER EXPIRED (after ad reward)!');
          debugPrint('   Server: ${state.server?.name}');
          try {
            VpnService.instance.disconnect();
          } catch (e) {
            debugPrint('⚠️ VPN disconnect error: $e');
          }
          state = state.copyWith(isActive: false, timerExpired: true);
        } else {
          if (state.remainingSeconds % 60 == 0) {
            final minutesLeft = state.remainingSeconds ~/ 60;
            debugPrint('⏲️ Free time remaining: $minutesLeft minutes');
          }
          state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
        }
      });

      debugPrint('✅ Timer restarted with $seconds seconds');
    } else if (state.isActive) {
      // Timer is still active, just add more time
      debugPrint('⏳ Timer still active, extending by $seconds seconds');
      state = state.copyWith(
        remainingSeconds: state.remainingSeconds + seconds,
        totalSeconds: state.totalSeconds + seconds,
      );
      debugPrint('✅ Time added. New remaining: ${state.remainingSeconds}s');
    } else {
      // Timer not active and not expired, restart it
      debugPrint('🔄 Timer inactive, restarting with new time');
      _timer?.cancel();

      state = FreeConnectionTimerState(
        isActive: true,
        isPremium: false,
        server: state.server,
        remainingSeconds: seconds,
        totalSeconds: seconds,
        timerExpired: false,
      );

      _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (state.remainingSeconds <= 0) {
          timer.cancel();
          debugPrint('⏰ FREE CONNECTION TIMER EXPIRED!');
          debugPrint('   Server: ${state.server?.name}');
          try {
            VpnService.instance.disconnect();
          } catch (e) {
            debugPrint('⚠️ VPN disconnect error: $e');
          }
          state = state.copyWith(isActive: false, timerExpired: true);
        } else {
          if (state.remainingSeconds % 60 == 0) {
            final minutesLeft = state.remainingSeconds ~/ 60;
            debugPrint('⏲️ Free time remaining: $minutesLeft minutes');
          }
          state = state.copyWith(remainingSeconds: state.remainingSeconds - 1);
        }
      });

      debugPrint('✅ Timer restarted with $seconds seconds');
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

class FreeConnectionTimerState {
  final bool isActive;
  final bool isPremium;
  final VpnServer? server;
  final int remainingSeconds;
  final int totalSeconds;
  final bool timerExpired;

  /// True when this timer was started for an ad-unlocked premium server.
  /// When it expires we disconnect silently (no extend-time popup).
  final bool isAdUnlockTimer;

  FreeConnectionTimerState({
    this.isActive = false,
    this.isPremium = false,
    this.server,
    this.remainingSeconds = 0,
    this.totalSeconds = 0,
    this.timerExpired = false,
    this.isAdUnlockTimer = false,
  });

  FreeConnectionTimerState copyWith({
    bool? isActive,
    bool? isPremium,
    VpnServer? server,
    int? remainingSeconds,
    int? totalSeconds,
    bool? timerExpired,
    bool? isAdUnlockTimer,
  }) {
    return FreeConnectionTimerState(
      isActive: isActive ?? this.isActive,
      isPremium: isPremium ?? this.isPremium,
      server: server ?? this.server,
      remainingSeconds: remainingSeconds ?? this.remainingSeconds,
      totalSeconds: totalSeconds ?? this.totalSeconds,
      timerExpired: timerExpired ?? this.timerExpired,
      isAdUnlockTimer: isAdUnlockTimer ?? this.isAdUnlockTimer,
    );
  }

  String get formattedTime {
    final minutes = remainingSeconds ~/ 60;
    final seconds = remainingSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  double get progress {
    if (totalSeconds <= 0) return 0.0;
    return (totalSeconds - remainingSeconds) / totalSeconds;
  }
}

class ConnectionStats {
  final int totalConnections;
  final Duration totalTime;
  final double dataUsageMB;

  ConnectionStats({
    this.totalConnections = 0,
    this.totalTime = Duration.zero,
    this.dataUsageMB = 0.0,
  });

  ConnectionStats copyWith({
    int? totalConnections,
    Duration? totalTime,
    double? dataUsageMB,
  }) {
    return ConnectionStats(
      totalConnections: totalConnections ?? this.totalConnections,
      totalTime: totalTime ?? this.totalTime,
      dataUsageMB: dataUsageMB ?? this.dataUsageMB,
    );
  }
}

// Reward Video State Provider - Watch the service and update when state changes
class RewardVideoNotifier extends StateNotifier<RewardVideoState> {
  final RewardVideoService _service;

  RewardVideoNotifier(this._service) : super(_service.state) {
    // Listen to service state changes
    _init();
  }

  Future<void> _init() async {
    await _service.initialize();
    state = _service.state;
    debugPrint('🎬 RewardVideoNotifier initialized');
  }

  /// Mark a video as watched
  Future<void> markVideoWatched(int videoIndex) async {
    await _service.markVideoWatched(videoIndex);
    state = _service.state;
    debugPrint('✅ Video $videoIndex marked as watched');
  }

  /// Check if video can be watched
  bool canWatchVideo(int videoIndex) {
    return _service.canWatchVideo(videoIndex);
  }

  /// Get remaining videos
  int getRemainingVideos() {
    return _service.getRemainingVideos();
  }

  /// Get today's earned minutes
  int getTodayMinutesEarned() {
    return _service.getTodayMinutesEarned();
  }

  /// Reset for testing only
  Future<void> resetForTesting() async {
    await _service.resetForTesting();
    state = _service.state;
  }
}

final rewardVideoProvider =
    StateNotifierProvider<RewardVideoNotifier, RewardVideoState>((ref) {
      // Initialize service synchronously inline for now
      final service = RewardVideoService();
      // Don't await - just create the notifier
      return RewardVideoNotifier(service);
    });

// Provider for premium server unlock refresh trigger
// This provider rebuilds whenever premium unlocks change
final premiumServerUnlocksProvider =
    StateNotifierProvider<
      PremiumUnlocksNotifier,
      Map<String, UnlockedPremiumServer>
    >((ref) {
      return PremiumUnlocksNotifier();
    });

class PremiumUnlocksNotifier
    extends StateNotifier<Map<String, UnlockedPremiumServer>> {
  PremiumUnlocksNotifier() : super({}) {
    _initialize();
    _startPeriodicRefresh();
  }

  Timer? _refreshTimer;

  Future<void> _initialize() async {
    await PremiumServerUnlockService().initialize();
    _refresh();
  }

  void _startPeriodicRefresh() {
    // Refresh every second only when there are active unlocks to count down.
    // When empty, check every 30 s (in case an unlock is added externally).
    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (state.isNotEmpty) {
        _refresh();
      }
    });
  }

  Future<void> _refresh() async {
    final unlocks = PremiumServerUnlockService().getAllUnlockedServers();
    state = unlocks;
  }

  /// Call this after unlocking a server to trigger immediate UI rebuild
  Future<void> notifyUnlock() async {
    await Future.delayed(const Duration(milliseconds: 100));
    await _refresh();
  }

  /// Check if a server is unlocked with time remaining
  int getRemainingMinutes(dynamic serverId) {
    return PremiumServerUnlockService().getRemainingMinutes(serverId);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }
}

// ─── Server Latency Provider ──────────────────────────────────────────────────
// Measures real TCP connect latency for each server.
// Tries multiple ports; a fast SocketException (connection refused) is also a
// valid RTT because the host replied (just refused the connection).
// Result map: server.id → latency in ms (null = all ports timed-out).

class ServerLatencyNotifier extends StateNotifier<Map<String, int?>> {
  ServerLatencyNotifier() : super({});

  bool _disposed = false;

  /// Measure latency for all [servers] in parallel (up to 10 at a time).
  Future<void> measureLatencies(List<VpnServer> servers) async {
    if (_disposed) return;
    final chunks = <List<VpnServer>>[];
    for (var i = 0; i < servers.length; i += 10) {
      chunks.add(
        servers.sublist(i, i + 10 > servers.length ? servers.length : i + 10),
      );
    }
    for (final chunk in chunks) {
      if (_disposed) return;
      await Future.wait(chunk.map(_measureOne));
    }
  }

  Future<void> _measureOne(VpnServer server) async {
    if (_disposed) return;
    final host = server.ip.isNotEmpty ? server.ip : server.name;
    // Try the configured TCP port first, then common ports that tend to reply fast.
    final tcpPort = int.tryParse(server.tcpPort) ?? server.port;
    final portsToTry = <int>{tcpPort, 80, 443}.toList();

    for (final port in portsToTry) {
      if (_disposed) return;
      final stopwatch = Stopwatch()..start();
      try {
        final socket = await Socket.connect(
          host,
          port,
          timeout: const Duration(seconds: 4),
        );
        stopwatch.stop();
        socket.destroy();
        if (!_disposed) {
          state = {...state, server.id: stopwatch.elapsedMilliseconds};
        }
        return; // Got a successful connection — done.
      } on SocketException {
        stopwatch.stop();
        // Connection refused means the server DID reply — that's a valid RTT.
        // Distinguish refused (fast) from timeout (slow).
        if (stopwatch.elapsedMilliseconds < 2000) {
          if (!_disposed) {
            state = {...state, server.id: stopwatch.elapsedMilliseconds};
          }
          return;
        }
        // Otherwise it timed out on this port — try next.
      } catch (_) {
        // Other errors — try next port.
      }
    }

    // All ports timed out or errored — mark as unreachable.
    if (!_disposed) {
      state = {...state, server.id: null};
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}

final serverLatencyProvider =
    StateNotifierProvider<ServerLatencyNotifier, Map<String, int?>>((ref) {
      return ServerLatencyNotifier();
    });
