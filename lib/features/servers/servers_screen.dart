import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import '../../core/api/api_service.dart';
import '../../core/localization/app_localizations.dart';
import '../../core/services/vpn_state.dart' as multi_vpn;
import '../../core/services/admob_service.dart';
import '../../services/ads_popup_config_service.dart';
import '../../services/premium_server_unlock_service.dart';

import '../../shared/providers/app_providers.dart';
import '../../shared/providers/theme_provider.dart';
import '../../shared/widgets/loading_widget.dart';
import '../../shared/widgets/error_widget.dart';
import '../../widgets/unified_ads_popup_simple.dart';
import '../../core/services/level_play_service.dart';
class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

// Global key to access the servers screen state from main shell
final GlobalKey<_ServersScreenState> serversScreenKey =
GlobalKey<_ServersScreenState>();

class _ServersScreenState extends ConsumerState<ServersScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
  // One scroll controller per tab (Free / Premium)
  final List<ScrollController> _scrollControllers = [
    ScrollController(),
    ScrollController(),
  ];
  String _searchQuery = '';
  bool _showPremiumOnly = false;
  bool _showFreeOnly = false;
  final TextEditingController _searchController = TextEditingController();

  // Ad variables
  BannerAd? _bannerAd;
  bool _isBannerAdLoaded = false;

  DateTime? _lastVpnInterstitialAt;
  String? _pendingVpnInterstitialPlacement;
  bool _isAppResumed = true;
  bool _vpnInterstitialShowing = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 2, vsync: this);
    _initializeAds();
    // Initialize premium unlock service to load saved unlocks from storage
    PremiumServerUnlockService()
        .initialize()
        .then((_) {
      debugPrint('✅ Premium unlock service initialized');
    })
        .catchError((e) {
      debugPrint('❌ Error initializing premium unlock service: $e');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _isAppResumed = state == AppLifecycleState.resumed;

    if (_isAppResumed && _pendingVpnInterstitialPlacement != null) {
      final placement = _pendingVpnInterstitialPlacement!;
      _pendingVpnInterstitialPlacement = null;
      _showVpnInterstitial(placement);
    }
  }

  Future<void> _showVpnInterstitial(String placementName) async {
    if (!mounted) return;

    final isPremiumNow = ref.read(premiumStatusProvider);
    if (isPremiumNow) {
      debugPrint('[VPN ADS] Premium user - skip $placementName');
      return;
    }

    if (!_isAppResumed) {
      debugPrint('[VPN ADS] App not resumed - queue $placementName');
      _pendingVpnInterstitialPlacement = placementName;
      return;
    }

    final now = DateTime.now();
    if (_lastVpnInterstitialAt != null &&
        now.difference(_lastVpnInterstitialAt!) <
            const Duration(seconds: 10)) {
      debugPrint('[VPN ADS] Cooldown active - skip $placementName');
      return;
    }

    if (_vpnInterstitialShowing) {
      debugPrint(
        '[VPN ADS] Interstitial already showing - skip $placementName',
      );
      return;
    }

    _vpnInterstitialShowing = true;
    _lastVpnInterstitialAt = now;

    try {
      debugPrint('[VPN ADS] Request Interstitial: $placementName');

      final levelPlay = LevelPlayService.instance;

      await levelPlay.refreshPremiumStatus();

      if (!mounted) return;



      if (!mounted || !_isAppResumed) {
        _pendingVpnInterstitialPlacement = placementName;
        return;
      }

      debugPrint(
        '[VPN ADS] Showing Interstitial: $placementName',
      );

      await levelPlay.showInterstitial(
        placementName: placementName,
      );
    } catch (e, stackTrace) {
      debugPrint('[VPN ADS] Interstitial error: $e');
      debugPrint('$stackTrace');
    } finally {
      _vpnInterstitialShowing = false;
    }
  }

  void _initializeAds() {
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
        debugPrint('Top banner ad failed to load: $error');
        ad.dispose();
      },
    );
    //_bannerAd?.load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final sc in _scrollControllers) {
      sc.dispose();
    }
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _bannerAd?.dispose();
    super.dispose();
  }

  // Helper method to check if any filters are active
  bool get _hasActiveFilters {
    return _searchQuery.isNotEmpty || _showPremiumOnly || _showFreeOnly;
  }

  Widget _buildFilterStatusBar(bool isDarkMode) {
    if (!_hasActiveFilters) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF3B82F6).withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: const Color(0xFF3B82F6).withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.filter_list, size: 16, color: const Color(0xFF3B82F6)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _buildFilterText(),
              style: TextStyle(
                fontSize: 12,
                color: const Color(0xFF3B82F6),
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          GestureDetector(
            onTap: clearSearchAndFilters,
            child: Container(
              padding: const EdgeInsets.all(4),
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Icon(
                Icons.close,
                size: 14,
                color: const Color(0xFF3B82F6),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildFilterText() {
    List<String> filters = [];

    if (_searchQuery.isNotEmpty) {
      filters.add('Search: "$_searchQuery"');
    }

    if (_showPremiumOnly) {
      filters.add('Premium only');
    }

    if (_showFreeOnly) {
      filters.add('Free only');
    }

    return 'Active filters: ${filters.join(', ')}';
  }

  // Public methods to trigger dialogs from AppBar


  void triggerFilterDialog() {
    _showFilterDialog();
  }

  void clearSearchAndFilters() {
    setState(() {
      _searchQuery = '';
      _searchController.clear();
      _showPremiumOnly = false;
      _showFreeOnly = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final serversAsync = ref.watch(serversProvider);
    final favoriteServers = ref.watch(favoriteServersProvider);
    final isPremium = ref.watch(premiumStatusProvider);
    final currentServer = ref.watch(currentServerProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    // Trigger TCP-connect latency measurement when server list loads/refreshes
    ref.listen<AsyncValue<List<VpnServer>>>(serversProvider, (_, next) {
      next.whenData((servers) {
        ref.read(serverLatencyProvider.notifier).measureLatencies(servers);
      });
    });

    // Listen to VPN state changes.
    // Connected -> LevelPlay Interstitial
    // Disconnected -> LevelPlay Interstitial
    ref.listen<AsyncValue<multi_vpn.VpnState>>(
      vpnStateProvider,
          (previous, next) {
        next.whenData((state) async {
          final previousState = previous?.value;

          debugPrint(
            '🔄 VPN Stage Changed: $state (previous: $previousState)',
          );

          // Ignore duplicate notifications and initial disconnected state.
          if (state == previousState) return;

          // Always read current values.
          final currentPremium =
          ref.read(premiumStatusProvider);
          final selectedServer =
          ref.read(currentServerProvider);

          // ==================================================
          // VPN DISCONNECTED
          // ==================================================
          if (state == multi_vpn.VpnState.disconnected) {
            final timerStateOnDisc =
            ref.read(freeConnectionTimerProvider);

            if (!timerStateOnDisc.timerExpired) {
              ref
                  .read(freeConnectionTimerProvider.notifier)
                  .stopTimer();
            }

            debugPrint('🔌 VPN Disconnected');

            if (!currentPremium) {
              await _showVpnInterstitial(
                'vpn_disconnected',
              );
            }

            return;
          }

          // ==================================================
          // VPN CONNECTED
          // ==================================================
          if (state == multi_vpn.VpnState.connected) {
            debugPrint('📡 VPN Connected');

            // Existing free connection timer logic.
            if (!currentPremium &&
                selectedServer != null) {
              final unlock = selectedServer.premium
                  ? PremiumServerUnlockService()
                  .getUnlockInfo(
                selectedServer.id,
              )
                  : null;

              final isAdUnlocked =
                  unlock?.isStillUnlocked ?? false;

              if (isAdUnlocked) {
                ref
                    .read(
                  freeConnectionTimerProvider
                      .notifier,
                )
                    .startFromSeconds(
                  selectedServer,
                  unlock!.remainingSeconds,
                );
              } else {
                ref
                    .read(
                  freeConnectionTimerProvider
                      .notifier,
                )
                    .startTimer(
                  selectedServer,
                  currentPremium,
                );
              }
            }

            if (!currentPremium) {
              await _showVpnInterstitial(
                'vpn_connected',
              );
            }
          }
        });
      },
    );

    final themeColor = ref.watch(themeColorProvider);

    return Container(
      color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8F9FA),
      child: Column(
        children: [
          // Premium upgrade banner (non-premium users only)
          //if (!isPremium)



          // Main Content
          Expanded(
            child: Column(
              children: [
                // Tabs
                Material(
                  color: isDarkMode
                      ? const Color(0xFF0F172A)
                      : const Color(0xFFF8F9FA),
                  child: TabBar(
                    controller: _tabController,
                    indicatorColor: themeColor,
                    labelColor: themeColor,
                    unselectedLabelColor: isDarkMode
                        ? const Color(0xFF94A3B8)
                        : Colors.grey[600],
                    tabs: const [
                      Tab(
                        icon: Icon(Icons.wifi, size: 14),
                        text: 'FREE SERVERS',
                      ),
                      Tab(
                        icon: Icon(Icons.paid, size: 14),
                        text: 'VIP SERVERS',
                      ),
                    ],
                  ),
                ),
                // Filter status bar
                _buildFilterStatusBar(isDarkMode),
                // Server List
                Expanded(
                  child: serversAsync.when(
                    loading: () => const LoadingWidget(),
                    error: (error, stack) => ErrorRetryWidget(
                      message: AppLocalizations.of(context).failedToLoadServers,
                      onRetry: () => ref.refresh(serversProvider),
                    ),
                    data: (servers) {
                      return TabBarView(
                        controller: _tabController,
                        children: [
                          // Free Servers
                          _buildServerList(
                            servers,
                            false,
                            favoriteServers,
                            isPremium,
                            currentServer,
                            isDarkMode,
                            tabIndex: 0,
                          ),
                          // Premium Servers
                          _buildServerList(
                            servers,
                            true,
                            favoriteServers,
                            isPremium,
                            currentServer,
                            isDarkMode,
                            tabIndex: 1,
                          ),
                        ],
                      );
                    },
                  ),
                ),
                // Bottom Banner Ad
                if (!isPremium && _isBannerAdLoaded && _bannerAd != null)
                  Container(
                    height: 60,
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AdWidget(ad: _bannerAd!),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildServerList(
      List<VpnServer> allServers,
      bool? premiumFilter,
      Set<String> favoriteServers,
      bool isPremium,
      VpnServer? currentServer,
      bool isDarkMode, {
        int tabIndex = 0,
      }) {
    // Filter servers
    List<VpnServer> filteredServers = allServers.where((server) {
      // Apply search filter
      bool matchesSearch =
          _searchQuery.isEmpty ||
              server.name.toLowerCase().contains(_searchQuery) ||
              server.country.toLowerCase().contains(_searchQuery);

      // Apply tab-level premium filter
      bool matchesPremium =
          premiumFilter == null || server.premium == premiumFilter;

      // Apply dialog-level premium/free filters on top of tab filtering
      if (_showPremiumOnly && !server.premium) return false;
      if (_showFreeOnly && server.premium) return false;

      // Ensure server supports at least one protocol (OpenVPN, WireGuard, or OneConnect)
      bool hasProtocol =
          server.supportsOpenVPN ||
              server.supportsWireGuard ||
              server.isOneConnect;

      return matchesSearch && matchesPremium && server.isActive && hasProtocol;
    }).toList();

    // Sort: favorites first, full/at-capacity servers last, then by order
    filteredServers.sort((a, b) {
      final aFav = favoriteServers.contains(a.id);
      final bFav = favoriteServers.contains(b.id);
      if (aFav && !bFav) return -1;
      if (!aFav && bFav) return 1;
      // Push full (100% capacity) servers to the bottom
      final aFull = a.isFull || a.load >= 1.0;
      final bFull = b.isFull || b.load >= 1.0;
      if (aFull && !bFull) return 1;
      if (!aFull && bFull) return -1;
      return a.order.compareTo(b.order);
    });

    if (filteredServers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.wifi_off,
              size: 64,
              color: isDarkMode ? Colors.grey[600] : Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context).noServersFound,
              style: TextStyle(
                fontSize: 18,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // For free servers tab, add Smart Connect as first item
    final smartConnectOffset = tabIndex == 0 ? 1 : 0;
    // For non-premium, add a native ad at the very top (position after smart connect)
    final topAdOffset = (!isPremium) ? 1 : 0;
    final totalOffset = smartConnectOffset + topAdOffset;

    return ListView.builder(
      key: ValueKey(
        'servers_list_${tabIndex}_${filteredServers.length}_$isPremium',
      ),
      controller: _scrollControllers[tabIndex],
      padding: const EdgeInsets.all(16),
      itemCount: isPremium
          ? filteredServers.length
          : filteredServers.length +
          totalOffset +
          ((filteredServers.length + 3) ~/ 4),
      itemBuilder: (context, index) {
        // Safety check for index bounds
        if (index < 0) return const SizedBox.shrink();

        // Smart Connect card at position 0 for free tab
        if (tabIndex == 0 && index == 0) {
          return _buildSmartConnectCard(isDarkMode, currentServer);
        }

        // Top native ad for non-premium users right after smart connect (or at top for premium tab)
        if (!isPremium && index == smartConnectOffset) {
          return _buildNativeAdCard(isDarkMode);
        }

        // Adjust index for smart connect + top ad offsets
        final adjustedIndex = index - totalOffset;

        // Show native ad every 4th item for non-premium users (based on adjusted index)
        if (!isPremium && (adjustedIndex + 1) % 4 == 0) {
          return _buildNativeAdCard(isDarkMode);
        }

        // Calculate actual server index (accounting for all offsets)
        int serverIndex = isPremium
            ? adjustedIndex
            : adjustedIndex - ((adjustedIndex + 1) ~/ 4);

        // Additional safety checks
        if (serverIndex < 0 || serverIndex >= filteredServers.length) {
          return const SizedBox.shrink();
        }

        final server = filteredServers[serverIndex];
        // Only show as connected when VPN is truly connected (not just selected)
        final vpnState =
            ref.watch(vpnStateProvider).value ??
                multi_vpn.VpnState.disconnected;
        final isConnected =
            currentServer?.id == server.id &&
                vpnState == multi_vpn.VpnState.connected;
        final isFavorite = favoriteServers.contains(server.id);

        return _buildServerCard(
          server,
          isConnected,
          isFavorite,
          isPremium,
          isDarkMode,
        );
      },
    );
  }

  Widget _buildSmartConnectCard(bool isDarkMode, VpnServer? currentServer) {
    final themeColor = ref.watch(themeColorProvider);
    final isSelected = currentServer == null;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () {
            ref.read(currentServerProvider.notifier).setServer(null);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: isSelected
                    ? themeColor.withValues(alpha: 0.4)
                    : (isDarkMode
                    ? const Color(0xFF334155)
                    : const Color(0xFFE5E7EB)),
                width: isSelected ? 1.5 : 1.0,
              ),
              boxShadow: isSelected
                  ? [
                BoxShadow(
                  color: themeColor.withValues(alpha: 0.12),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ]
                  : null,
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: themeColor.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.bolt, color: themeColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto Connect',
                        style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Automatically connect to the fastest server',
                        style: TextStyle(
                          color: isDarkMode
                              ? const Color(0xFF94A3B8)
                              : Colors.grey[600],
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_circle, color: themeColor, size: 22)
                else
                  Icon(
                    Icons.chevron_right,
                    color: isDarkMode
                        ? const Color(0xFF64748B)
                        : Colors.grey[400],
                    size: 22,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildServerCard(
      VpnServer server,
      bool isConnected,
      bool isFavorite,
      bool isPremium,
      bool isDarkMode,
      ) {
    final themeColor = ref.watch(themeColorProvider);
    // Check if this server is temporarily unlocked via ad watch
    final unlocks = ref.watch(premiumServerUnlocksProvider);
    final isAdUnlocked =
        server.premium &&
            (unlocks[server.id.toString()]?.isStillUnlocked ?? false);
    final canConnect = !server.premium || isPremium || isAdUnlocked;
    // Measured TCP-connect latency (null = not yet measured or unreachable)
    final latencies = ref.watch(serverLatencyProvider);
    final latencyMs = latencies[server.id];

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF22C55E).withValues(alpha: 0.6)
              : (isDarkMode
              ? const Color(0xFF334155)
              : const Color(0xFFE5E7EB)),
          width: isConnected ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: isConnected
                ? const Color(0xFF22C55E).withValues(alpha: 0.1)
                : Colors.black.withValues(alpha: isDarkMode ? 0.15 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: canConnect
              ? () => _connectToServer(server)
              : (server.premium && !isPremium)
              ? () => _showPremiumUnlockDialog(server)
              : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                // Flag
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF0F172A)
                        : const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    child: Text(
                      server.flag,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Server Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              server.name,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: isDarkMode
                                    ? Colors.white
                                    : const Color(0xFF111827),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Protocol badge
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color:
                              (server.isOneConnect
                                  ? const Color(0xFF8B5CF6)
                                  : server.isV2Ray
                                  ? const Color(0xFF9333EA)
                                  : server.isOpenConnect
                                  ? const Color(0xFFF97316)
                                  : server.supportsWireGuard
                                  ? const Color(0xFF10B981)
                                  : const Color(0xFF3B82F6))
                                  .withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),

                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            server.country,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDarkMode
                                  ? const Color(0xFF94A3B8)
                                  : const Color(0xFF6B7280),
                            ),
                          ),
                          if (latencyMs != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 5,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: _getLatencyColor(
                                  latencyMs,
                                ).withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${latencyMs}ms',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: _getLatencyColor(latencyMs),
                                ),
                              ),
                            ),
                          ],
                          if (server.premium) ...[
                            const SizedBox(width: 6),
                            Consumer(
                              builder: (context, ref, child) {
                                final unlockedServers = ref.watch(
                                  premiumServerUnlocksProvider,
                                );
                                final serverId = server.id.toString();
                                final unlock = unlockedServers[serverId];
                                final remainingMinutes =
                                unlock != null && unlock.isStillUnlocked
                                    ? (unlock.remainingTime.inSeconds / 60)
                                    .ceil()
                                    : 0;
                                return Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1,
                                  ),
                                  decoration: BoxDecoration(
                                    color: remainingMinutes > 0
                                        ? const Color(
                                      0xFF22C55E,
                                    ).withValues(alpha: 0.12)
                                        : const Color(
                                      0xFFFFD700,
                                    ).withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    remainingMinutes > 0
                                        ? '${remainingMinutes}m'
                                        : 'PRO',
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                      color: remainingMinutes > 0
                                          ? const Color(0xFF16A34A)
                                          : const Color(0xFFD97706),
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      // Load bar
                      Row(
                        children: [
                          Expanded(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: LinearProgressIndicator(
                                value: server.load.clamp(0.0, 1.0),
                                minHeight: 4,
                                backgroundColor: isDarkMode
                                    ? const Color(0xFF334155)
                                    : const Color(0xFFE5E7EB),
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  _getLoadColor(server.load),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${(server.load.clamp(0.0, 1.0) * 100).toInt()}%',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: isDarkMode
                                  ? const Color(0xFF64748B)
                                  : const Color(0xFF9CA3AF),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 10),

                // Right side actions
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (isConnected)
                      const Icon(
                        Icons.check_circle_rounded,
                        color: Color(0xFF22C55E),
                        size: 22,
                      )
                    else if (!canConnect)
                      const Icon(
                        Icons.lock_rounded,
                        color: Color(0xFFD97706),
                        size: 20,
                      )
                    else
                      Icon(
                        Icons.radio_button_unchecked,
                        size: 20,
                        color: isDarkMode
                            ? const Color(0xFF475569)
                            : const Color(0xFFD1D5DB),
                      ),

                    GestureDetector(
                      onTap: () => _toggleFavorite(server.id),
                      child: Icon(
                        isFavorite
                            ? Icons.star_rounded
                            : Icons.star_outline_rounded,
                        color: isFavorite
                            ? const Color(0xFFF59E0B)
                            : (isDarkMode
                            ? const Color(0xFF475569)
                            : const Color(0xFFD1D5DB)),
                        size: 22,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNativeAdCard(bool isDarkMode) {
    return _NativeAdCard(isDarkMode: isDarkMode);
  }

  Color _getLatencyColor(int latency) {
    if (latency <= 50) return Colors.green;
    if (latency <= 100) return Colors.orange;
    return Colors.red;
  }

  Color _getLoadColor(double load) {
    if (load <= 0.5) return Colors.green;
    if (load <= 0.8) return Colors.orange;
    return Colors.red;
  }

  void _connectToServer(VpnServer server) async {
    try {
      // ✅ CHECK ACCESS RIGHTS FIRST
      final timerState = ref.read(freeConnectionTimerProvider);
      final isPremium = ref.read(premiumStatusProvider);

      // Check if this is a premium server and user is not subscribed
      if (server.premium && !isPremium) {
        // Check if server is temporarily unlocked via ad
        final unlockService = PremiumServerUnlockService();
        final unlockInfo = unlockService.getUnlockInfo(server.id);
        if (unlockInfo == null || !unlockInfo.isStillUnlocked) {
          debugPrint(
            '🔒 Premium server selected - user not subscribed and not ad-unlocked',
          );
          _showPremiumUnlockDialog(server);
          return;
        }
        debugPrint(
          '✅ Premium server is ad-unlocked (${unlockInfo.remainingTime.inMinutes}m remaining), connecting...',
        );
      }

      // Check if free time has expired for free servers
      if (!isPremium && timerState.timerExpired && !server.premium) {
        debugPrint(
          '⏰ Free server selected - timer expired, need ad or subscription',
        );

        // Get ad config to check if ads are enabled
        final adConfig = await AdMobService.instance.getAdConfig(server.id);
        final adsEnabled = adConfig?.enableAds ?? true;

        if (!adsEnabled) {
          // Ads disabled - show subscription-only popup
          debugPrint('🔴 Ads disabled, showing subscription-only popup');
          if (mounted) {
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: EdgeInsets.fromLTRB(
                  24,
                  12,
                  24,
                  MediaQuery.of(ctx).viewInsets.bottom + 32,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: Colors.grey[300],
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFEF2F2),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.timer_off_rounded,
                        color: Color(0xFFEF4444),
                        size: 36,
                      ),
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'Free Time Expired',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF111827),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your free connection time has expired.\nUpgrade to Premium to continue.',
                      style: TextStyle(fontSize: 14, color: Color(0xFF6B7280)),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 28),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        icon: const Icon(
                          Icons.star_rounded,
                          color: Colors.white,
                        ),
                        label: const Text(
                          'Upgrade to Premium',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF2563EB),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          Navigator.of(ctx).pop();
                          if (mounted)
                            Navigator.of(context).pushNamed('/premium');
                        },
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton(
                        onPressed: () => Navigator.of(ctx).pop(),
                        child: const Text(
                          'Cancel',
                          style: TextStyle(
                            color: Color(0xFF6B7280),
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }
          return; // Don't proceed with connection
        }

        // Ads are enabled - show reward video popup

        bool shouldProceed = false;
        int watchedAdsInThisPopup = 0;
        final adConfigForRewards = await AdMobService.instance.getAdConfig(
          server.id,
        );
        final defaultDurations = [300, 600, 1200]; // 5, 10, 20 minutes

        // Show reward popup and wait for user action
        if (mounted) {
          await showModalBottomSheet(
            context: context,
            isScrollControlled: true,
            isDismissible: false,
            enableDrag: false,
            backgroundColor: Colors.transparent,
            builder: (dialogContext) => Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: UnifiedAdsPopupSimple(
                adCount: 1,
                title: 'Extend Free Time',
                subtitle: 'Watch videos to continue',
                showSubscribeButton: true,
                onAction: (action) async {
                  if (action == 'ad_watched') {
                    watchedAdsInThisPopup++;
                    final rewardIndex = watchedAdsInThisPopup - 1;
                    final rewardDurationSeconds =
                    adConfigForRewards?.ads.isNotEmpty == true &&
                        rewardIndex >= 0 &&
                        rewardIndex < adConfigForRewards!.ads.length
                        ? adConfigForRewards.ads[rewardIndex].durationSeconds
                        : defaultDurations[rewardIndex.clamp(0, 2)];

                    ref
                        .read(freeConnectionTimerProvider.notifier)
                        .addTime(rewardDurationSeconds);

                    // Keep daily reward state in sync for watch limits/UI.
                    final videoIndex = rewardIndex.clamp(0, 2);
                    await ref
                        .read(rewardVideoProvider.notifier)
                        .markVideoWatched(videoIndex);

                    debugPrint(
                      '✅ Added $rewardDurationSeconds seconds for watched ad #$watchedAdsInThisPopup',
                    );
                  } else if (action == 'all_ads_watched') {
                    shouldProceed = true;
                    if (mounted && Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext);
                    }
                  } else if (action == 'subscribe_clicked') {
                    if (mounted && Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext);
                    }
                    if (mounted) {
                      Navigator.of(context).pushNamed('/premium');
                    }
                  }
                },
              ),
            ),
          );
        }

        // If user didn't watch video or subscribe, don't proceed with connection
        if (!shouldProceed) {
          return;
        }
      }

      // Check if server is full
      if (server.isFull) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '${server.name} is at full capacity (${server.connectedDevices}/${server.capacity} users). Please select another server.',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Track user action for ad display
      AdMobService.instance.incrementActionCounter();

      // Set the selected server in the provider BEFORE attempting connection
      if (mounted) {
        await ref.read(currentServerProvider.notifier).setServer(server);
      }

      // Show connecting message
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Connecting to ${server.name}...'),
            backgroundColor: Colors.blue,
            duration: const Duration(seconds: 2),
          ),
        );
      }

      // Use VPN service for OpenVPN connections
      final vpnService = ref.read(vpnServiceProvider);
      final success = await vpnService.connectToServer(server);

      if (!success) {
        // Reset server selection on failure
        if (mounted) {
          await ref.read(currentServerProvider.notifier).setServer(null);
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Failed to connect to ${server.name.isNotEmpty ? server.name : server.country}. Please try again.',
              ),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 4),
              action: SnackBarAction(
                label: 'Retry',
                textColor: Colors.white,
                onPressed: () {
                  _connectToServer(server);
                },
              ),
            ),
          );
        }
      }
    } catch (e) {
      // Reset server selection on error
      if (mounted) {
        await ref.read(currentServerProvider.notifier).setServer(null);
      }

      if (mounted) {
        String errorMessage = 'Connection failed';
        if (e.toString().contains('OpenVPN need to be initialized')) {
          errorMessage = 'VPN engine initialization failed. Please try again.';
        } else if (e.toString().contains('permission denied')) {
          errorMessage =
          'VPN permission required. Please grant permission in settings.';
        } else if (e.toString().contains('Premium subscription required')) {
          errorMessage = 'This server requires a premium subscription.';
        } else if (e.toString().contains('timeout')) {
          errorMessage =
          'Connection timeout. Please check your internet connection.';
        } else {
          errorMessage =
          'Failed to connect: ${e.toString().replaceAll('Exception: ', '')}';
        }

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'Retry',
              textColor: Colors.white,
              onPressed: () {
                _connectToServer(server);
              },
            ),
          ),
        );
      }
    }
  }

  // Show popup for premium server unlock with SINGLE ad option
  void _showPremiumUnlockDialog(VpnServer server) async {
    try {
      // Fetch ads popup configuration
      final adsConfig = await AdsPopupConfigService().getAdsPopupConfig();

      debugPrint(
        '📱 PREMIUM UNLOCK - Config loaded: ${adsConfig.enablePremiumUnlock} | Duration: ${adsConfig.premiumUnlockDurationMinutes}min',
      );

      // Check if premium unlock ads popup is enabled
      if (!adsConfig.enablePremiumUnlock) {
        debugPrint('⚠️ Premium unlock ads popup is disabled');
        if (mounted) {
          Navigator.pushNamed(context, '/premium');
        }
        return;
      }

      if (mounted) {
        // Show 3 ADS popup for PREMIUM SERVERS
        debugPrint('🎬🎬🎬 ABOUT TO SHOW DIALOG 🎬🎬🎬');
        debugPrint('   Server: ${server.name} (${server.id})');
        debugPrint('   Mounted: $mounted');

        final result = await showModalBottomSheet<bool>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (context) {
            debugPrint(
              '🎬 BOTTOM SHEET BUILDER CALLED - Creating UnifiedAdsPopupSimple',
            );
            return UnifiedAdsPopupSimple(
              customText: adsConfig.premiumUnlockText,
              adCount: 1,
              showSubscribeButton: false,
              title: 'Unlock Premium Server',
              onAction: (action) async {
                try {
                  debugPrint('🔔 onAction called with action: $action');

                  // Called after EACH individual ad is watched
                  if (action == 'ad_watched') {
                    debugPrint(
                      '✅ AD WATCHED - granting unlock for ${adsConfig.premiumUnlockDurationMinutes} minutes',
                    );
                    final unlockService = PremiumServerUnlockService();
                    // Get existing unlock to extend if already unlocked
                    final existing = unlockService.getUnlockInfo(server.id);
                    final extraMinutes = adsConfig.premiumUnlockDurationMinutes;
                    // If already unlocked, extend from current expiry; otherwise from now
                    final baseTime =
                    (existing != null && existing.isStillUnlocked)
                        ? existing.unlockedUntil
                        : DateTime.now();
                    final newExpiry = baseTime.add(
                      Duration(minutes: extraMinutes),
                    );
                    // Store extended unlock
                    await unlockService.unlockPremiumServer(
                      server: server,
                      durationMinutes:
                      newExpiry.difference(DateTime.now()).inMinutes + 1,
                      unlockedBy: 'ad',
                    );
                    // Notify UI immediately so badge updates
                    await ref
                        .read(premiumServerUnlocksProvider.notifier)
                        .notifyUnlock();
                    debugPrint(
                      '✅ Per-ad unlock stored. Remaining: ${unlockService.getUnlockInfo(server.id)?.remainingTime.inMinutes}m',
                    );
                  } else if (action == 'all_ads_watched') {
                    debugPrint('═════════════════════════════════════════');
                    debugPrint('✅ ALL ADS WATCHED - FINAL UNLOCK COMPLETE');
                    debugPrint('✅ Server: ${server.name} (ID: ${server.id})');
                    debugPrint('═════════════════════════════════════════');

                    // Per-ad unlocks already applied - just get final remaining time
                    final unlockService = PremiumServerUnlockService();
                    final finalUnlock = unlockService.getUnlockInfo(server.id);
                    final totalMinutes =
                        finalUnlock?.remainingTime.inMinutes ?? 0;

                    // Notify UI one more time to be sure
                    await ref
                        .read(premiumServerUnlocksProvider.notifier)
                        .notifyUnlock();

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            '✅ ${server.name} unlocked for ${totalMinutes}m!',
                          ),
                          backgroundColor: Colors.green,
                          duration: const Duration(seconds: 3),
                        ),
                      );
                    }
                  } else if (action == 'subscribe_clicked') {
                    // User clicked "Go Premium" button - handle navigation
                    debugPrint('═════════════════════════════════════════');
                    debugPrint(
                      '🛒 User wants to subscribe - navigating to premium',
                    );
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
                } catch (e) {
                  debugPrint('❌ CRITICAL Error in onAction: $e');
                  debugPrint('   Stack: $e');
                }
              },
              onClosed: () {
                debugPrint('⏰ Premium unlock popup closed');
              },
            );
          },
        );

        debugPrint(
          '📊 Popup result: $result (true=watched, false/null=dismissed)',
        );

        // After popup closes, check if user watched ad and connect
        if (result == true) {
          debugPrint('═════════════════════════════════════════');
          debugPrint('✅ AD WAS WATCHED - UNLOCKING AND CONNECTING');
          debugPrint('═════════════════════════════════════════');

          // Get the latest unlock info to display
          final unlockService = PremiumServerUnlockService();
          final unlockInfo = unlockService.getUnlockInfo(server.id);
          if (unlockInfo != null && unlockInfo.isStillUnlocked) {
            debugPrint(
              '✅ Unlock confirmed: Valid until ${unlockInfo.unlockedUntil.toLocal()}',
            );
            debugPrint(
              '   Remaining: ${(unlockInfo.remainingTime.inMinutes)}m',
            );
          } else {
            debugPrint('⚠️ Unlock not found or expired after popup closed');
          }

          // Force UI rebuild to show updated badge
          if (mounted) {
            setState(() {
              debugPrint(
                '🔄 Refreshing servers UI - badge will show unlock time',
              );
            });
          }

          if (mounted) {
            await Future.delayed(const Duration(milliseconds: 300));
            _connectToServer(server);
          }
        } else {
          debugPrint('❌ Popup closed without watching ad (Result: $result)');
        }
      }
    } catch (e) {
      debugPrint('❌ Error showing premium unlock popup: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _toggleFavorite(String serverId) {
    ref.read(favoriteServersProvider.notifier).toggleFavorite(serverId);
  }

  Widget _buildBenefitItem(String text) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Icon(Icons.check_circle, color: Colors.amber, size: 16),
          const SizedBox(width: 8),
          Text(
            text,
            style: TextStyle(
              fontSize: 14,
              color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
        ],
      ),
    );
  }

  /// Format free connection time in minutes to a readable string
  String _formatFreeTime(int minutes) {
    if (minutes <= 0) return 'Unlimited';

    if (minutes < 60) {
      return '${minutes}min';
    } else {
      final hours = minutes ~/ 60;
      final remainingMinutes = minutes % 60;
      if (remainingMinutes == 0) {
        return '${hours}h';
      } else {
        return '${hours}h ${remainingMinutes}min';
      }
    }
  }

  void _showServerDetailsBottomSheet(VpnServer server) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final latencies = ref.read(serverLatencyProvider);
    final latencyMs = latencies[server.id];
    final latencyText = latencyMs != null ? '${latencyMs} ms' : '-- ms';
    final currentServer = ref.read(currentServerProvider);
    final isConnected = currentServer?.id == server.id;

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
          MediaQuery.of(ctx).viewInsets.bottom + 28,
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
                    color:
                    (server.premium
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF10B981))
                        .withValues(alpha: 0.15),
                  ),
                  child: Text(
                    server.flag,
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
                          fontSize: 17,
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
                if (server.premium)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'PREMIUM',
                      style: TextStyle(
                        fontSize: 10,
                        color: Color(0xFFF59E0B),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                const SizedBox(width: 6),
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
            // Stats row
            Row(
              children: [
                _buildStatChip(Icons.speed, latencyText, isDarkMode),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.analytics_outlined,
                  '${(server.load.clamp(0.0, 1.0) * 100).toInt()}% load',
                  isDarkMode,
                ),
                const SizedBox(width: 8),
                _buildStatChip(
                  Icons.people_outline,
                  '${server.connectedDevices} users',
                  isDarkMode,
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Detail rows

            const SizedBox(height: 16),
            // Connect button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.of(ctx).pop();
                  _connectToServer(server);
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isConnected
                      ? const Color(0xFF10B981)
                      : const Color(0xFF2563EB),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  isConnected ? 'Currently Connected' : 'Connect to Server',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatChip(IconData icon, String text, bool isDarkMode) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isDarkMode ? Colors.grey[800] : Colors.grey[50],
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
          ),
        ),
        child: Column(
          children: [
            Icon(
              icon,
              size: 18,
              color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
            ),
            const SizedBox(height: 4),
            Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.grey[200] : Colors.grey[700],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(
      IconData icon,
      String label,
      String value,
      bool isDarkMode,
      ) {
    return Row(
      children: [
        Icon(
          icon,
          size: 16,
          color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
        ),
        const SizedBox(width: 10),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isDarkMode ? Colors.white : Colors.black87,
          ),
        ),
      ],
    );
  }

  String _getCountryFlagEmoji(String countryCode) {
    if (countryCode.isEmpty || countryCode.length < 2) return '🌐';
    try {
      final code = countryCode.toUpperCase();
      final flag = String.fromCharCodes(
        code.codeUnits.map((c) => 0x1F1E6 + c - 65),
      );
      return flag;
    } catch (_) {
      return '🌐';
    }
  }


  void _showFilterDialog() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    bool tempPremiumOnly = _showPremiumOnly;
    bool tempFreeOnly = _showFreeOnly;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx2, setSheetState) => Container(
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: EdgeInsets.fromLTRB(
            20,
            12,
            20,
            MediaQuery.of(ctx2).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
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
                  Icon(
                    Icons.filter_list,
                    color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  ),
                  const SizedBox(width: 10),
                  Text(
                    AppLocalizations.of(context).filterServers,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx2).pop(),
                    child: Icon(
                      Icons.close,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // Premium filter tile
              _buildFilterTile(
                AppLocalizations.of(context).premiumOnly,
                AppLocalizations.of(context).showOnlyPremiumServers,
                Icons.currency_exchange,
                const Color(0xFFF59E0B),
                tempPremiumOnly,
                isDarkMode,
                    (v) => setSheetState(() {
                  tempPremiumOnly = v!;
                  if (v) tempFreeOnly = false;
                }),
              ),
              const SizedBox(height: 8),
              // Free filter tile
              _buildFilterTile(
                AppLocalizations.of(context).freeServers,
                AppLocalizations.of(context).showOnlyFreeServers,
                Icons.wifi,
                const Color(0xFF10B981),
                tempFreeOnly,
                isDarkMode,
                    (v) => setSheetState(() {
                  tempFreeOnly = v!;
                  if (v) tempPremiumOnly = false;
                }),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  if (tempPremiumOnly || tempFreeOnly)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _showPremiumOnly = false;
                            _showFreeOnly = false;
                          });
                          Navigator.of(ctx2).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(AppLocalizations.of(ctx2).clear),
                      ),
                    ),
                  if (tempPremiumOnly || tempFreeOnly)
                    const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() {
                          _showPremiumOnly = tempPremiumOnly;
                          _showFreeOnly = tempFreeOnly;
                        });
                        Navigator.of(ctx2).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(AppLocalizations.of(ctx2).apply),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterTile(
      String title,
      String subtitle,
      IconData icon,
      Color color,
      bool value,
      bool isDarkMode,
      ValueChanged<bool?> onChanged,
      ) {
    return Container(
      decoration: BoxDecoration(
        color: value
            ? color.withValues(alpha: 0.08)
            : (isDarkMode ? Colors.grey[800] : Colors.grey[50]),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: value
              ? color.withValues(alpha: 0.4)
              : (isDarkMode ? Colors.grey[700]! : Colors.grey[200]!),
        ),
      ),
      child: CheckboxListTile(
        title: Text(
          title,
          style: TextStyle(
            color: isDarkMode ? Colors.white : Colors.black87,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(
            color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
            fontSize: 12,
          ),
        ),
        secondary: Icon(icon, color: color, size: 22),
        value: value,
        activeColor: color,
        checkColor: Colors.white,
        onChanged: onChanged,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  /// Get color for different protocols
  Color _getProtocolColor(String protocol) {
    switch (protocol.toLowerCase()) {
      case 'openvpn':
        return Colors.blue;
      default:
        return Colors.blue;
    }
  }
}

// ─── Self-contained native ad card ────────────────────────────────────────────
class _NativeAdCard extends StatefulWidget {
  final bool isDarkMode;
  const _NativeAdCard({required this.isDarkMode});

  @override
  State<_NativeAdCard> createState() => _NativeAdCardState();
}

class _NativeAdCardState extends State<_NativeAdCard> {
  NativeAd? _ad;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ad = AdMobService.instance.createNativeAd(
      onAdLoaded: (ad) {
        if (mounted) setState(() => _loaded = true);
      },
      onAdFailedToLoad: (ad, error) {
        debugPrint('NativeAdCard failed: $error');
        ad.dispose();
      },
    );
    _ad?.load();
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded || _ad == null) return const SizedBox.shrink();

    return Container(
      height: 320,
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: widget.isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: widget.isDarkMode
            ? null
            : Border.all(color: Colors.grey[300] ?? Colors.grey),
        boxShadow: [
          BoxShadow(
            color: (widget.isDarkMode ? Colors.black : Colors.grey).withValues(
              alpha: 0.1,
            ),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: AdWidget(ad: _ad!),
      ),
    );
  }
}
