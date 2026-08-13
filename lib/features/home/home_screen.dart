import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:animate_do/animate_do.dart';

import '../../core/localization/app_localizations.dart';
import '../../core/services/vpn_state.dart';
import '../../core/services/admob_service.dart';
import '../../core/services/vpn_notification_service.dart';
import '../../core/api/api_service.dart';

import '../../shared/providers/app_providers.dart';
import '../../shared/providers/theme_provider.dart';

import '../../widgets/premium_server_unlock_popup.dart';
import '../../widgets/subscription_banner.dart';

import '../../providers/ip_address_provider.dart';
import '../../providers/subscription_provider.dart';

import '../../services/ads_popup_config_service.dart';
import '../../services/premium_server_unlock_service.dart';
import '../../widgets/unified_ads_popup_simple.dart';

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
  bool _isTogglingConnection = false;

  bool _userInitiatedDisconnect = false;

  List<VpnServer> _autoConnectQueue = [];

  bool _isAutoConnecting = false;

  Timer? _autoConnectTimeoutTimer;

  Timer? _elapsedTimer;

  int _elapsedSeconds = 0;

  bool _wasConnected = false;

  // ============================================================
  // ELAPSED CONNECTION TIMER
  // ============================================================

  void _startElapsedTimer() {
    _elapsedTimer?.cancel();

    _elapsedSeconds = 0;

    _elapsedTimer = Timer.periodic(
      const Duration(seconds: 1),
          (_) {
        if (!mounted) return;

        setState(() {
          _elapsedSeconds++;
        });
      },
    );
  }

  void _stopElapsedTimer() {
    _elapsedTimer?.cancel();
    _elapsedTimer = null;
    _elapsedSeconds = 0;
  }

  String get _formattedElapsedTime {
    final hours = _elapsedSeconds ~/ 3600;

    final minutes =
        (_elapsedSeconds % 3600) ~/ 60;

    final seconds =
        _elapsedSeconds % 60;

    return '${hours.toString().padLeft(2, '0')}:'
        '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  // ============================================================
  // INIT
  // ============================================================

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

    _scaleAnimation = Tween<double>(
      begin: 1.0,
      end: 1.1,
    ).animate(
      CurvedAnimation(
        parent: _connectionAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseAnimation = Tween<double>(
      begin: 1.0,
      end: 1.2,
    ).animate(
      CurvedAnimation(
        parent: _pulseAnimationController,
        curve: Curves.easeInOut,
      ),
    );

    _pulseAnimationController.repeat(reverse: true);

    _initializeAds();
    _initializeVpnNotifications();
    _initializePremiumUnlockService();

    _restoreServerSelection();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      _handleAutoConnect();
    });
  }

  // ============================================================
  // RESTORE SERVER
  // ============================================================

  Future<void> _restoreServerSelection() async {
    try {
      final notifier =
      ref.read(currentServerProvider.notifier);

      final persistedServerId =
      await notifier.getPersistedServerId();

      if (persistedServerId == null) return;

      await Future.delayed(
        const Duration(seconds: 1),
      );

      if (!mounted) return;

      final servers =
      await ref.read(serversProvider.future);

      if (servers.isEmpty) return;

      VpnServer? persistedServer;

      try {
        persistedServer = servers.firstWhere(
              (server) => server.id == persistedServerId,
        );
      } catch (_) {
        persistedServer = servers.first;
      }

      if (persistedServer != null && mounted) {
        await notifier.setServer(persistedServer);
      }
    } catch (e) {
      debugPrint(
        '⚠️ Restore server error: $e',
      );
    }
  }

  // ============================================================
  // VPN NOTIFICATION
  // ============================================================

  Future<void> _initializeVpnNotifications() async {
    try {
      final service =
      VpnNotificationService();

      await service.initialize();
    } catch (e) {
      debugPrint(
        '⚠️ VPN notification init error: $e',
      );
    }
  }

  // ============================================================
  // ADS
  // ============================================================

  void _initializeAds() {
    if (!mounted) return;

    final isPremium =
    ref.read(premiumStatusProvider);

    if (isPremium) {
      return;
    }

    _bannerAd?.dispose();
    _connectedNativeAd?.dispose();

    _bannerAd = null;
    _connectedNativeAd = null;

    _isBannerAdLoaded = false;
    _isConnectedNativeAdLoaded = false;

    // ----------------------------------------------------------
    // Banner
    // ----------------------------------------------------------

    _bannerAd =
        AdMobService.instance.createBannerAd(
          onAdLoaded: (ad) {
            if (!mounted) return;

            setState(() {
              _isBannerAdLoaded = true;
            });
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint(
              '❌ Banner ad failed: $error',
            );

            ad.dispose();

            if (!mounted) return;

            Future.delayed(
              const Duration(seconds: 30),
                  () {
                if (!mounted) return;

                if (!ref.read(premiumStatusProvider)) {
                  _initializeAds();
                }
              },
            );
          },
        );

    _bannerAd?.load();

    // ----------------------------------------------------------
    // Native
    // ----------------------------------------------------------

    _connectedNativeAd =
        AdMobService.instance.createNativeAd(
          onAdLoaded: (ad) {
            if (!mounted) return;

            setState(() {
              _isConnectedNativeAdLoaded = true;
            });

            debugPrint(
              '[HOME ADS] ✅ Native Ad loaded',
            );
          },
          onAdFailedToLoad: (ad, error) {
            debugPrint(
              '[HOME ADS] ❌ Native Ad failed: $error',
            );

            ad.dispose();

            if (!mounted) return;

            setState(() {
              _isConnectedNativeAdLoaded = false;
              _connectedNativeAd = null;
            });
          },
        );

    _connectedNativeAd?.load();

    // Prepare interstitial
    AdMobService.instance
        .ensureInterstitialAdReady();
  }

  // ============================================================
  // PREMIUM UNLOCK SERVICE
  // ============================================================

  Future<void> _initializePremiumUnlockService() async {
    try {
      final service =
      PremiumServerUnlockService();

      await service.initialize();

      debugPrint(
        '✅ Premium server unlock service initialized',
      );
    } catch (e) {
      debugPrint(
        '❌ Premium unlock initialization error: $e',
      );
    }
  }

  // ============================================================
  // KILL SWITCH
  // ============================================================

  void _handleKillSwitch(
      VpnState? previousState,
      ) {
    final killSwitchEnabled =
    ref.read(killSwitchProvider);

    if (!killSwitchEnabled) return;

    final wasConnected =
        previousState == VpnState.connected;

    final wasConnecting =
        previousState == VpnState.connecting;

    if (wasConnected || wasConnecting) {
      _showKillSwitchDialog();
    }
  }

  void _showKillSwitchDialog() {
    if (!mounted) return;

    final isDarkMode =
        Theme.of(context).brightness ==
            Brightness.dark;

    showModalBottomSheet(
      context: context,
      isDismissible: false,
      enableDrag: false,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF1E293B)
                : Colors.white,
            borderRadius:
            const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx).viewInsets.bottom +
                28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin:
                const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius:
                  BorderRadius.circular(2),
                ),
              ),

              Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(
                        alpha: 0.12,
                      ),
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
                      AppLocalizations.of(ctx)
                          .killSwitchActivated,
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                        FontWeight.bold,
                        color: isDarkMode
                            ? Colors.white
                            : const Color(
                          0xFF1A1A2E,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 12),

              Text(
                'VPN connection was lost unexpectedly. '
                    'Internet access is blocked to protect your privacy. '
                    'Please reconnect to restore access.',
                style: TextStyle(
                  fontSize: 14,
                  color: isDarkMode
                      ? Colors.grey[400]
                      : Colors.grey[600],
                ),
              ),

              const SizedBox(height: 24),

              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();

                        ref
                            .read(
                          killSwitchProvider
                              .notifier,
                        )
                            .setValue(false);
                      },
                      child: Text(
                        AppLocalizations.of(ctx)
                            .disableKillSwitch,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.of(ctx).pop();

                        _handleAutoReconnect();
                      },
                      child: Text(
                        AppLocalizations.of(ctx)
                            .reconnect,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // AUTO RECONNECT
  // ============================================================

  Future<void> _handleAutoReconnect() async {
    try {
      final currentServer =
      ref.read(currentServerProvider);

      final timerState =
      ref.read(freeConnectionTimerProvider);

      final unlockService =
      PremiumServerUnlockService();

      final isSubscribed =
          ref.read(subscriptionProvider).isPremium;

      final isPremiumUser =
          timerState.isPremium ||
              isSubscribed;

      if (currentServer != null) {
        final isUnlocked =
        unlockService.isPremiumServerUnlocked(
          currentServer.id,
        );

        if (currentServer.premium &&
            !isPremiumUser &&
            !isUnlocked) {
          debugPrint(
            '🔒 Auto reconnect blocked: premium server locked',
          );
          return;
        }

        if (!currentServer.premium &&
            timerState.timerExpired &&
            !isPremiumUser) {
          debugPrint(
            '⏰ Auto reconnect blocked: timer expired',
          );
          return;
        }

        await ref
            .read(vpnServiceProvider)
            .connectToServer(
          currentServer,
        );
      } else {
        await _connectToBestServer();
      }
    } catch (e) {
      debugPrint(
        '❌ Auto reconnect error: $e',
      );
    }
  }

  // ============================================================
  // REWARDED FREE TIME POPUP
  // ============================================================

  Future<void> _showRewardedAdForTime() async {
    try {
      debugPrint(
        '📱 FREE TIME POPUP: Showing ads popup...',
      );

      final adsConfig =
      await AdsPopupConfigService()
          .getAdsPopupConfig();

      if (!adsConfig
          .enableBuySubscriptionPrompt) {
        if (mounted) {
          Navigator.pushNamed(
            context,
            '/premium',
          );
        }
        return;
      }

      if (!mounted) return;

      final rewardState =
      ref.read(rewardVideoProvider);

      final canWatchList =
      List.generate(
        3,
            (index) =>
        !rewardState
            .watchedVideoIndices
            .contains(index),
      );

      VpnServer? popupServer =
      ref.read(currentServerProvider);

      if (popupServer == null) {
        try {
          final servers =
          await ref.read(
            serversProvider.future,
          );

          if (servers.isNotEmpty) {
            popupServer = servers.first;
          } else {
            if (mounted) {
              Navigator.pushNamed(
                context,
                '/premium',
              );
            }
            return;
          }
        } catch (_) {
          if (mounted) {
            Navigator.pushNamed(
              context,
              '/premium',
            );
          }
          return;
        }
      }

      final result =
      await showModalBottomSheet<bool>(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return PremiumServerUnlockPopup(
            server: popupServer!,
            canWatchVideo: canWatchList,
            watchedCount:
            rewardState.watchedCount,
            maxVideos: 3,
            durationMinutes:
            adsConfig.adRewardDuration,
            onVideoWatched:
                (videoIndex) async {
              try {
                ref
                    .read(
                  rewardVideoProvider
                      .notifier,
                )
                    .markVideoWatched(
                  videoIndex,
                );

                final durationMinutes =
                    adsConfig.adRewardDuration;

                ref
                    .read(
                  freeConnectionTimerProvider
                      .notifier,
                )
                    .addTime(
                  durationMinutes * 60,
                );

                try {
                  final vpnState =
                      ref
                          .read(
                        vpnStateProvider,
                      )
                          .value ??
                          VpnState.disconnected;

                  final server =
                  ref.read(
                    currentServerProvider,
                  );

                  if (vpnState ==
                      VpnState.disconnected &&
                      server != null) {
                    await ref
                        .read(
                      vpnServiceProvider,
                    )
                        .connectToServer(
                      server,
                    );
                  }
                } catch (e) {
                  debugPrint(
                    '⚠️ VPN reconnect error: $e',
                  );
                }

                if (!mounted) return;

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ Free time extended by '
                          '$durationMinutes minutes!',
                    ),
                    backgroundColor:
                    Colors.green,
                  ),
                );
              } catch (e) {
                debugPrint(
                  '❌ Reward callback error: $e',
                );
              }
            },
            onSubscriptionPressed: () async {
              if (!mounted) return;

              Navigator.of(context).pop();

              await Future.delayed(
                const Duration(
                  milliseconds: 100,
                ),
              );

              if (!mounted) return;

              Navigator.pushNamed(
                context,
                '/premium',
              );
            },
          );
        },
      );

      if (!mounted) return;

      if (result == null || result == false) {
        final timer =
        ref.read(
          freeConnectionTimerProvider,
        );

        if (timer.remainingSeconds <= 0) {
          try {
            await ref
                .read(
              currentServerProvider
                  .notifier,
            )
                .setServer(null);

            ref
                .read(vpnServiceProvider)
                .disconnect();
          } catch (e) {
            debugPrint(
              '❌ Disconnect error: $e',
            );
          }

          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(
              const SnackBar(
                content: Text(
                  '❌ VPN Disconnected - Free time expired. '
                      'Watch an ad or subscribe to continue.',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint(
        '❌ Error showing reward popup: $e',
      );
    }
  }

  // ============================================================
  // AUTO CONNECT
  // ============================================================

  Future<void> _handleAutoConnect() async {
    try {
      final autoConnect =
      ref.read(autoConnectProvider);

      if (!autoConnect ||
          _userInitiatedDisconnect) {
        return;
      }

      await Future.delayed(
        const Duration(seconds: 2),
      );

      if (!mounted ||
          _userInitiatedDisconnect) {
        return;
      }

      final vpnState =
          ref.read(vpnStateProvider).value;

      final currentServer =
      ref.read(currentServerProvider);

      if (vpnState == VpnState.disconnected &&
          currentServer == null) {
        await _connectToBestServer();
      }
    } catch (e) {
      debugPrint(
        '⚠️ Auto connect error: $e',
      );
    }
  }

  // ============================================================
  // CONNECT BEST SERVER
  // ============================================================

  Future<void> _connectToBestServer() async {
    try {
      final timerState =
      ref.read(freeConnectionTimerProvider);

      final isSubscribed =
          ref.read(subscriptionProvider).isPremium;

      final isPremiumUser =
          timerState.isPremium ||
              isSubscribed;

      if (timerState.timerExpired &&
          !isPremiumUser) {
        debugPrint(
          '⏰ Best server connection blocked',
        );
        return;
      }

      final apiService =
      ref.read(apiServiceProvider);

      final servers =
      await apiService.getServers();

      if (servers.isEmpty) return;

      final notifier =
      ref.read(
        currentServerProvider.notifier,
      );

      final persistedServerId =
      await notifier.getPersistedServerId();

      if (persistedServerId != null) {
        VpnServer? persisted;

        try {
          persisted = servers.firstWhere(
                (s) => s.id == persistedServerId,
          );
        } catch (_) {
          persisted = null;
        }

        if (persisted != null &&
            !persisted.isFull &&
            (!persisted.premium ||
                isPremiumUser)) {
          await notifier.setServer(
            persisted,
          );

          _isAutoConnecting = true;
          _autoConnectQueue = [];

          final success =
          await ref
              .read(vpnServiceProvider)
              .connectToServer(
            persisted,
          );

          if (success) return;

          _isAutoConnecting = false;

          await notifier.setServer(null);
        }
      }

      final latencies =
      ref.read(serverLatencyProvider);

      final candidates =
      (isPremiumUser
          ? servers.where(
            (s) =>
        s.isActive &&
            !s.isFull,
      )
          : servers.where(
            (s) =>
        !s.premium &&
            s.isActive &&
            !s.isFull,
      ))
          .toList();

      candidates.sort((a, b) {
        final latencyA =
        latencies[a.id];

        final latencyB =
        latencies[b.id];

        if (latencyA != null &&
            latencyB == null) {
          return -1;
        }

        if (latencyA == null &&
            latencyB != null) {
          return 1;
        }

        if (latencyA != null &&
            latencyB != null) {
          return latencyA.compareTo(
            latencyB,
          );
        }

        return a.order.compareTo(
          b.order,
        );
      });

      final queue = candidates
          .where(
            (s) => s.id != persistedServerId,
      )
          .toList();

      if (queue.isEmpty) return;

      final bestServer = queue.first;

      _autoConnectQueue =
          queue.skip(1).toList();

      _isAutoConnecting = true;

      _startAutoConnectTimeout();

      await notifier.setServer(
        bestServer,
      );

      final success =
      await ref
          .read(vpnServiceProvider)
          .connectToServer(
        bestServer,
      );

      if (!success) {
        _autoConnectTimeoutTimer?.cancel();

        _isAutoConnecting = false;

        _autoConnectQueue = [];

        await notifier.setServer(null);
      }
    } catch (e) {
      debugPrint(
        '❌ Connect best server error: $e',
      );

      _autoConnectTimeoutTimer?.cancel();

      _isAutoConnecting = false;

      _autoConnectQueue = [];

      try {
        await ref
            .read(
          currentServerProvider
              .notifier,
        )
            .setServer(null);
      } catch (_) {}
    }
  }

  // ============================================================
  // AUTO CONNECT FALLBACK
  // ============================================================

  Future<void> _tryNextAutoConnectServer() async {
    _autoConnectTimeoutTimer?.cancel();

    if (_autoConnectQueue.isEmpty) {
      _isAutoConnecting = false;
      return;
    }

    final next =
        _autoConnectQueue.first;

    _autoConnectQueue =
        _autoConnectQueue.skip(1).toList();

    debugPrint(
      '🔄 Auto-connect fallback: '
          'trying ${next.name}',
    );

    _startAutoConnectTimeout();

    await ref
        .read(
      currentServerProvider.notifier,
    )
        .setServer(next);

    final success =
    await ref
        .read(vpnServiceProvider)
        .connectToServer(next);

    if (!success) {
      await _tryNextAutoConnectServer();
    }
  }

  // ============================================================
  // AUTO CONNECT TIMEOUT
  // ============================================================

  void _startAutoConnectTimeout() {
    _autoConnectTimeoutTimer?.cancel();

    _autoConnectTimeoutTimer =
        Timer(
          const Duration(seconds: 10),
              () {
            if (!mounted ||
                !_isAutoConnecting) {
              return;
            }

            final state =
                ref.read(vpnStateProvider).value;

            if (state == VpnState.connecting ||
                state == VpnState.waitConnection ||
                state == VpnState.authenticating ||
                state == VpnState.preparing) {
              debugPrint(
                '⏱️ Auto-connect timeout',
              );

              ref
                  .read(vpnServiceProvider)
                  .disconnect();
            }
          },
        );
  }

  // ============================================================
  // TOGGLE CONNECTION
  // ============================================================

  Future<void> _toggleConnection() async {
    if (_isTogglingConnection) return;

    _isTogglingConnection = true;

    try {
      await _doToggleConnection();
    } finally {
      _isTogglingConnection = false;
    }
  }

  Future<void> _doToggleConnection() async {
    final vpnService =
    ref.read(vpnServiceProvider);

    final vpnState =
        ref.read(vpnStateProvider).value ??
            VpnState.disconnected;

    // ----------------------------------------------------------
    // Disconnect
    // ----------------------------------------------------------

    if (vpnState == VpnState.connected ||
        vpnState == VpnState.waitConnection ||
        vpnState == VpnState.connecting ||
        vpnState == VpnState.reconnecting ||
        vpnState == VpnState.preparing ||
        vpnState == VpnState.authenticating) {
      _userInitiatedDisconnect = true;

      await vpnService.disconnect();

      if (!mounted) return;

      await ref
          .read(
        currentServerProvider.notifier,
      )
          .setServer(null);

      _connectionAnimationController
          .reset();

      return;
    }

    if (vpnState != VpnState.disconnected) {
      return;
    }

    _userInitiatedDisconnect = false;

    final currentServer =
    ref.read(currentServerProvider);

    final timerState =
    ref.read(freeConnectionTimerProvider);

    final isSubscribed =
        ref.read(subscriptionProvider).isPremium;

    final isPremiumUser =
        timerState.isPremium ||
            isSubscribed;

    // ----------------------------------------------------------
    // Timer expired
    // ----------------------------------------------------------

    if (!isPremiumUser &&
        timerState.timerExpired) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              '❌ Free time expired. '
                  'Watch an ad or subscribe to connect.',
            ),
            backgroundColor:
            Colors.orangeAccent,
          ),
        );
      }

      return;
    }

    // ----------------------------------------------------------
    // Existing server
    // ----------------------------------------------------------

    if (currentServer != null) {
      final unlockService =
      PremiumServerUnlockService();

      final isUnlocked =
      unlockService.isPremiumServerUnlocked(
        currentServer.id,
      );

      if (currentServer.premium &&
          !isPremiumUser &&
          !isUnlocked) {
        await _showPremiumUnlockPopup(
          currentServer,
        );

        return;
      }

      if (!currentServer.premium &&
          timerState.timerExpired &&
          !isPremiumUser) {
        await _showRewardedAdForTime();

        return;
      }

      _connectionAnimationController
          .forward();

      final success =
      await vpnService.connectToServer(
        currentServer,
      );

      if (!success) {
        _connectionAnimationController
            .reverse();

        if (mounted) {
          await ref
              .read(
            currentServerProvider
                .notifier,
          )
              .setServer(null);
        }
      }

      return;
    }

    // ----------------------------------------------------------
    // No server selected
    // ----------------------------------------------------------

    if (!isPremiumUser &&
        timerState.timerExpired) {
      return;
    }

    _connectionAnimationController
        .forward();

    final servers =
    await ref.read(
      serversProvider.future,
    );

    final candidates =
    isPremiumUser
        ? servers
        .where(
          (s) =>
      s.isActive &&
          !s.isFull,
    )
        .toList()
        : servers
        .where(
          (s) =>
      !s.premium &&
          s.isActive &&
          !s.isFull,
    )
        .toList();

    if (candidates.isEmpty) {
      _connectionAnimationController
          .reverse();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          const SnackBar(
            content: Text(
              'All servers are at full capacity. '
                  'Please try again later or select a server manually.',
            ),
            backgroundColor:
            Colors.orange,
          ),
        );

        _showServerSelection();
      }

      return;
    }

    candidates.sort(
          (a, b) =>
          a.order.compareTo(
            b.order,
          ),
    );

    final bestServer =
        candidates.first;

    await ref
        .read(
      currentServerProvider.notifier,
    )
        .setServer(bestServer);

    final success =
    await vpnService.connectToServer(
      bestServer,
    );

    if (!success && mounted) {
      _connectionAnimationController
          .reverse();

      await ref
          .read(
        currentServerProvider
            .notifier,
      )
          .setServer(null);
    }
  }

  // ============================================================
  // PREMIUM SERVER UNLOCK
  // ============================================================

  Future<void> _showPremiumUnlockPopup(
      VpnServer server,
      ) async {
    try {
      final adsConfig =
      await AdsPopupConfigService()
          .getAdsPopupConfig();

      if (!adsConfig.enablePremiumUnlock) {
        if (!mounted) return;

        ScaffoldMessenger.of(
          context,
        ).showSnackBar(
          SnackBar(
            content: Text(
              AppLocalizations.of(
                context,
              ).subscribeForPremium,
            ),
            backgroundColor:
            Colors.purple,
          ),
        );

        Future.delayed(
          const Duration(seconds: 1),
              () {
            if (mounted) {
              Navigator.pushNamed(
                context,
                '/premium',
              );
            }
          },
        );

        return;
      }

      if (!mounted) return;

      await showModalBottomSheet(
        context: context,
        isDismissible: false,
        enableDrag: false,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) {
          return UnifiedAdsPopupSimple(
            adCount: 1,
            title: AppLocalizations.of(
              context,
            ).unlockPremiumServer,
            subtitle: server.name,
            customText:
            adsConfig.premiumUnlockText,
            showSubscribeButton: false,
            onAction: (action) async {
              if (action ==
                  'all_ads_watched') {
                final unlockService =
                PremiumServerUnlockService();

                await unlockService
                    .unlockPremiumServer(
                  server: server,
                  durationMinutes: adsConfig
                      .premiumUnlockDurationMinutes,
                  unlockedBy: 'ad',
                );

                await ref
                    .read(
                  premiumServerUnlocksProvider
                      .notifier,
                )
                    .notifyUnlock();

                if (!mounted) return;

                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(
                  SnackBar(
                    content: Text(
                      '✅ ${server.name} unlocked for '
                          '${adsConfig.premiumUnlockDurationMinutes} minutes!',
                    ),
                    backgroundColor:
                    Colors.green,
                  ),
                );

                Navigator.of(context).pop();

                await Future.delayed(
                  const Duration(
                    milliseconds: 150,
                  ),
                );

                if (!mounted) return;

                await ref
                    .read(
                  currentServerProvider
                      .notifier,
                )
                    .setServer(server);

                await ref
                    .read(
                  vpnServiceProvider,
                )
                    .connectToServer(
                  server,
                );
              } else if (action ==
                  'subscribe_clicked') {
                if (!mounted) return;

                Navigator.of(context).pop();

                await Future.delayed(
                  const Duration(
                    milliseconds: 150,
                  ),
                );

                if (!mounted) return;

                await Navigator.pushNamed(
                  context,
                  '/premium',
                );
              }
            },
          );
        },
      );
    } catch (e) {
      debugPrint(
        '❌ Premium unlock popup error: $e',
      );
    }
  }

  // ============================================================
  // SERVER SELECTION
  // ============================================================

  void _showServerSelection() {
    if (!mounted) return;

    Navigator.pushNamed(
      context,
      '/servers',
    );
  }

  // ============================================================
  // SERVER DETAILS
  // ============================================================

  void _showServerDetailsBottomSheet(
      VpnServer server,
      ) {
    if (!mounted) return;

    final isDarkMode =
        Theme.of(context).brightness ==
            Brightness.dark;

    final localizations =
    AppLocalizations.of(context);

    final latencies =
    ref.read(serverLatencyProvider);

    final latencyMs =
    latencies[server.id];

    final latencyText =
    latencyMs != null
        ? '$latencyMs${localizations.ms}'
        : '--${localizations.ms}';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return Container(
          decoration: BoxDecoration(
            color: isDarkMode
                ? const Color(0xFF1E293B)
                : Colors.white,
            borderRadius:
            const BorderRadius.vertical(
              top: Radius.circular(24),
            ),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx)
                .viewInsets
                .bottom +
                28,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
            CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin:
                  const EdgeInsets.only(
                    bottom: 16,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey[300],
                    borderRadius:
                    BorderRadius.circular(
                      2,
                    ),
                  ),
                ),
              ),

              Row(
                children: [
                  Container(
                    padding:
                    const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(
                        0xFF10B981,
                      ).withValues(
                        alpha: 0.15,
                      ),
                    ),
                    child: Text(
                      _getCountryEmoji(
                        server.countryCode,
                      ),
                      style:
                      const TextStyle(
                        fontSize: 26,
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment:
                      CrossAxisAlignment
                          .start,
                      children: [
                        Text(
                          server.name,
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight:
                            FontWeight.bold,
                            color: isDarkMode
                                ? Colors.white
                                : Colors.black,
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
                    onTap: () =>
                        Navigator.of(ctx)
                            .pop(),
                    child: Container(
                      padding:
                      const EdgeInsets.all(
                        8,
                      ),
                      decoration:
                      BoxDecoration(
                        color: isDarkMode
                            ? Colors.grey[800]
                            : Colors.grey[100],
                        shape:
                        BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.close,
                        size: 18,
                        color: isDarkMode
                            ? Colors.grey[400]
                            : Colors.grey[600],
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Container(
                width: double.infinity,
                padding:
                const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration:
                BoxDecoration(
                  color: const Color(
                    0xFF10B981,
                  ).withValues(
                    alpha: 0.1,
                  ),
                  borderRadius:
                  BorderRadius.circular(
                    12,
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration:
                      const BoxDecoration(
                        color: Color(
                          0xFF10B981,
                        ),
                        shape:
                        BoxShape.circle,
                      ),
                    ),
                    const SizedBox(
                      width: 10,
                    ),
                    Text(
                      localizations
                          .currentlyConnected,
                      style:
                      const TextStyle(
                        fontSize: 14,
                        color: Color(
                          0xFF10B981,
                        ),
                        fontWeight:
                        FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      latencyText,
                      style:
                      const TextStyle(
                        color: Color(
                          0xFF10B981,
                        ),
                        fontWeight:
                        FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final vpnStateAsync =
    ref.watch(vpnStateProvider);

    final currentServer =
    ref.watch(currentServerProvider);

    final isPremium =
    ref.watch(premiumStatusProvider);

    final themeMode =
    ref.watch(themeModeProvider);

    final isDarkMode =
        themeMode == ThemeMode.dark ||
            (themeMode == ThemeMode.system &&
                MediaQuery.of(context)
                    .platformBrightness ==
                    Brightness.dark);

    // ----------------------------------------------------------
    // Server latency
    // ----------------------------------------------------------

    ref.listen<
        AsyncValue<List<VpnServer>>>(
      serversProvider,
          (_, next) {
        next.whenData((servers) {
          if (servers.isNotEmpty) {
            ref
                .read(
              serverLatencyProvider
                  .notifier,
            )
                .measureLatencies(
              servers,
            );
          }
        });
      },
    );

    // ----------------------------------------------------------
    // VPN state
    // ----------------------------------------------------------

    ref.listen<AsyncValue<VpnState>>(
      vpnStateProvider,
          (previous, next) {
        if (!mounted) return;

        next.whenData((state) async {
          try {
            final currentServer =
            ref.read(
              currentServerProvider,
            );

            switch (state) {
              case VpnState.connected:
                await _handleConnectedState(
                  previous?.value,
                  currentServer,
                );
                break;

              case VpnState.disconnected:
                _handleDisconnectedState(
                  previous?.value,
                );
                break;

              case VpnState.error:
                _handleErrorState();
                break;

              case VpnState.denied:
                _handleDeniedState();
                break;

              default:
                break;
            }
          } catch (e) {
            debugPrint(
              '❌ VPN state listener error: $e',
            );
          }
        });
      },
    );

    // ----------------------------------------------------------
    // Premium state
    // ----------------------------------------------------------

    ref.listen<bool>(
      premiumStatusProvider,
          (previous, next) {
        if (previous == null ||
            previous == next ||
            !mounted) {
          return;
        }

        if (next) {
          _bannerAd?.dispose();
          _connectedNativeAd?.dispose();

          _bannerAd = null;
          _connectedNativeAd = null;

          setState(() {
            _isBannerAdLoaded = false;
            _isConnectedNativeAdLoaded =
            false;
          });
        } else {
          _initializeAds();
        }
      },
    );

    // ----------------------------------------------------------
    // Free timer
    // ----------------------------------------------------------

    ref.listen<FreeConnectionTimerState>(
      freeConnectionTimerProvider,
          (previous, next) {
        debugPrint(
          '🔔 Timer state: '
              'expired=${next.timerExpired}, '
              'premium=${next.isPremium}',
        );

        if (next.timerExpired &&
            !next.isPremium &&
            next.isAdUnlockTimer) {
          ref
              .read(
            currentServerProvider
                .notifier,
          )
              .setServer(null);
        }
      },
    );

    // ----------------------------------------------------------
    // UI
    // ----------------------------------------------------------

    return Container(
      color: isDarkMode
          ? const Color(0xFF0F172A)
          : Colors.white,
      child: SafeArea(
        child: Column(
          children: [
            const SubscriptionBanner(),

            Expanded(
              child: vpnStateAsync.when(
                loading: () =>
                    _buildConnectionSection(
                      VpnState.disconnected,
                      currentServer,
                      isDarkMode,
                      isPremium,
                    ),
                error: (error, stack) =>
                    Center(
                      child: Column(
                        mainAxisAlignment:
                        MainAxisAlignment
                            .center,
                        children: [
                          const Icon(
                            Icons.error_outline,
                            size: 64,
                            color: Colors.red,
                          ),
                          const SizedBox(
                            height: 16,
                          ),
                          Text(
                            'Error: $error',
                            style:
                            const TextStyle(
                              color: Colors.red,
                            ),
                            textAlign:
                            TextAlign.center,
                          ),
                          const SizedBox(
                            height: 16,
                          ),
                          ElevatedButton(
                            onPressed: () {
                              ref.invalidate(
                                vpnStateProvider,
                              );
                            },
                            child:
                            const Text(
                              'Retry',
                            ),
                          ),
                        ],
                      ),
                    ),
                data: (vpnState) =>
                    _buildConnectionSection(
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

  // ============================================================
  // CONNECTED STATE
  // ============================================================

  Future<void> _handleConnectedState(
      VpnState? previousState,
      VpnServer? currentServer,
      ) async {
    var effectiveServer = currentServer;

    if (effectiveServer == null) {
      effectiveServer =
          ref
              .read(vpnServiceProvider)
              .currentServer;

      if (effectiveServer != null &&
          mounted) {
        await ref
            .read(
          currentServerProvider
              .notifier,
        )
            .setServer(
          effectiveServer,
        );
      }
    }

    if (effectiveServer == null) {
      return;
    }

    final shouldShowInterstitial =
        previousState != null &&
            previousState !=
                VpnState.connected &&
            !ref.read(
              premiumStatusProvider,
            ) &&
            !_hasShownConnectInterstitial;

    if (shouldShowInterstitial) {
      _hasShownConnectInterstitial =
      true;

      AdMobService.instance
          .showConnectionInterstitialAd();
    }

    if (!mounted) return;

    _connectionAnimationController
        .forward();

    final speedService =
    ref.read(
      networkSpeedServiceProvider,
    );

    speedService.startMonitoring();

    // ----------------------------------------------------------
    // Timer
    // ----------------------------------------------------------

    final server = effectiveServer;

    final isPremium =
    ref.read(
      premiumStatusProvider,
    );

    if (server.premium) {
      final unlockService =
      PremiumServerUnlockService();

      await unlockService.initialize();

      final unlock =
      unlockService.getUnlockInfo(
        server.id,
      );

      final isAdUnlocked =
          unlock?.isStillUnlocked ?? false;

      if (isAdUnlocked) {
        ref
            .read(
          freeConnectionTimerProvider
              .notifier,
        )
            .startFromSeconds(
          server,
          unlock!.remainingSeconds,
        );
      } else if (isPremium) {
        ref
            .read(
          freeConnectionTimerProvider
              .notifier,
        )
            .startTimer(
          server,
          true,
        );
      } else {
        ref
            .read(vpnServiceProvider)
            .disconnect();
      }
    } else if (isPremium) {
      ref
          .read(
        freeConnectionTimerProvider
            .notifier,
      )
          .startTimer(
        server,
        true,
      );
    } else if (server.freeConnectDuration >
        0) {
      final vpnService =
      ref.read(vpnServiceProvider);

      final connectionStart =
          vpnService.connectionStartTime;

      if (connectionStart != null) {
        final elapsed =
            DateTime.now()
                .difference(
              connectionStart,
            )
                .inSeconds;

        final totalSeconds =
            server.freeConnectDuration *
                60;

        final remaining =
            totalSeconds - elapsed;

        if (remaining <= 0) {
          vpnService.disconnect();
        } else {
          ref
              .read(
            freeConnectionTimerProvider
                .notifier,
          )
              .startFromSeconds(
            server,
            remaining,
          );
        }
      } else {
        ref
            .read(
          freeConnectionTimerProvider
              .notifier,
        )
            .startTimer(
          server,
          false,
        );
      }
    } else {
      ref
          .read(
        freeConnectionTimerProvider
            .notifier,
      )
          .startTimer(
        server,
        false,
      );
    }

    ref.invalidate(ipAddressProvider);

    if (!_wasConnected) {
      _wasConnected = true;
      _startElapsedTimer();
    }
  }

  // ============================================================
  // DISCONNECTED STATE
  // ============================================================

  void _handleDisconnectedState(
      VpnState? previousState,
      ) {
    _connectionAnimationController
        .reverse();

    _hasShownConnectInterstitial = false;

    _wasConnected = false;

    _stopElapsedTimer();

    final speedService =
    ref.read(
      networkSpeedServiceProvider,
    );

    speedService.stopMonitoring();

    final timerState =
    ref.read(
      freeConnectionTimerProvider,
    );

    if (!timerState.timerExpired) {
      ref
          .read(
        freeConnectionTimerProvider
            .notifier,
      )
          .stopTimer();
    }

    ref.invalidate(ipAddressProvider);

    if (!ref.read(premiumStatusProvider)) {
      AdMobService.instance
          .showConnectionInterstitialAd();
    }

    _handleKillSwitch(
      previousState,
    );
  }

  // ============================================================
  // ERROR STATE
  // ============================================================

  void _handleErrorState() {
    _connectionAnimationController
        .reverse();

    _hasShownConnectInterstitial = false;

    ref
        .read(
      freeConnectionTimerProvider
          .notifier,
    )
        .stopTimer();

    ref
        .read(
      currentServerProvider.notifier,
    )
        .setServer(null);

    if (_isAutoConnecting &&
        _autoConnectQueue.isNotEmpty) {
      _tryNextAutoConnectServer();
    } else {
      _isAutoConnecting = false;
      _autoConnectQueue = [];
    }
  }

  // ============================================================
  // DENIED STATE
  // ============================================================

  void _handleDeniedState() {
    _connectionAnimationController
        .reverse();

    _hasShownConnectInterstitial = false;

    ref
        .read(
      freeConnectionTimerProvider
          .notifier,
    )
        .stopTimer();
  }

  // ============================================================
  // CONNECTION SECTION
  // ============================================================

  Widget _buildConnectionSection(
      VpnState vpnState,
      VpnServer? currentServer,
      bool isDarkMode,
      bool isPremium,
      ) {
    final themeColor =
    ref.watch(themeColorProvider);

    final networkSpeedAsync =
    ref.watch(networkSpeedProvider);

    final isConnected =
        vpnState == VpnState.connected;

    return SingleChildScrollView(
      child: Padding(
        padding:
        const EdgeInsets.symmetric(
          horizontal: 20,
          vertical: 12,
        ),
        child: Column(
          mainAxisAlignment:
          MainAxisAlignment.center,
          crossAxisAlignment:
          CrossAxisAlignment.center,
          children: [
            // ----------------------------------------------------
            // SERVER SELECTOR
            // ----------------------------------------------------

            FadeInDown(
              delay: const Duration(
                milliseconds: 50,
              ),
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(
                    context,
                    '/servers',
                  );
                },
                child: Container(
                  width: double.infinity,
                  padding:
                  const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  decoration:
                  BoxDecoration(
                    color: isDarkMode
                        ? const Color(
                      0xFF1E293B,
                    )
                        : Colors.white,
                    borderRadius:
                    BorderRadius.circular(
                      16,
                    ),
                    border: Border.all(
                      color: isConnected
                          ? themeColor.withValues(
                        alpha: 0.4,
                      )
                          : isDarkMode
                          ? const Color(
                        0xFF334155,
                      )
                          : const Color(
                        0xFFE5E7EB,
                      ),
                      width: 1.5,
                    ),
                    boxShadow: isConnected
                        ? [
                      BoxShadow(
                        color: themeColor
                            .withValues(
                          alpha: 0.12,
                        ),
                        blurRadius: 14,
                        spreadRadius: 2,
                      ),
                    ]
                        : null,
                  ),
                  child: Row(
                    children: [
                      if (currentServer !=
                          null) ...[
                        Text(
                          _getCountryEmoji(
                            currentServer
                                .countryCode,
                          ),
                          style:
                          const TextStyle(
                            fontSize: 30,
                          ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Text(
                                currentServer
                                    .name,
                                maxLines: 1,
                                overflow:
                                TextOverflow
                                    .ellipsis,
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight:
                                  FontWeight
                                      .bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(
                                height: 2,
                              ),
                              Text(
                                currentServer
                                    .country,
                                style:
                                TextStyle(
                                  color: isDarkMode
                                      ? const Color(
                                    0xFF94A3B8,
                                  )
                                      : Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ] else ...[
                        Container(
                          padding:
                          const EdgeInsets.all(
                            8,
                          ),
                          decoration:
                          BoxDecoration(
                            color: themeColor
                                .withValues(
                              alpha: 0.15,
                            ),
                            shape:
                            BoxShape.circle,
                          ),
                          child: Icon(
                            Icons.bolt,
                            color:
                            themeColor,
                            size: 20,
                          ),
                        ),
                        const SizedBox(
                          width: 12,
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                            CrossAxisAlignment
                                .start,
                            children: [
                              Text(
                                'Select Location',
                                style:
                                TextStyle(
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight:
                                  FontWeight
                                      .bold,
                                  fontSize: 15,
                                ),
                              ),
                              const SizedBox(
                                height: 2,
                              ),
                              Text(
                                'Tap to select a server',
                                style:
                                TextStyle(
                                  color: isDarkMode
                                      ? const Color(
                                    0xFF94A3B8,
                                  )
                                      : Colors.grey[600],
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],

                      Row(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: [
                          if (isConnected) ...[
                            Container(
                              padding:
                              const EdgeInsets
                                  .symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration:
                              BoxDecoration(
                                color: themeColor
                                    .withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius:
                                BorderRadius
                                    .circular(
                                  8,
                                ),
                              ),
                              child: Text(
                                'CONNECTED',
                                style:
                                TextStyle(
                                  color:
                                  themeColor,
                                  fontSize: 10,
                                  fontWeight:
                                  FontWeight
                                      .bold,
                                ),
                              ),
                            ),
                            const SizedBox(
                              width: 6,
                            ),
                          ],
                          Icon(
                            Icons.chevron_right,
                            color: isDarkMode
                                ? const Color(
                              0xFF64748B,
                            )
                                : Colors.grey[400],
                            size: 22,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // ----------------------------------------------------
            // POWER BUTTON
            // ----------------------------------------------------

            FadeInDown(
              child: GestureDetector(
                onTap: _toggleConnection,
                child: AnimatedBuilder(
                  animation: isConnected
                      ? _pulseAnimation
                      : _scaleAnimation,
                  builder:
                      (context, child) {
                    final pulse =
                    isConnected
                        ? _pulseAnimation
                        .value
                        : _scaleAnimation
                        .value;

                    final ringA = isConnected
                        ? ((_pulseAnimation
                        .value -
                        1.0) *
                        6)
                        .clamp(
                      0.06,
                      0.20,
                    )
                        : 0.07;

                    final connColor =
                    _getConnectionColor(
                      vpnState,
                      themeColor:
                      themeColor,
                    );

                    return SizedBox(
                      width: 214,
                      height: 214,
                      child: Stack(
                        alignment:
                        Alignment.center,
                        children: [
                          Container(
                            width: 210,
                            height: 210,
                            decoration:
                            BoxDecoration(
                              shape: BoxShape
                                  .circle,
                              border:
                              Border.all(
                                color: connColor
                                    .withValues(
                                  alpha:
                                  ringA,
                                ),
                                width: 1.5,
                              ),
                            ),
                          ),

                          Container(
                            width: 182,
                            height: 182,
                            decoration:
                            BoxDecoration(
                              shape: BoxShape
                                  .circle,
                              border:
                              Border.all(
                                color: connColor
                                    .withValues(
                                  alpha:
                                  (ringA *
                                      1.7)
                                      .clamp(
                                    0.0,
                                    1.0,
                                  ),
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
                              decoration:
                              BoxDecoration(
                                shape: BoxShape
                                    .circle,
                                gradient:
                                _getConnectionGradient(
                                  vpnState,
                                  themeColor:
                                  themeColor,
                                ),
                                border: vpnState ==
                                    VpnState
                                        .disconnected
                                    ? Border.all(
                                  color:
                                  themeColor,
                                  width:
                                  3,
                                )
                                    : null,
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                    connColor
                                        .withValues(
                                      alpha: vpnState ==
                                          VpnState
                                              .disconnected
                                          ? 0.2
                                          : 0.45,
                                    ),
                                    blurRadius:
                                    vpnState ==
                                        VpnState
                                            .disconnected
                                        ? 20
                                        : 36,
                                    spreadRadius:
                                    vpnState ==
                                        VpnState
                                            .disconnected
                                        ? 4
                                        : 12,
                                  ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Container(
                                    decoration:
                                    const BoxDecoration(
                                      shape: BoxShape
                                          .circle,
                                      color:
                                      Colors.black12,
                                    ),
                                  ),

                                  Center(
                                    child:
                                    _buildConnectionIcon(
                                      vpnState,
                                      themeColor:
                                      themeColor,
                                    ),
                                  ),

                                  if (vpnState ==
                                      VpnState
                                          .connecting ||
                                      vpnState ==
                                          VpnState
                                              .authenticating)
                                    const Center(
                                      child:
                                      SizedBox(
                                        width: 170,
                                        height: 170,
                                        child:
                                        CircularProgressIndicator(
                                          strokeWidth:
                                          2.5,
                                          valueColor:
                                          AlwaysStoppedAnimation<
                                              Color>(
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

            // ----------------------------------------------------
            // STATUS
            // ----------------------------------------------------

            FadeInUp(
              delay: const Duration(
                milliseconds: 200,
              ),
              child: Text(
                _getStatusText(
                  vpnState,
                ),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight:
                  FontWeight.bold,
                  color:
                  _getConnectionColor(
                    vpnState,
                    themeColor:
                    themeColor,
                  ),
                ),
                textAlign:
                TextAlign.center,
              ),
            ),

            const SizedBox(height: 6),

            FadeInUp(
              delay: const Duration(
                milliseconds: 250,
              ),
              child: Text(
                isConnected
                    ? AppLocalizations.of(
                  context,
                ).connectionSecure
                    : vpnState ==
                    VpnState
                        .connecting
                    ? 'Setting secure connection...'
                    : AppLocalizations.of(
                  context,
                ).connectionNotSecure,
                style: TextStyle(
                  fontSize: 13,
                  color: isDarkMode
                      ? const Color(
                    0xFF94A3B8,
                  )
                      : const Color(
                    0xFF6B7280,
                  ),
                ),
                textAlign:
                TextAlign.center,
              ),
            ),

            // ----------------------------------------------------
            // ELAPSED TIME
            // ----------------------------------------------------

            if (isConnected) ...[
              const SizedBox(
                height: 12,
              ),
              FadeInUp(
                child: Text(
                  _formattedElapsedTime,
                  style: TextStyle(
                    fontSize: 40,
                    fontWeight:
                    FontWeight.bold,
                    color: isDarkMode
                        ? Colors.white
                        : Colors.black87,
                    letterSpacing: 2,
                  ),
                ),
              ),
            ],

            // ----------------------------------------------------
            // SPEED
            // ----------------------------------------------------

            if (isConnected) ...[
              const SizedBox(
                height: 12,
              ),
              FadeInUp(
                delay: const Duration(
                  milliseconds: 300,
                ),
                child: networkSpeedAsync
                    .when(
                  data: (speed) {
                    return Container(
                      padding:
                      const EdgeInsets
                          .symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      decoration:
                      BoxDecoration(
                        color: isDarkMode
                            ? const Color(
                          0xFF1E293B,
                        )
                            : Colors.white,
                        borderRadius:
                        BorderRadius
                            .circular(
                          14,
                        ),
                        border: Border.all(
                          color: isDarkMode
                              ? const Color(
                            0xFF334155,
                          )
                              : const Color(
                            0xFFE5E7EB,
                          ),
                        ),
                      ),
                      child: Row(
                        mainAxisSize:
                        MainAxisSize.min,
                        children: [
                          Column(
                            children: [
                              Icon(
                                Icons
                                    .arrow_downward,
                                color:
                                themeColor,
                                size: 18,
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                speed
                                    .formattedDownloadSpeed,
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight:
                                  FontWeight
                                      .bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Download',
                                style:
                                TextStyle(
                                  color: isDarkMode
                                      ? const Color(
                                    0xFF94A3B8,
                                  )
                                      : Colors.grey[600],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),

                          Container(
                            margin:
                            const EdgeInsets
                                .symmetric(
                              horizontal: 24,
                            ),
                            width: 1,
                            height: 40,
                            color: isDarkMode
                                ? const Color(
                              0xFF334155,
                            )
                                : const Color(
                              0xFFE5E7EB,
                            ),
                          ),

                          Column(
                            children: [
                              const Icon(
                                Icons
                                    .arrow_upward,
                                color: Color(
                                  0xFFF59E0B,
                                ),
                                size: 18,
                              ),
                              const SizedBox(
                                height: 4,
                              ),
                              Text(
                                speed
                                    .formattedUploadSpeed,
                                style: TextStyle(
                                  color: isDarkMode
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight:
                                  FontWeight
                                      .bold,
                                  fontSize: 13,
                                ),
                              ),
                              Text(
                                'Upload',
                                style:
                                TextStyle(
                                  color: isDarkMode
                                      ? const Color(
                                    0xFF94A3B8,
                                  )
                                      : Colors.grey[600],
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                  loading: () =>
                  const SizedBox.shrink(),
                  error: (_, __) =>
                  const SizedBox.shrink(),
                ),
              ),
            ],

            // ----------------------------------------------------
            // NATIVE AD
            // ----------------------------------------------------

            if (!isPremium &&
                _isConnectedNativeAdLoaded &&
                _connectedNativeAd != null) ...[
              const SizedBox(height: 14),
              FadeInUp(
                delay: Duration(
                  milliseconds:
                  isConnected ? 650 : 400,
                ),
                child: Container(
                  height:
                  isConnected ? 320 : 280,
                  width: double.infinity,
                  margin:
                  const EdgeInsets.symmetric(
                    horizontal: 6,
                  ),
                  decoration:
                  BoxDecoration(
                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                    color: isDarkMode
                        ? const Color(
                      0xFF1E293B,
                    )
                        : Colors.white,
                    border: Border.all(
                      color: isDarkMode
                          ? Colors.white
                          .withValues(
                        alpha: 0.08,
                      )
                          : Colors.black
                          .withValues(
                        alpha: 0.05,
                      ),
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius:
                    BorderRadius.circular(
                      12,
                    ),
                    child: AdWidget(
                      ad: _connectedNativeAd!,
                    ),
                  ),
                ),
              ),
            ],

            const SizedBox(
              height: 20,
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CONNECTION ICON
  // ============================================================

  Widget _buildConnectionIcon(
      VpnState vpnState, {
        Color? themeColor,
      }) {
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
        return const Icon(
          Icons.error_outline,
          size: 44,
          color: Colors.white60,
        );

      default:
        return Icon(
          Icons.power_settings_new,
          size: 44,
          color: themeColor ??
              const Color(0xFFFA0602),
        );
    }
  }

  // ============================================================
  // CONNECTION GRADIENT
  // ============================================================

  LinearGradient _getConnectionGradient(
      VpnState vpnState, {
        Color? themeColor,
      }) {
    switch (vpnState) {
      case VpnState.connected:
        return const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF22C55E),
            Color(0xFF16A34A),
          ],
        );

      case VpnState.connecting:
      case VpnState.authenticating:
        return const LinearGradient(
          colors: [
            Color(0xFFF59E0B),
            Color(0xFFD97706),
          ],
        );

      case VpnState.error:
        return const LinearGradient(
          colors: [
            Color(0xFFEF4444),
            Color(0xFFDC2626),
          ],
        );

      default:
        return LinearGradient(
          colors: [
            (themeColor ??
                const Color(0xFF2563EB))
                .withValues(
              alpha: 0.12,
            ),
            const Color(0xFFF8FAFF),
          ],
        );
    }
  }

  // ============================================================
  // CONNECTION COLOR
  // ============================================================

  Color _getConnectionColor(
      VpnState vpnState, {
        Color? themeColor,
      }) {
    switch (vpnState) {
      case VpnState.connected:
        return const Color(
          0xFF22C55E,
        );

      case VpnState.connecting:
      case VpnState.authenticating:
        return const Color(
          0xFFF59E0B,
        );

      case VpnState.error:
        return const Color(
          0xFFEF4444,
        );

      default:
        return themeColor ??
            const Color(0xFF2563EB);
    }
  }

  // ============================================================
  // STATUS TEXT
  // ============================================================

  String _getStatusText(
      VpnState vpnState,
      ) {
    final l10n =
    AppLocalizations.of(context);

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
        if (_isAutoConnecting &&
            _autoConnectQueue.isNotEmpty) {
          return l10n.connectingStatus;
        }

        return l10n.connectionError;

      case VpnState.denied:
        return l10n.permissionDeniedStatus;

      default:
        return l10n.notProtected;
    }
  }

  // ============================================================
  // COUNTRY EMOJI
  // ============================================================

  String _getCountryEmoji(
      String country,
      ) {
    final code =
    country.toUpperCase().trim();

    if (code.length != 2) {
      return '🌍';
    }

    final first =
    code.codeUnitAt(0);

    final second =
    code.codeUnitAt(1);

    if (first < 65 ||
        first > 90 ||
        second < 65 ||
        second > 90) {
      return '🌍';
    }

    return String.fromCharCodes([
      0x1F1E6 + first - 65,
      0x1F1E6 + second - 65,
    ]);
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _autoConnectTimeoutTimer?.cancel();
    _autoConnectTimeoutTimer = null;

    _elapsedTimer?.cancel();
    _elapsedTimer = null;

    _connectionAnimationController
        .dispose();

    _pulseAnimationController.dispose();

    _bannerAd?.dispose();
    _bannerAd = null;

    _connectedNativeAd?.dispose();
    _connectedNativeAd = null;

    super.dispose();
  }
}