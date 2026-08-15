import 'package:vpn_master/core/localization/app_localizations.dart';
import 'package:vpn_master/widgets/premium_server_unlock_popup.dart';
import 'package:vpn_master/widgets/unified_ads_popup_simple.dart';
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:animate_do/animate_do.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import '../../core/services/vpn_state.dart';
import '../../core/services/admob_service.dart';
import '../../core/services/level_play_service.dart';
import '../../core/services/vpn_notification_service.dart';
import '../../core/api/api_service.dart';
import '../../shared/providers/app_providers.dart';
import '../../shared/providers/theme_provider.dart';
import '../../widgets/subscription_banner.dart';
import '../../widgets/ip_address_widget.dart';
import '../../providers/ip_address_provider.dart';
import '../../services/ads_popup_config_service.dart';
import '../../services/premium_server_unlock_service.dart';
import '../../providers/subscription_provider.dart';
import '../../widgets/connection_map_widget.dart';
import '../../shared/widgets/flag_icon.dart';
import 'utils/country_emoji.dart';
import 'widgets/home_small_widgets.dart';
import 'widgets/location_cards.dart';
import 'widgets/connection_stats_section.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen>
    with TickerProviderStateMixin {
  late AnimationController _connectionAnimationController;
  late AnimationController _pulseAnimationController;
  late Animation<double> _scaleAnimation;
  late Animation<double> _pulseAnimation;

  BannerAd? _bannerAd;
  NativeAd? _connectedNativeAd;
  bool _isBannerAdLoaded = false;
  bool _isConnectedNativeAdLoaded = false;
  bool _hasShownConnectInterstitial = false;
  bool _isTogglingConnection = false; // guard against concurrent taps
  bool _userInitiatedDisconnect =
      false; // guard: prevent auto-connect after manual disconnect
  List<VpnServer> _autoConnectQueue =
      []; // remaining servers to try on auto-connect failure
  bool _isAutoConnecting =
      false; // true when auto-connecting (not user-initiated)
  Timer? _autoConnectTimeoutTimer; // cancels hung auto-connect after timeout

  @override
  void initState() {
    super.initState();
    _connectionAnimationController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    _pulseAnimationController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.1).animate(
      CurvedAnimation(
        parent: _connectionAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.2).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    // Start pulse animation for connected state
    _pulseAnimationController.repeat(reverse: true);

    // Initialize ads
    _initializeAds();

    // Initialize VPN notification service
    _initializeVpnNotifications();

    // Initialize premium server unlock service
    _initializePremiumUnlockService();

    // Handle auto-connect
    _handleAutoConnect();

    // Restore server selection
    _restoreServerSelection();
  }

  Future<void> _restoreServerSelection() async {
    try {
      final currentServerNotifier = ref.read(currentServerProvider.notifier);
      final persistedServerId = await currentServerNotifier
          .getPersistedServerId();

      if (persistedServerId != null) {
        // Wait a bit for servers to load, then restore selection
        await Future.delayed(const Duration(seconds: 1));
        final servers = await ref.read(serversProvider.future);
        VpnServer? persistedServer;
        try {
          persistedServer = servers.firstWhere(
            (s) => s.id == persistedServerId,
          );
        } catch (e) {
          persistedServer = servers.isNotEmpty ? servers.first : null;
        }

        if (persistedServer != null) {
          await currentServerNotifier.setServer(persistedServer);
        }
      }
    } catch (e) {}
  }

  void _initializeVpnNotifications() async {
    try {
      final vpnNotificationService = VpnNotificationService();
      await vpnNotificationService.initialize();
    } catch (e) {}
  }

  void _initializeAds() {
    // Only show ads to non-premium users
    final isPremium = ref.read(premiumStatusProvider);
    if (isPremium) {
      return;
    }

    _bannerAd?.dispose();
    _connectedNativeAd?.dispose();
    _bannerAd = null;
    _connectedNativeAd = null;
    _isBannerAdLoaded = false;
    _isConnectedNativeAdLoaded = false;

    // Create top banner ad
    _bannerAd = AdMobService.instance.createBannerAd(
      onAdLoaded: (ad) {
        if (mounted) {
          setState(() {
            _isBannerAdLoaded = true;
          });
        }
      },
      onAdFailedToLoad: (ad, error) {
        ad.dispose();

        // Retry loading ad after 30 seconds
        Future.delayed(const Duration(seconds: 30), () {
          if (mounted && !ref.read(premiumStatusProvider)) {
            _initializeAds();
          }
        });
      },
    );

    _bannerAd?.load();

    _connectedNativeAd = AdMobService.instance.createNativeAd(
      onAdLoaded: (ad) {
        if (mounted) {
          setState(() {
            _isConnectedNativeAdLoaded = true;
          });
        }
      },
      onAdFailedToLoad: (ad, error) {
        ad.dispose();
      },
    );

    _connectedNativeAd?.load();
  }

  /// Initialize premium server unlock service
  Future<void> _initializePremiumUnlockService() async {
    try {
      final unlockService = PremiumServerUnlockService();
      await unlockService.initialize();
      debugPrint('✅ Premium server unlock service initialized');
    } catch (e) {
      debugPrint('❌ Error initializing premium unlock service: $e');
    }
  }

  void _handleKillSwitch(VpnState? previousState) {
    final killSwitchEnabled = ref.read(killSwitchProvider);

    if (!killSwitchEnabled) return;
    if (_userInitiatedDisconnect) return;

    // Check if this was an unexpected disconnection
    final wasConnected = previousState == VpnState.connected;
    final wasConnecting = previousState == VpnState.connecting;

    if (wasConnected || wasConnecting) {
      // This was an unexpected disconnection, activate kill switch
      _showKillSwitchDialog();
    }
  }

  void _showKillSwitchDialog() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.security,
                    color: Colors.red,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    AppLocalizations.of(ctx).killSwitchActivated,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF1A1A2E),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'VPN connection was lost unexpectedly. Internet access is blocked to protect your privacy. Please reconnect to restore access.',
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      ref.read(killSwitchProvider.notifier).setValue(false);
                    },
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(AppLocalizations.of(ctx).disableKillSwitch),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.of(ctx).pop();
                      _handleAutoReconnect();
                    },
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(AppLocalizations.of(ctx).reconnect),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _handleAutoReconnect() async {
    final currentServer = ref.read(currentServerProvider);
    if (currentServer != null) {
      // ✅ CHECK ACCESS BEFORE AUTO-RECONNECTING
      final timerState = ref.read(freeConnectionTimerProvider);
      final unlockService = PremiumServerUnlockService();

      // Check if premium server has temporary unlock via ads
      final isPremiumUnlocked = unlockService.isPremiumServerUnlocked(
        currentServer.id,
      );

      // Prevent reconnect if premium server without subscription or unlock
      final isSubscribedForReconnect = ref.read(subscriptionProvider).isPremium;
      final isReconnectPremium =
          timerState.isPremium || isSubscribedForReconnect;
      if (currentServer.premium && !isReconnectPremium && !isPremiumUnlocked) {
        debugPrint(
          '🔒 Auto-reconnect blocked: Premium server without subscription or unlock',
        );
        return;
      }

      // Prevent reconnect if free server with expired timer
      if (!currentServer.premium &&
          timerState.timerExpired &&
          !isReconnectPremium) {
        debugPrint('⏰ Auto-reconnect blocked: Free server with expired timer');
        return;
      }

      // ✅ Access check passed - proceed with reconnect
      final vpnService = ref.read(vpnServiceProvider);
      await vpnService.connectToServer(currentServer);
    } else {
      // Connect to best server
      await _connectToBestServer();
    }
  }

  Future<void> _showRewardedAdForTime() async {
    try {
      debugPrint('📱 FREE TIME POPUP: Showing ads popup...');

      // Fetch ads popup configuration (cached; re-fetches every 2 min)
      final adsConfig = await AdsPopupConfigService().getAdsPopupConfig();

      debugPrint(
        '📱 FREE TIME CONFIG: Enabled=${adsConfig.enableBuySubscriptionPrompt} | Ads=${adsConfig.adRewardDuration}min',
      );

      // Check if free time extension popup is enabled
      if (!adsConfig.enableBuySubscriptionPrompt) {
        debugPrint('⚠️ Free time extension ads popup is disabled');
        if (mounted) {
          Navigator.pushNamed(context, '/premium');
        }
        return;
      }

      if (!mounted) return;

      // Show 3-ad popup for FREE SERVERS (extending free time)
      // Get reward video provider to track watched ads
      final rewardState = ref.read(rewardVideoProvider);
      final canWatchList = List.generate(3, (index) {
        return !rewardState.watchedVideoIndices.contains(index);
      });

      // Ensure we pass a VpnServer to the popup
      VpnServer? popupServer = ref.read(currentServerProvider);
      if (popupServer == null) {
        try {
          final servers = await ref.read(serversProvider.future);
          if (servers.isNotEmpty) {
            popupServer = servers.first;
          } else {
            if (mounted) Navigator.pushNamed(context, '/premium');
            return;
          }
        } catch (e) {
          if (mounted) Navigator.pushNamed(context, '/premium');
          return;
        }
      }

      debugPrint('🎬 Showing popup with server: ${popupServer?.name}');

      final result = await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => PremiumServerUnlockPopup(
          server: popupServer!,
          canWatchVideo: canWatchList,
          watchedCount: rewardState.watchedCount,
          maxVideos: 3,
          durationMinutes: adsConfig.adRewardDuration,
          onVideoWatched: (videoIndex) async {
            try {
              // User watched ad, extend time by configured duration
              debugPrint('═════════════════════════════════════════');
              debugPrint('✅ FREE TIME AD WATCHED: AD-${videoIndex + 1}');
              debugPrint('═════════════════════════════════════════');

              // Mark video as watched
              ref
                  .read(rewardVideoProvider.notifier)
                  .markVideoWatched(videoIndex);

              // Extend free time by ad_reward_duration (from config)
              final durationMinutes = adsConfig.adRewardDuration;

              debugPrint('⏱️ Adding $durationMinutes minutes to free timer');
              debugPrint(
                '   Before: ${ref.read(freeConnectionTimerProvider).formattedTime}',
              );

              // Update timer via Riverpod - this will auto-notify listeners
              ref
                  .read(freeConnectionTimerProvider.notifier)
                  .addTime(durationMinutes * 60);

              debugPrint(
                '   After: ${ref.read(freeConnectionTimerProvider).formattedTime}',
              );

              // Reconnect VPN if it was disconnected when the timer expired
              try {
                final vpnStateNow =
                    ref.read(vpnStateProvider).value ?? VpnState.disconnected;
                final serverToReconnect = ref.read(currentServerProvider);
                if (vpnStateNow == VpnState.disconnected &&
                    serverToReconnect != null) {
                  debugPrint(
                    '🔄 VPN was disconnected — reconnecting to ${serverToReconnect.name}',
                  );
                  final vpnService = ref.read(vpnServiceProvider);
                  await vpnService.connectToServer(serverToReconnect);
                }
              } catch (e) {
                debugPrint('⚠️ VPN reconnect after ad error: $e');
              }

              // Small delay to ensure state update
              await Future.delayed(const Duration(milliseconds: 100));

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Free time extended by $durationMinutes minutes!',
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            } catch (e) {
              debugPrint('❌ Error in onVideoWatched: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('❌ Error extending time: $e'),
                    backgroundColor: Colors.red,
                    duration: const Duration(seconds: 3),
                  ),
                );
              }
            }
          },
          onSubscriptionPressed: () async {
            debugPrint('🛒 Subscribe pressed from free time popup');
            if (mounted) {
              // Close popup and navigate to premium
              Navigator.of(context).pop();
              await Future.delayed(const Duration(milliseconds: 100));
              if (mounted) {
                Navigator.pushNamed(context, '/premium');
              }
            }
          },
        ),
      );

      debugPrint(
        '📊 FREE TIME POPUP CLOSED: Result=$result (true=watched, null/false=dismissed)',
      );

      // Handle popup dismissal WITHOUT watching ad
      if (result == null || result == false) {
        debugPrint('═════════════════════════════════════════');
        debugPrint('⏰ USER DISMISSED POPUP WITHOUT WATCHING AD');
        debugPrint('═════════════════════════════════════════');

        // CRITICAL: Only disconnect if timer is at 0 (time expired)
        // If timer has remaining time, user still has connection allowed
        final currentTimer = ref.read(freeConnectionTimerProvider);
        final remainingSeconds = currentTimer.remainingSeconds;

        debugPrint(
          '⏱️ Timer remaining: ${currentTimer.formattedTime} (${remainingSeconds}s)',
        );

        if (remainingSeconds <= 0) {
          // Timer was at 0 when popup was shown (Scenario 1) → DISCONNECT
          debugPrint('🔌 Timer is at 0 - DISCONNECTING VPN');
          debugPrint('═════════════════════════════════════════');

          try {
            // Get VPN service first
            final vpnService = ref.read(vpnServiceProvider);

            // Check current state
            final currentVpnState =
                ref.read(vpnStateProvider).value ?? VpnState.disconnected;
            debugPrint(
              '🔍 Current VPN state before disconnect: $currentVpnState',
            );

            // Clear current server selection FIRST (prevents auto-reconnect)
            debugPrint('🔄 Clearing server selection...');
            await ref.read(currentServerProvider.notifier).setServer(null);
            debugPrint('✅ Server selection cleared');

            // Force disconnect VPN immediately
            debugPrint('🔌 Sending disconnect command...');
            vpnService.disconnect();

            // Give VPN service time to process disconnect
            await Future.delayed(const Duration(milliseconds: 1500));
            debugPrint('✅ Disconnect processed');

            // Verify disconnect happened
            final newVpnState =
                ref.read(vpnStateProvider).value ?? VpnState.disconnected;
            debugPrint('🔍 VPN state after disconnect: $newVpnState');
            if (newVpnState != VpnState.disconnected) {
              debugPrint(
                '⚠️ Warning: VPN still not disconnected, trying again',
              );
              vpnService.disconnect();
              await Future.delayed(const Duration(milliseconds: 1000));
            }
          } catch (e) {
            debugPrint('❌ CRITICAL: Error disconnecting VPN: $e');
          }

          // Show message
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  '❌ VPN Disconnected - Free time expired. Watch an ad or subscribe to continue.',
                ),
                backgroundColor: Colors.red,
                duration: Duration(seconds: 5),
              ),
            );
          }
        } else {
          // Timer has time left (Scenario 2) → KEEP VPN CONNECTED
          debugPrint(
            '⏱️ Timer still has ${currentTimer.formattedTime} remaining',
          );
          debugPrint(
            '✅ User closed popup but has time left - VPN STAYS CONNECTED',
          );
          debugPrint('═════════════════════════════════════════');

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '⏱️ You still have ${currentTimer.formattedTime} of free time remaining. VPN stays connected!',
                ),
                backgroundColor: Colors.blue,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      } else if (result == true) {
        debugPrint(
          '✅ User watched ad and popup auto-dismissed - VPN stays connected',
        );
        debugPrint('   Free time has been extended, VPN will remain connected');
      }
    } catch (e) {
      debugPrint('❌ Error showing free time ads popup: $e');
    }
  }

  void _handleAutoConnect() async {
    try {
      final autoConnect = ref.read(autoConnectProvider);
      if (autoConnect && !_userInitiatedDisconnect) {
        // Wait a bit for providers to initialize and restore server selection
        await Future.delayed(const Duration(seconds: 2));

        // Re-check the flag after the delay in case user disconnected during wait
        if (_userInitiatedDisconnect) return;

        final vpnState = ref.read(vpnStateProvider).value;
        final currentServer = ref.read(currentServerProvider);

        // Only auto-connect if not already connected or connecting
        if (vpnState == VpnState.disconnected) {
          if (currentServer != null) {
            final timerState = ref.read(freeConnectionTimerProvider);
            final isSubscribed = ref.read(subscriptionProvider).isPremium;
            final isUserPremium = timerState.isPremium || isSubscribed;

            if (currentServer.premium && !isUserPremium) {
              await _connectToBestServer();
            } else {
              await ref.read(vpnServiceProvider).connectToServer(currentServer);
            }
          } else {
            await _connectToBestServer();
          }
        }
      }
    } catch (e) {}
  }

  Future<void> _connectToBestServer() async {
    try {
      // ✅ CHECK ACCESS BEFORE CONNECTING TO BEST SERVER
      final timerState = ref.read(freeConnectionTimerProvider);
      final isSubscribed = ref.read(subscriptionProvider).isPremium;
      final isUserPremium = timerState.isPremium || isSubscribed;

      // If free tier user has expired timer, don't auto-connect
      if (timerState.timerExpired && !isUserPremium) {
        debugPrint(
          '⏰ Best server connection blocked: Free tier with expired timer',
        );
        return;
      }

      final apiService = ref.read(apiServiceProvider);
      final servers = await apiService.getServers();

      if (servers.isNotEmpty) {
        // First check if there's a persisted server selection
        final currentServerNotifier = ref.read(currentServerProvider.notifier);
        final persistedServerId = await currentServerNotifier
            .getPersistedServerId();

        if (persistedServerId != null) {
          // Try to find the persisted server
          final persistedServer = servers.firstWhere(
            (s) => s.id == persistedServerId,
            orElse: () => servers.first,
          );

          // ✅ Check if persisted server is accessible and not full
          if (persistedServer.premium && !isUserPremium) {
            debugPrint(
              '🔒 Persisted premium server not accessible - no subscription',
            );
          } else if (persistedServer.isFull) {
            debugPrint(
              '🚫 Persisted server is at full capacity - falling through to next available',
            );
          } else {
            await currentServerNotifier.setServer(persistedServer);
            _isAutoConnecting = true;
            _autoConnectQueue = [];
            final success = await ref
                .read(vpnServiceProvider)
                .connectToServer(persistedServer);
            if (success) return;
            // Persisted server failed immediately — clear and fall through
            _isAutoConnecting = false;
            await currentServerNotifier.setServer(null);
          }
        }

        // Premium users can auto-connect to both free and premium servers.
        // Free users auto-connect only to free servers.
        final latencies = ref.read(serverLatencyProvider);
        final candidateServers =
            (isUserPremium
                    ? servers.where((s) => s.isActive && !s.isFull)
                    : servers.where(
                        (s) => !s.premium && s.isActive && !s.isFull,
                      ))
                .toList()
              ..sort((a, b) {
                final la = latencies[a.id];
                final lb = latencies[b.id];
                if (la != null && lb == null) return -1;
                if (la == null && lb != null) return 1;
                if (la != null && lb != null) return la.compareTo(lb);
                return a.order.compareTo(b.order);
              });

        // Remove the persisted server (already failed above) from the queue
        final queue = candidateServers
            .where((s) => s.id != persistedServerId)
            .toList();

        if (queue.isNotEmpty) {
          final bestServer = queue.first;
          // Store remaining servers for fallback on VPN error
          _autoConnectQueue = queue.skip(1).toList();
          _isAutoConnecting = true;
          _startAutoConnectTimeout();

          await ref.read(currentServerProvider.notifier).setServer(bestServer);
          final success = await ref
              .read(vpnServiceProvider)
              .connectToServer(bestServer);

          if (!success) {
            _autoConnectTimeoutTimer?.cancel();
            _isAutoConnecting = false;
            _autoConnectQueue = [];
            await ref.read(currentServerProvider.notifier).setServer(null);
          }
        }
      }
    } catch (e) {
      _autoConnectTimeoutTimer?.cancel();
      _isAutoConnecting = false;
      _autoConnectQueue = [];
      await ref.read(currentServerProvider.notifier).setServer(null);
    }
  }

  /// Called when auto-connect fails — tries the next server in the queue.
  Future<void> _tryNextAutoConnectServer() async {
    _autoConnectTimeoutTimer?.cancel();
    if (_autoConnectQueue.isEmpty) {
      _isAutoConnecting = false;
      return;
    }
    final next = _autoConnectQueue.first;
    _autoConnectQueue = _autoConnectQueue.skip(1).toList();
    debugPrint('🔄 Auto-connect fallback: trying ${next.name}');
    _startAutoConnectTimeout();
    await ref.read(currentServerProvider.notifier).setServer(next);
    final success = await ref.read(vpnServiceProvider).connectToServer(next);
    if (!success) {
      _autoConnectTimeoutTimer?.cancel();
      // connectToServer returned false synchronously — skip to next
      await _tryNextAutoConnectServer();
    }
  }

  /// Starts a 10-second watchdog that force-moves to the next auto-connect
  /// server if the VPN hangs in connecting/waitConnection state.
  void _startAutoConnectTimeout() {
    _autoConnectTimeoutTimer?.cancel();
    _autoConnectTimeoutTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_isAutoConnecting) return;
      final state = ref.read(vpnStateProvider).value;
      if (state == VpnState.connecting ||
          state == VpnState.waitConnection ||
          state == VpnState.authenticating ||
          state == VpnState.preparing) {
        debugPrint('⏱️ Auto-connect timeout — moving to next server');
        ref.read(vpnServiceProvider).disconnect();
        // _tryNextAutoConnectServer will be triggered by the error state listener
      }
    });
  }

  void _disconnectVpn() async {
    debugPrint('═══════════════════════════════════════');
    debugPrint('🔌 _disconnectVpn() called from home screen');
    debugPrint('═══════════════════════════════════════');

    _userInitiatedDisconnect = true;
    _isAutoConnecting = false;
    _autoConnectQueue = [];
    _autoConnectTimeoutTimer?.cancel();
    try {
      final vpnService = ref.read(vpnServiceProvider);

      // Await disconnect so the native tunnel and UI state are kept in sync.
      await vpnService.disconnect();

      // Clear server selection
      await ref.read(currentServerProvider.notifier).setServer(null);

      debugPrint('✅ Disconnect signal sent - server cleared');
    } catch (e) {
      debugPrint('❌ Error disconnecting VPN: $e');
    }
  }

  @override
  void dispose() {
    _autoConnectTimeoutTimer?.cancel();
    _connectionAnimationController.dispose();
    _pulseAnimationController.dispose();
    _bannerAd?.dispose();
    _connectedNativeAd?.dispose();

    // Note: Don't use ref.read() in dispose() as the widget is being disposed
    // The network speed service will be properly disposed by the provider system

    super.dispose();
  }

  void _toggleConnection() async {
    // Prevent concurrent calls (rapid double-taps causing reconnect loops)
    if (_isTogglingConnection) return;
    _isTogglingConnection = true;
    try {
      await _doToggleConnection();
    } finally {
      _isTogglingConnection = false;
    }
  }

  Future<void> _doToggleConnection() async {
    final vpnService = ref.read(vpnServiceProvider);
    final vpnState = ref.read(vpnStateProvider).value ?? VpnState.disconnected;

    // If connecting or waiting, disconnect (allow user to cancel)
    if (vpnState == VpnState.connected ||
        vpnState == VpnState.waitConnection ||
        vpnState == VpnState.connecting ||
        vpnState == VpnState.reconnecting ||
        vpnState == VpnState.preparing ||
        vpnState == VpnState.authenticating) {
      _userInitiatedDisconnect = true;
      await vpnService.disconnect();
      // Clear the current server when disconnecting
      await ref.read(currentServerProvider.notifier).setServer(null);
      _connectionAnimationController.reset();
      return;
    }

    if (vpnState != VpnState.disconnected) return;

    _userInitiatedDisconnect =
        false; // User is connecting - clear the disconnect guard

    final currentServer = ref.read(currentServerProvider);
    final timerState = ref.read(freeConnectionTimerProvider);
    // Check actual subscription status (timerState.isPremium is only set after first connect)
    final isSubscribed = ref.read(subscriptionProvider).isPremium;
    final isUserPremium = timerState.isPremium || isSubscribed;

    // ✅ CRITICAL CHECK: Prevent connection if timer expired and no subscription
    if (!isUserPremium && timerState.timerExpired) {
      debugPrint('═════════════════════════════════════════');
      debugPrint('🚫 CONNECTION BLOCKED');
      debugPrint('   Free time EXPIRED - cannot connect');
      debugPrint('   Must watch ad OR buy subscription');
      debugPrint('═════════════════════════════════════════');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            '❌ Free time expired. Watch an ad or subscribe to connect.',
          ),
          backgroundColor: Colors.orangeAccent,
          duration: Duration(seconds: 4),
        ),
      );
      return;
    }

    if (currentServer != null) {
      // ✅ CHECK ACCESS BEFORE CONNECTING
      final unlockService = PremiumServerUnlockService();
      final isPremiumUnlocked = unlockService.isPremiumServerUnlocked(
        currentServer.id,
      );

      // Check if this is a premium server and user is not subscribed or unlocked
      if (currentServer.premium && !isUserPremium && !isPremiumUnlocked) {
        debugPrint(
          '🔒 Premium server selected - user not subscribed or unlocked',
        );
        // Show unlock popup for premium server
        _showPremiumUnlockPopup(currentServer);
        return;
      }

      // Check if this is a free server with expired timer
      if (!currentServer.premium && timerState.timerExpired && !isUserPremium) {
        debugPrint(
          '⏰ Free server selected - timer expired, need ad or subscription',
        );
        // Show reward popup to watch ad or subscribe
        _showRewardedAdForTime();
        return;
      }

      // ✅ User can connect - proceed with connection
      _connectionAnimationController.forward();
      final success = await vpnService.connectToServer(currentServer);
      if (!success) {
        _connectionAnimationController.reverse();
        // Clear server selection on failure
        await ref.read(currentServerProvider.notifier).setServer(null);
      }
    } else {
      // No server selected - try quick connect to a free server

      // ✅ CHECK TIMER BEFORE AUTO-CONNECTING TO FREE SERVER
      if (!isUserPremium && timerState.timerExpired) {
        debugPrint('═════════════════════════════════════════');
        debugPrint('🚫 AUTO-CONNECTION BLOCKED - TIMER EXPIRED');
        debugPrint('═════════════════════════════════════════');
        return;
      }

      _connectionAnimationController.forward();
      final servers = await ref.read(serversProvider.future);

      // Premium users can connect to any active non-full server;
      // free users are limited to free (non-premium) non-full servers.
      final candidateServers = isUserPremium
          ? servers.where((s) => s.isActive && !s.isFull).toList()
          : servers
                .where((s) => !s.premium && s.isActive && !s.isFull)
                .toList();

      if (candidateServers.isNotEmpty) {
        // Sort by order to get the best server (lowest order number)
        candidateServers.sort((a, b) => a.order.compareTo(b.order));
        final bestServer = candidateServers.first;

        await ref.read(currentServerProvider.notifier).setServer(bestServer);
        final success = await vpnService.connectToServer(bestServer);
        if (!success) {
          _connectionAnimationController.reverse();
          await ref.read(currentServerProvider.notifier).setServer(null);
        }
      } else {
        _connectionAnimationController.reverse();
        // All servers are full or none available — alert user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'All servers are at full capacity. Please try again later or select a server manually.',
              ),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        _showServerSelection();
      }
    }
  }

  /// Show popup for premium server unlock (requires subscription or ad watch)
  Future<void> _showPremiumUnlockPopup(VpnServer server) async {
    try {
      // Fetch ads popup configuration (cached; re-fetches every 2 min)
      final adsConfig = await AdsPopupConfigService().getAdsPopupConfig();

      // Check if premium unlock ads popup is enabled
      if (!adsConfig.enablePremiumUnlock) {
        debugPrint('⚠️ Ads popup for premium server unlock is disabled');
        if (mounted) {
          // Show simple message and navigate to premium
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(AppLocalizations.of(context).subscribeForPremium),
              backgroundColor: Colors.purple,
              duration: const Duration(seconds: 3),
            ),
          );
          Future.delayed(const Duration(seconds: 1), () {
            if (mounted) {
              Navigator.pushNamed(context, '/premium');
            }
          });
        }
        return;
      }

      if (!mounted) return;

      // Show the new premium server unlock ads popup
      showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => UnifiedAdsPopupSimple(
          adCount: 3,
          title: AppLocalizations.of(context).unlockPremiumServer,
          subtitle: server.name,
          customText: adsConfig.premiumUnlockText,
          showSubscribeButton: true,
          onAction: (action) async {
            if (action == 'all_ads_watched') {
              // User watched all ads, unlock premium server temporarily
              debugPrint('═════════════════════════════════════════');
              debugPrint('✅ ALL ADS WATCHED - PREMIUM SERVER UNLOCKED');
              debugPrint(
                '   Duration: ${adsConfig.premiumUnlockDurationMinutes} minutes',
              );
              debugPrint('═════════════════════════════════════════');

              // Unlock the premium server
              final unlockService = PremiumServerUnlockService();
              await unlockService.unlockPremiumServer(
                server: server,
                durationMinutes: adsConfig.premiumUnlockDurationMinutes,
                unlockedBy: 'ad',
              );

              // Notify provider to trigger UI rebuild on servers screen
              await ref
                  .read(premiumServerUnlocksProvider.notifier)
                  .notifyUnlock();

              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ ${server.name} unlocked for ${adsConfig.premiumUnlockDurationMinutes} minutes!',
                    ),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 3),
                  ),
                );

                // Close popup and attempt connection
                Future.delayed(const Duration(milliseconds: 200), () {
                  if (mounted) {
                    Navigator.pop(context); // Close popup first
                    // Set the unlocked server as current
                    Future.delayed(const Duration(milliseconds: 150), () {
                      if (mounted) {
                        ref
                            .read(currentServerProvider.notifier)
                            .setServer(server);
                      }
                    });
                  }
                });
              }
            } else if (action == 'subscribe_clicked') {
              // User clicked Go Premium button
              debugPrint('═════════════════════════════════════════');
              debugPrint('🛒 User wants to subscribe - navigating to premium');
              debugPrint('═════════════════════════════════════════');

              // Close the dialog first
              if (mounted) {
                Navigator.of(context).pop(false);
              }

              // Give the dialog time to close before navigating
              await Future.delayed(const Duration(milliseconds: 150));

              // Then navigate to premium screen
              if (mounted) {
                debugPrint('   📱 Navigating to /premium screen...');
                await Navigator.of(context).pushNamed('/premium');
                debugPrint('   ✅ Navigation to premium completed');
              }
            }
          },
        ),
      );
    } catch (e) {
      debugPrint('❌ Error showing premium unlock popup: $e');
    }
  }

  /// Show popup to watch ad for premium server temporary access
  void _showServerSelection() {
    Navigator.pushNamed(context, '/servers');
  }

  void _showServerDetailsBottomSheet(VpnServer server) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final localizations = AppLocalizations.of(context);
    final latencies = ref.read(serverLatencyProvider);
    final latencyMs = latencies[server.id];
    final latencyText = latencyMs != null
        ? '${latencyMs}${localizations.ms}'
        : '--${localizations.ms}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          MediaQuery.of(ctx).viewInsets.bottom + MediaQuery.of(ctx).padding.bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF10B981).withValues(alpha: 0.15),
                  ),
                  child: server.countryCode.trim().length == 2
                      ? FlagIcon(countryCode: server.countryCode, size: 30)
                      : Text(
                          countryEmoji(server.countryCode),
                          style: const TextStyle(fontSize: 26),
                        ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        server.name,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: isDarkMode ? Colors.white : Colors.black,
                        ),
                      ),
                      Text(
                        server.country,
                        style: TextStyle(
                          fontSize: 13,
                          color: isDarkMode
                              ? Colors.grey[400]
                              : Colors.grey[600],
                        ),
                      ),
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: () => Navigator.of(ctx).pop(),
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.close,
                      size: 18,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // Details card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                ),
              ),
              child: Column(
                children: [
                  DetailRow(
                    localizations.serverIp,
                    '${server.ip}:${server.port}',
                    Icons.computer,
                  ),
                  const SizedBox(height: 10),
                  DetailRow(
                    localizations.protocol,
                    server.protocol.toUpperCase(),
                    Icons.security,
                  ),
                  const SizedBox(height: 10),
                  DetailRow(localizations.ping, latencyText, Icons.speed),
                  const SizedBox(height: 10),
                  DetailRow(
                    localizations.load,
                    '${(server.load.clamp(0.0, 1.0) * 100).toInt()}%',
                    Icons.analytics,
                  ),
                  const SizedBox(height: 10),
                  DetailRow(
                    localizations.connectedUsers,
                    '${server.connectedDevices}/${server.capacity}',
                    Icons.people,
                  ),
                  if (!server.premium) ...[
                    const SizedBox(height: 10),
                    DetailRow(
                      localizations.freeTimeLimit,
                      server.freeConnectDuration > 0
                          ? '${server.freeConnectDuration} minutes'
                          : localizations.unlimited,
                      Icons.access_time,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            // Status: Currently Connected
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFF10B981).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: const BoxDecoration(
                      color: Color(0xFF10B981),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    localizations.currentlyConnected,
                    style: const TextStyle(
                      fontSize: 14,
                      color: Color(0xFF10B981),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vpnStateAsync = ref.watch(vpnStateProvider);
    final currentServer = ref.watch(currentServerProvider);
    final isPremium = ref.watch(premiumStatusProvider);
    final themeMode = ref.watch(themeModeProvider);
    final isDarkMode =
        themeMode == ThemeMode.dark ||
        (themeMode == ThemeMode.system &&
            MediaQuery.of(context).platformBrightness == Brightness.dark);

    // Trigger TCP-connect latency measurement when servers load so the
    // home screen shows ping even if the servers screen was never opened.
    ref.listen<AsyncValue<List<VpnServer>>>(serversProvider, (_, next) {
      next.whenData((servers) {
        ref.read(serverLatencyProvider.notifier).measureLatencies(servers);
      });
    });

    // Listen to VPN state changes (prevent duplicate notifications)
    ref.listen<AsyncValue<VpnState>>(vpnStateProvider, (previous, next) {
      try {
        // Remove duplicate notification handling since VpnService already handles notifications
        final currentServer = ref.read(currentServerProvider);

        next.whenData((state) {
          switch (state) {
            case VpnState.connecting:
              // Let VpnService handle connecting notifications
              break;
            case VpnState.preparing:
              // Show preparing state
              break;
            case VpnState.authenticating:
              // Keep showing connecting notification during authentication
              break;
            case VpnState.connected:
              // When the app is relaunched while VPN is already running the
              // vpnStateProvider emits 'connected' but currentServerProvider
              // may still be null (not yet restored from prefs). Recover the
              // server from VpnService which saved it in persistence.
              var effectiveServer = currentServer;
              if (effectiveServer == null) {
                effectiveServer = ref.read(vpnServiceProvider).currentServer;
                if (effectiveServer != null) {
                  ref
                      .read(currentServerProvider.notifier)
                      .setServer(effectiveServer);
                }
              }

              if (effectiveServer != null) {
                final previousState = previous?.value;
                final shouldShowConnectInterstitial =
                    previousState != null &&
                    previousState != VpnState.connected &&
                    !ref.read(premiumStatusProvider) &&
                    !_hasShownConnectInterstitial;

                if (shouldShowConnectInterstitial) {
                  _hasShownConnectInterstitial = true;
                  LevelPlayService.instance.showInterstitial(
                    placementName: 'vpn_connect',
                  );
                }

                // Let VpnService handle connected notifications
                _connectionAnimationController.forward();

                // Start speed monitoring
                final speedService = ref.read(networkSpeedServiceProvider);
                speedService.startMonitoring();

                // Start / restore the free connection timer.
                // Capture values before the async gap to avoid widget
                // deactivation issues inside the async closure.
                final capturedServer = effectiveServer;
                final capturedRef = ref;
                () async {
                  final isPremium = capturedRef.read(premiumStatusProvider);

                  if (capturedServer.premium) {
                    // Premium server: ensure PremiumServerUnlockService has
                    // loaded its persisted unlocks before we ask for remaining
                    // time.  initialize() is guarded and safe to call again.
                    await PremiumServerUnlockService().initialize();
                    final unlock = PremiumServerUnlockService().getUnlockInfo(
                      capturedServer.id,
                    );
                    final isAdUnlocked = unlock?.isStillUnlocked ?? false;
                    if (isAdUnlocked) {
                      // Ad-unlocked premium server — remaining seconds are
                      // computed from the persisted unlockedUntil timestamp
                      // so they are always accurate after an app restart.
                      capturedRef
                          .read(freeConnectionTimerProvider.notifier)
                          .startFromSeconds(
                            capturedServer,
                            unlock!.remainingSeconds,
                          );
                    } else if (isPremium) {
                      // Subscribed user on a premium server — no countdown.
                      capturedRef
                          .read(freeConnectionTimerProvider.notifier)
                          .startTimer(capturedServer, true);
                    } else {
                      // Free user on a premium server with no valid ad-unlock
                      // (unlock expired while app was in background).
                      // Disconnect immediately — do NOT give a free timer.
                      capturedRef.read(vpnServiceProvider).disconnect();
                    }
                  } else if (isPremium) {
                    // Premium subscriber on a free server — no countdown.
                    capturedRef
                        .read(freeConnectionTimerProvider.notifier)
                        .startTimer(capturedServer, true);
                  } else if (capturedServer.freeConnectDuration > 0) {
                    // Free user with a time-limited server.
                    // _connectionStartTime is restored from persistence so we
                    // can compute how much time has already elapsed and give
                    // the user only their *remaining* allocation rather than
                    // resetting to the full duration on every app restart.
                    final vpnSvc = capturedRef.read(vpnServiceProvider);
                    final connStart = vpnSvc.connectionStartTime;
                    if (connStart != null) {
                      final elapsed = DateTime.now()
                          .difference(connStart)
                          .inSeconds;
                      final totalSeconds =
                          capturedServer.freeConnectDuration * 60;
                      final remaining = totalSeconds - elapsed;
                      if (remaining <= 0) {
                        // Time already expired while the app was in the
                        // background — disconnect immediately.
                        vpnSvc.disconnect();
                      } else {
                        capturedRef
                            .read(freeConnectionTimerProvider.notifier)
                            .startFromSeconds(capturedServer, remaining);
                      }
                    } else {
                      // No saved start time — treat as a fresh connection.
                      capturedRef
                          .read(freeConnectionTimerProvider.notifier)
                          .startTimer(capturedServer, false);
                    }
                  } else {
                    // Free server with unlimited duration.
                    capturedRef
                        .read(freeConnectionTimerProvider.notifier)
                        .startTimer(capturedServer, false);
                  }
                }();

                // Refresh IP address when connected (delayed to let VPN interface stabilize)
                Future.delayed(const Duration(milliseconds: 2500), () {
                  if (ref.read(vpnStateProvider).value == VpnState.connected) {
                    ref.invalidate(ipAddressProvider);
                  }
                });
              }
              break;
            case VpnState.disconnecting:
              // Show brief disconnecting state, then hide
              Future.delayed(const Duration(milliseconds: 500), () {
                // Let VpnService handle notification cleanup
              });
              break;
            case VpnState.disconnected:
              // Let VpnService handle disconnected notifications
              _connectionAnimationController.reverse();

              // Only show the disconnect interstitial on a real
              // connected -> disconnected transition (not on app launch,
              // a failed connection attempt, or a duplicate notification).
              if (previous?.value == VpnState.connected &&
                  !ref.read(premiumStatusProvider)) {
                LevelPlayService.instance.showInterstitial(
                  placementName: 'vpn_disconnect',
                );
              }

              _hasShownConnectInterstitial = false;

              // Stop speed monitoring
              final speedService = ref.read(networkSpeedServiceProvider);
              speedService.stopMonitoring();

              // Only reset the free timer if it was NOT an expiry-triggered disconnect.
              // Preserving timerExpired=true prevents free users from reconnecting
              // without watching an ad.
              final timerStateOnDisconnect = ref.read(
                freeConnectionTimerProvider,
              );
              if (!timerStateOnDisconnect.timerExpired) {
                ref.read(freeConnectionTimerProvider.notifier).stopTimer();
              }

              // Refresh IP address when disconnected (delayed to let normal interface restore)
              Future.delayed(const Duration(milliseconds: 1500), () {
                if (!mounted) return;
                if (ref.read(vpnStateProvider).value == VpnState.disconnected) {
                  ref.invalidate(ipAddressProvider);
                }
              });

              // Handle kill switch
              _handleKillSwitch(previous?.value);
              break;
            case VpnState.denied:
              // Let VpnService handle notification cleanup
              _connectionAnimationController.reverse();
              _hasShownConnectInterstitial = false;

              // Stop free connection timer
              ref.read(freeConnectionTimerProvider.notifier).stopTimer();
              break;
            case VpnState.error:
              // Let VpnService handle notification cleanup
              _connectionAnimationController.reverse();
              _hasShownConnectInterstitial = false;

              // Stop free connection timer
              ref.read(freeConnectionTimerProvider.notifier).stopTimer();

              // Clear persisted server on error so next connect picks a fresh server
              ref.read(currentServerProvider.notifier).setServer(null);

              // If this was an auto-connect failure, try the next free server
              if (_isAutoConnecting && _autoConnectQueue.isNotEmpty) {
                _tryNextAutoConnectServer();
              } else {
                _isAutoConnecting = false;
                _autoConnectQueue = [];
              }

              // Handle kill switch
              _handleKillSwitch(previous?.value);
              break;
            case VpnState.waitConnection:
              // Keep showing connecting notification
              break;
            case VpnState.reconnecting:
              if (currentServer != null) {
                // Let VpnService handle reconnecting notifications
              }
              break;
          }
        });
      } catch (e) {}
    });

    // Listen to premium status changes to reinitialize ads
    ref.listen<bool>(premiumStatusProvider, (previous, next) {
      if (previous != null && previous != next) {
        if (next) {
          // User became premium - dispose ads
          _bannerAd?.dispose();
          _connectedNativeAd?.dispose();
          _bannerAd = null;
          _connectedNativeAd = null;
          setState(() {
            _isBannerAdLoaded = false;
            _isConnectedNativeAdLoaded = false;
          });
        } else {
          // User is no longer premium - reinitialize ads
          _initializeAds();
        }
      }
    });

    // Listen to timer expiration
    ref.listen<FreeConnectionTimerState>(freeConnectionTimerProvider, (
      previous,
      next,
    ) {
      debugPrint(
        '🔔 Timer state changed: expired=${next.timerExpired}, premium=${next.isPremium}',
      );

      if (next.timerExpired && !next.isPremium) {
        debugPrint('═══════════════════════════════════════');
        debugPrint('⏰ TIMER EXPIRED - VPN already disconnected by notifier');
        debugPrint('   Server: ${next.server?.name}');
        debugPrint('   Is ad-unlock timer: ${next.isAdUnlockTimer}');
        debugPrint('═══════════════════════════════════════');

        if (next.isAdUnlockTimer) {
          // Ad-unlock expired: VPN already disconnected by the notifier.
          // Just clear the server selection — no popup needed.
          ref.read(currentServerProvider.notifier).setServer(null);
        }
        // Free-server timer expired: VPN already disconnected by the notifier.
        // No popup — user will see the expired state in the UI.
      }
    });

    return Container(
      color: isDarkMode ? const Color(0xFF0F172A) : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            // Subscription notification banner
            const SubscriptionBanner(),

            // Top banner ad for non-premium users
            if (!isPremium && _isBannerAdLoaded && _bannerAd != null)
              FadeInDown(
                child: Container(
                  margin: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  height: 50,
                  child: AdWidget(ad: _bannerAd!),
                ),
              ),

            Expanded(
              child: vpnStateAsync.when(
                loading: () => _buildConnectionSection(
                  VpnState.disconnected,
                  currentServer,
                  isDarkMode,
                  isPremium,
                ),
                error: (error, stack) => Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(
                        'Error: $error',
                        style: const TextStyle(color: Colors.red),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: () {
                          ref.invalidate(vpnStateProvider);
                        },
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                ),
                data: (vpnState) => _buildConnectionSection(
                  vpnState,
                  currentServer,
                  isDarkMode,
                  isPremium,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionSection(
    VpnState vpnState,
    VpnServer? currentServer,
    bool isDarkMode,
    bool isPremium,
  ) {
    final themeColor = ref.watch(themeColorProvider);
    final isConnected = vpnState == VpnState.connected;
    final isConnecting = vpnState == VpnState.connecting ||
        vpnState == VpnState.waitConnection ||
        vpnState == VpnState.authenticating ||
        vpnState == VpnState.preparing;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // Tech Map Section
            FadeInDown(
              duration: const Duration(milliseconds: 800),
              child: const ConnectionMapWidget(),
            ),

            const SizedBox(height: 12),

            // Connection Button Section
            FadeInDown(
              delay: const Duration(milliseconds: 100),
              child: GestureDetector(
                onTap: _toggleConnection,
                child: AnimatedBuilder(
                  animation: isConnected ? _pulseAnimation : _scaleAnimation,
                  builder: (context, child) {
                    final pulse = isConnected
                        ? _pulseAnimation.value
                        : _scaleAnimation.value;
                    final ringA = isConnected
                        ? ((_pulseAnimation.value - 1.0) * 6).clamp(0.06, 0.20)
                        : 0.07;
                    final connColor = _getConnectionColor(
                      vpnState,
                      themeColor: themeColor,
                    );
                    return SizedBox(
                      width: 214,
                      height: 214,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 210,
                            height: 210,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: connColor.withOpacity(ringA),
                                width: 1.5,
                              ),
                            ),
                          ),
                          Container(
                            width: 182,
                            height: 182,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: connColor.withOpacity(
                                  (ringA * 1.7).clamp(0.0, 1.0),
                                ),
                                width: 1.2,
                              ),
                            ),
                          ),
                          Transform.scale(
                            scale: pulse,
                            child: Container(
                              width: 150,
                              height: 150,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _getConnectionGradient(
                                  vpnState,
                                  themeColor: themeColor,
                                ),
                                border: vpnState == VpnState.disconnected
                                    ? Border.all(color: themeColor, width: 3.0)
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color: connColor.withOpacity(
                                      vpnState == VpnState.disconnected
                                          ? 0.2
                                          : 0.45,
                                    ),
                                    blurRadius: vpnState == VpnState.disconnected
                                        ? 20
                                        : 36,
                                    spreadRadius: vpnState == VpnState.disconnected
                                        ? 4
                                        : 12,
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Container(
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black12,
                                    ),
                                  ),
                                  Center(
                                    child: _buildConnectionIcon(vpnState, themeColor: themeColor),
                                  ),
                                  if (isConnecting)
                                    Center(
                                      child: SizedBox(
                                        width: 170,
                                        height: 170,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Status Text
            FadeInUp(
              delay: const Duration(milliseconds: 200),
              child: Text(
                _getStatusText(vpnState),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: _getConnectionColor(vpnState, themeColor: themeColor),
                ),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 6),
            FadeInUp(
              delay: const Duration(milliseconds: 250),
              child: Text(
                isConnected
                    ? AppLocalizations.of(context).connectionSecure
                    : isConnecting
                        ? 'Setting secure connection...'
                        : AppLocalizations.of(context).connectionNotSecure,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode ? const Color(0xFF94A3B8) : const Color(0xFF6B7280),
                ),
                textAlign: TextAlign.center,
              ),
            ),

            const SizedBox(height: 18),

            // Server Info / Selection Card
            if (isConnected) ...[
              if (currentServer != null)
                FadeInUp(
                  delay: const Duration(milliseconds: 300),
                  child: ConnectedServerCard(
                    currentServer: currentServer,
                    onTap: () => _showServerDetailsBottomSheet(currentServer),
                  ),
                ),
            ] else if (!isConnecting) ...[
              FadeInUp(
                delay: const Duration(milliseconds: 300),
                child: SelectionLocationCard(
                  currentServer: currentServer,
                  isDarkMode: isDarkMode,
                  themeColor: themeColor,
                  onChangePressed: _showServerSelection,
                ),
              ),
            ],

            // Free Connection Timer
            if (isConnected && !isPremium) ...[
              const SizedBox(height: 14),
              FadeInUp(
                delay: const Duration(milliseconds: 400),
                child: _buildFreeConnectionTimer(),
              ),
            ],

            // Connection Stats
            if (isConnected) ...[
              const SizedBox(height: 14),
              FadeInUp(
                delay: const Duration(milliseconds: 500),
                child: const ConnectionStatsSection(),
              ),
            ],

            // Ads
            if (!isPremium &&
                _isConnectedNativeAdLoaded &&
                _connectedNativeAd != null) ...[
              const SizedBox(height: 16),
              FadeInUp(
                delay: const Duration(milliseconds: 550),
                child: Container(
                  height: 300,
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.white.withOpacity(0.08)
                          : Colors.black.withOpacity(0.05),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: AdWidget(ad: _connectedNativeAd!),
                  ),
                ),
              ),
            ],

            // IP Address Banner
            const SizedBox(height: 14),
            const IpAddressWidget(),
          ],
        ),
      ),
    );
  }

  Widget _buildConnectionIcon(VpnState vpnState, {Color? themeColor}) {
    switch (vpnState) {
      case VpnState.connected:
        return const Icon(
          Icons.power_settings_new,
          size: 44,
          color: Colors.white60,
        );
      case VpnState.connecting:
      case VpnState.authenticating:
        return const Icon(
          Icons.power_settings_new,
          size: 44,
          color: Colors.white60,
        );
      case VpnState.error:
        return const Icon(Icons.error_outline, size: 44, color: Colors.white60);
      default:
        return Icon(
          Icons.power_settings_new,
          size: 44,
          color: themeColor ?? const Color(0xFF2563EB),
        );
    }
  }

  LinearGradient _getConnectionGradient(
    VpnState vpnState, {
    Color? themeColor,
  }) {
    switch (vpnState) {
      case VpnState.connected:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF22C55E), Color(0xFF16A34A)],
        );
      case VpnState.connecting:
      case VpnState.authenticating:
        return const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFD97706)],
        );
      case VpnState.error:
        return const LinearGradient(
          colors: [Color(0xFFEF4444), Color(0xFFDC2626)],
        );
      default:
        return LinearGradient(
          colors: [
            (themeColor ?? const Color(0xFF2563EB)).withValues(alpha: 0.12),
            const Color(0xFFF8FAFF),
          ],
        );
    }
  }

  Color _getConnectionColor(VpnState vpnState, {Color? themeColor}) {
    switch (vpnState) {
      case VpnState.connected:
        return const Color(0xFF22C55E);
      case VpnState.connecting:
      case VpnState.authenticating:
        return const Color(0xFFF59E0B);
      case VpnState.error:
        return const Color(0xFFEF4444);
      default:
        return themeColor ?? const Color(0xFF2563EB);
    }
  }

  String _getStatusText(VpnState vpnState) {
    final l10n = AppLocalizations.of(context);
    switch (vpnState) {
      case VpnState.connected:
        return l10n.protectedStatus;
      case VpnState.connecting:
        return l10n.connectingStatus;
      case VpnState.authenticating:
        return l10n.authenticating;
      case VpnState.disconnecting:
        return l10n.disconnectingStatus;
      case VpnState.error:
        // During auto-connect retries, don't show "CONNECTION ERROR" — it
        // confuses users when we're already trying the next server silently.
        if (_isAutoConnecting && _autoConnectQueue.isNotEmpty) {
          return l10n.connectingStatus;
        }
        return l10n.connectionError;
      case VpnState.denied:
        return l10n.permissionDeniedStatus;
      default:
        return l10n.notProtected;
    }
  }

  Widget _buildFreeConnectionTimer() {
    final timerState = ref.watch(freeConnectionTimerProvider);

    debugPrint(
      '🕐 Timer Widget Build - Active: ${timerState.isActive}, Remaining: ${timerState.formattedTime}, Premium: ${timerState.isPremium}',
    );

    if (!timerState.isActive || timerState.isPremium) {
      debugPrint('⚠️ Hiding timer widget (inactive or premium)');
      return const SizedBox.shrink();
    }

    final themeColor = ref.watch(themeColorProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.orange.withValues(alpha: 0.08),
            Colors.red.withValues(alpha: 0.08),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.orange.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.15),
            blurRadius: 6,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Column(
        children: [
          // Header row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orange.withValues(alpha: 0.2),
                ),
                child: Icon(Icons.access_time, color: Colors.orange, size: 16),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AppLocalizations.of(context).freeConnectionTime,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: isDarkMode ? Colors.white : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Remaining: ${timerState.formattedTime}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: timerState.remainingSeconds > 300
                      ? Colors.green
                      : Colors.orange,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  timerState.formattedTime,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: timerState.progress,
              backgroundColor: Colors.grey.withValues(alpha: 0.3),
              valueColor: AlwaysStoppedAnimation<Color>(
                timerState.remainingSeconds > 300
                    ? Colors.green
                    : timerState.remainingSeconds > 60
                    ? Colors.orange
                    : Colors.red,
              ),
              minHeight: 6,
            ),
          ),

          const SizedBox(height: 12),

          // Action buttons
          Row(
            children: [
              // Watch Ad (+N min) — duration comes from admin config
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.green.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: TextButton.icon(
                    onPressed: _showRewardedAdForTime,
                    icon: const Icon(
                      Icons.play_circle_outline,
                      size: 18,
                      color: Colors.green,
                    ),
                    label: Text(
                      ref
                          .watch(adsPopupConfigProvider)
                          .maybeWhen(
                            data: (cfg) =>
                                'Watch Ad\n (+${cfg.adRewardDuration} min)',
                            orElse: () =>
                                AppLocalizations.of(context).watchAd5Min,
                          ),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // Go Premium
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: themeColor.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: TextButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/premium');
                    },
                    icon: Icon(Icons.star, size: 18, color: themeColor),
                    label: Text(
                      AppLocalizations.of(context).goPremium,
                      style: TextStyle(
                        fontSize: 12,
                        color: themeColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

}
