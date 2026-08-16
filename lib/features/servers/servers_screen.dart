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
import '../../shared/widgets/flag_icon.dart';
import '../../widgets/unified_ads_popup_simple.dart';

class ServersScreen extends ConsumerStatefulWidget {
  const ServersScreen({super.key});

  @override
  ConsumerState<ServersScreen> createState() => _ServersScreenState();
}

// Global key to access the servers screen state from main shell
final GlobalKey<_ServersScreenState> serversScreenKey =
    GlobalKey<_ServersScreenState>();

class _ServersScreenState extends ConsumerState<ServersScreen>
    with TickerProviderStateMixin {
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

  @override
  void initState() {
    super.initState();
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
    _bannerAd?.load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    for (final sc in _scrollControllers) {
      sc.dispose();
    }
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
  void triggerSearchDialog() {
    _showSearchDialog();
  }

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
    final themeColor = ref.watch(themeColorProvider);

    // Trigger TCP-connect latency measurement when server list loads/refreshes
    ref.listen<AsyncValue<List<VpnServer>>>(serversProvider, (_, next) {
      next.whenData((servers) {
        ref.read(serverLatencyProvider.notifier).measureLatencies(servers);
      });
    });

    // Listen to VPN state changes to start timer for free users
    ref.listen<AsyncValue<multi_vpn.VpnState>>(vpnStateProvider, (
      previous,
      next,
    ) {
      next.whenData((state) {
        if (state == multi_vpn.VpnState.disconnected) {
          // Only reset the free timer if it was NOT an expiry-triggered disconnect.
          // Preserving timerExpired=true prevents free users from reconnecting
          // without watching an ad.
          final timerStateOnDisc = ref.read(freeConnectionTimerProvider);
          if (!timerStateOnDisc.timerExpired) {
            ref.read(freeConnectionTimerProvider.notifier).stopTimer();
          }
        } else if (state == multi_vpn.VpnState.connected) {
          // Start free connection timer when connected (only for free users on free servers)
          if (!isPremium && currentServer != null) {
            // Do NOT start free timer for ad-unlocked premium servers —
            // those are tracked by PremiumServerUnlockService, not the free timer
            final unlock = currentServer.premium
                ? PremiumServerUnlockService().getUnlockInfo(currentServer.id)
                : null;
            final isAdUnlocked = unlock?.isStillUnlocked ?? false;
            if (isAdUnlocked) {
              // Ad-unlocked premium server — start countdown for exactly
              // the remaining unlock duration (from admin setting)
              ref
                  .read(freeConnectionTimerProvider.notifier)
                  .startFromSeconds(currentServer, unlock!.remainingSeconds);
            } else {
              ref
                  .read(freeConnectionTimerProvider.notifier)
                  .startTimer(currentServer, isPremium);
            }
          }
        }
      });
    });

    return Container(
      color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF8F9FA),
      child: Column(
        children: [
          // Top Banner Ad
          if (!isPremium && _isBannerAdLoaded && _bannerAd != null)
            Container(
              height: 60,
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: isDarkMode ? Colors.grey[800] : Colors.grey[100],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: AdWidget(ad: _bannerAd!),
              ),
            ),
          // Main Content
          Expanded(
            child: Column(
              children: [
                // Tabs
                Container(
                  margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: BoxDecoration(
                    color: isDarkMode
                        ? const Color(0xFF1E293B)
                        : Colors.black.withOpacity(0.05),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TabBar(
                    controller: _tabController,
                    indicator: BoxDecoration(
                      color: themeColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: themeColor.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    indicatorSize: TabBarIndicatorSize.tab,
                    labelColor: Colors.white,
                    unselectedLabelColor: isDarkMode
                        ? const Color(0xFF94A3B8)
                        : Colors.black54,
                    labelStyle: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                    unselectedLabelStyle: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    tabs: [
                      Tab(
                        icon: const Icon(Icons.wifi, size: 14),
                        text: "FREE SERVER",
                      ),
                      Tab(
                        icon: const Icon(Icons.currency_exchange, size: 14),
                        text: "VIP SERVER / ADS",
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

    return ListView.builder(
      key: ValueKey(
        'servers_list_${tabIndex}_${filteredServers.length}_$isPremium',
      ),
      controller: _scrollControllers[tabIndex],
      padding: const EdgeInsets.all(16),
      itemCount: isPremium
          ? filteredServers.length
          : filteredServers.length + ((filteredServers.length + 3) ~/ 4),
      itemBuilder: (context, index) {
        // Safety check for index bounds
        if (index < 0) return const SizedBox.shrink();

        // Show native ad every 4th item for non-premium users
        if (!isPremium && (index + 1) % 4 == 0) {
          return _buildNativeAdCard(isDarkMode);
        }

        // Calculate actual server index
        int serverIndex = isPremium ? index : index - ((index + 1) ~/ 4);

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

    final activeColor = isConnected
        ? const Color(0xFF10B981)
        : (isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB));

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF10B981).withOpacity(0.8)
              : activeColor,
          width: isConnected ? 1.8 : 1.0,
        ),
        boxShadow: [
          BoxShadow(
            color: isConnected
                ? const Color(0xFF10B981).withOpacity(0.08)
                : Colors.black.withOpacity(isDarkMode ? 0.12 : 0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: canConnect
                ? () => _connectToServer(server)
                : (server.premium && !isPremium)
                ? () => _showPremiumUnlockDialog(server)
                : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  // Flag Container
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: isDarkMode
                            ? Colors.white.withOpacity(0.05)
                            : Colors.black.withOpacity(0.03),
                      ),
                    ),
                    child: Center(
                      child: server.countryCode.trim().length == 2
                          ? FlagIcon(countryCode: server.countryCode, size: 30)
                          : Text(
                              server.flag,
                              style: const TextStyle(fontSize: 26),
                            ),
                    ),
                  ),
                  const SizedBox(width: 14),

                  // Server Info details
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
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: isDarkMode
                                      ? Colors.white
                                      : const Color(0xFF111827),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            // Protocol Badge

                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                server.country,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: isDarkMode
                                      ? const Color(0xFF94A3B8)
                                      : const Color(0xFF6B7280),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (latencyMs != null) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: _getLatencyColor(
                                    latencyMs,
                                  ).withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.signal_cellular_alt_rounded,
                                      size: 11,
                                      color: _getLatencyColor(latencyMs),
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      '${latencyMs}ms',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.bold,
                                        color: _getLatencyColor(latencyMs),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (server.premium) ...[
                              const SizedBox(width: 8),
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
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: remainingMinutes > 0
                                          ? const Color(
                                              0xFF10B981,
                                            ).withOpacity(0.12)
                                          : const Color(
                                              0xFFF59E0B,
                                            ).withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(
                                      remainingMinutes > 0
                                          ? '${remainingMinutes}m'
                                          : 'VIP',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w800,
                                        color: remainingMinutes > 0
                                            ? const Color(0xFF10B981)
                                            : const Color(0xFFD97706),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Load Capacity Bar
                        Row(
                          children: [
                            Expanded(
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: server.load.clamp(0.0, 1.0),
                                  minHeight: 5,
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
                              '${(server.load.clamp(0.0, 1.0) * 100).toInt()}% load',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
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

                  const SizedBox(width: 12),

                  // Actions & Favorite Status (space-saving Column layout)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
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
                                        : const Color(0xFF9CA3AF)),
                              size: 20,
                            ),
                          ),
                          const SizedBox(width: 8),
                          if (isConnected)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF10B981),
                              size: 20,
                            )
                          else if (!canConnect)
                            const Icon(
                              Icons.video_collection,
                              color: Color(0xFFD97706),
                              size: 18,
                            )
                          else
                            Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 12,
                              color: isDarkMode
                                  ? const Color(0xFF475569)
                                  : const Color(0xFF9CA3AF),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _showServerDetailsBottomSheet(server),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: isDarkMode
                                ? const Color(0xFF0F172A)
                                : const Color(0xFFF3F4F6),
                            borderRadius: BorderRadius.circular(6),
                          ),

                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
                adCount: 3,
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
              title: 'WATCH ADS TO ACCESS',
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
          MediaQuery.of(ctx).viewInsets.bottom +
              MediaQuery.of(ctx).padding.bottom +
              20,
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
                  child: server.countryCode.trim().length == 2
                      ? FlagIcon(countryCode: server.countryCode, size: 30)
                      : Text(server.flag, style: const TextStyle(fontSize: 26)),
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
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[800] : Colors.grey[50],
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isDarkMode ? Colors.grey[700]! : Colors.grey[200]!,
                ),
              ),
              child: Column(
                children: [
                  _buildInfoRow(
                    Icons.computer,
                    'IP Address',
                    '${server.ip}:${server.port}',
                    isDarkMode,
                  ),
                  const Divider(height: 16),
                  _buildInfoRow(
                    Icons.security,
                    'Protocol',
                    server.protocol.toUpperCase(),
                    isDarkMode,
                  ),
                  if (!server.premium) ...[
                    const Divider(height: 16),
                    _buildInfoRow(
                      Icons.access_time,
                      'Free Limit',
                      server.freeConnectDuration > 0
                          ? '${server.freeConnectDuration} min'
                          : 'Unlimited',
                      isDarkMode,
                    ),
                  ],
                ],
              ),
            ),
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

  void _showSearchDialog() {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    _searchController.text = _searchQuery;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
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
                    Icons.search,
                    color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                  ),
                  const SizedBox(width: 10),
                  Text(
                    AppLocalizations.of(context).searchServers,
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                      color: isDarkMode ? Colors.white : Colors.black87,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.of(ctx).pop(),
                    child: Icon(
                      Icons.close,
                      color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  hintText: 'Enter server name or country...',
                  hintStyle: TextStyle(
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDarkMode
                          ? const Color(0xFF374151)
                          : Colors.grey[300]!,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(
                      color: isDarkMode
                          ? const Color(0xFF374151)
                          : Colors.grey[300]!,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(
                      color: Color(0xFF3B82F6),
                      width: 2,
                    ),
                  ),
                  filled: true,
                  fillColor: isDarkMode
                      ? const Color(0xFF374151)
                      : Colors.grey[50],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  prefixIcon: Icon(
                    Icons.search,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[500],
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            Icons.clear,
                            color: isDarkMode
                                ? Colors.grey[400]
                                : Colors.grey[500],
                          ),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                ),
                style: TextStyle(
                  color: isDarkMode ? Colors.white : Colors.black87,
                  fontSize: 15,
                ),
                controller: _searchController,
                onChanged: (v) => setState(() => _searchQuery = v),
                onSubmitted: (v) {
                  setState(() => _searchQuery = v);
                  Navigator.of(ctx).pop();
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if (_searchController.text.isNotEmpty)
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setState(() {
                            _searchQuery = '';
                            _searchController.clear();
                          });
                          Navigator.of(ctx).pop();
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 13),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(AppLocalizations.of(ctx).clear),
                      ),
                    ),
                  if (_searchController.text.isNotEmpty)
                    const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        setState(() => _searchQuery = _searchController.text);
                        Navigator.of(ctx).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF3B82F6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 13),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(AppLocalizations.of(ctx).searchServers),
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
                Icons.workspace_premium,
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
                Icons.lock_open,
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Material(
          type: MaterialType.transparency,
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
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
