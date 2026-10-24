import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/api_service.dart' show VpnServer;
import '../../shared/widgets/flag_icon.dart';
import 'third_party_servers.dart';

/// Content of the "THIRD PARTY" tab on the servers screen: free public
/// OpenVPN servers from VPN Gate, run by volunteers.
class ThirdPartyServersTab extends ConsumerStatefulWidget {
  final bool isDarkMode;

  /// Id of the server the VPN is connected to right now (null when not connected).
  final String? connectedServerId;
  final void Function(VpnServer server) onConnect;

  const ThirdPartyServersTab({
    super.key,
    required this.isDarkMode,
    required this.connectedServerId,
    required this.onConnect,
  });

  @override
  ConsumerState<ThirdPartyServersTab> createState() =>
      _ThirdPartyServersTabState();
}

class _ThirdPartyServersTabState extends ConsumerState<ThirdPartyServersTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        ref.read(thirdPartyServersProvider.notifier).load();
      }
    });
  }

  Future<void> _refresh() {
    return ref.read(thirdPartyServersProvider.notifier).load(force: true);
  }

  /// Warns the user about volunteer-run servers before connecting.
  Future<void> _confirmAndConnect(VpnServer server) async {
    // Tapping the server we are already connected to: no warning needed.
    if (widget.connectedServerId == server.id) {
      widget.onConnect(server);
      return;
    }

    final dark = widget.isDarkMode;
    final proceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: dark ? const Color(0xFF1E293B) : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          icon: const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFF59E0B),
            size: 40,
          ),
          title: Text(
            'Third-party server',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: dark ? Colors.white : const Color(0xFF111827),
              fontWeight: FontWeight.bold,
              fontSize: 18,
            ),
          ),
          content: Text(
            'This server is run by an independent volunteer (VPN Gate), not '
            'by us.\n\nThe operator may be able to see or log your traffic. '
            'Do not use it for banking, passwords or other sensitive '
            'activity.\n\nSpeed and stability can vary.',
            style: TextStyle(
              color: dark ? const Color(0xFFCBD5E1) : const Color(0xFF4B5563),
              fontSize: 14,
              height: 1.4,
            ),
          ),
          actionsAlignment: MainAxisAlignment.spaceBetween,
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.black,
              ),
              child: const Text('Connect anyway'),
            ),
          ],
        );
      },
    );

    if (proceed == true && mounted) {
      widget.onConnect(server);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(thirdPartyServersProvider);
    final dark = widget.isDarkMode;
    final textColor = dark ? Colors.white : const Color(0xFF111827);
    final mutedColor = dark ? const Color(0xFF94A3B8) : const Color(0xFF6B7280);

    final busy = state.loading || state.probing;
    final servers = state.servers;

    Widget body;
    if (servers.isEmpty && busy) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          const Center(child: CircularProgressIndicator()),
          const SizedBox(height: 16),
          Center(
            child: Text(
              'Checking servers...',
              style: TextStyle(color: mutedColor, fontSize: 14),
            ),
          ),
        ],
      );
    } else if (servers.isEmpty) {
      body = ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 80),
          Icon(Icons.wifi_off, size: 56, color: mutedColor),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Text(
              state.error ?? 'No servers found.',
              textAlign: TextAlign.center,
              style: TextStyle(color: mutedColor, fontSize: 15),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: ElevatedButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ),
        ],
      );
    } else {
      body = ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
        itemCount: servers.length + (state.probing ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= servers.length) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Checking more servers...',
                    style: TextStyle(color: mutedColor, fontSize: 12),
                  ),
                ],
              ),
            );
          }
          final server = servers[index];
          return _ServerCard(
            server: server,
            isConnected: widget.connectedServerId == server.id,
            isDarkMode: dark,
            textColor: textColor,
            mutedColor: mutedColor,
            onTap: () => _confirmAndConnect(server),
          );
        },
      );
    }

    return Column(
      children: [
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: const Color(0xFFF59E0B).withValues(alpha: 0.4),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.warning_amber_rounded,
                color: Color(0xFFF59E0B),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'These servers are run by independent volunteers (VPN Gate), '
                  'not by us. They may log or inspect your traffic. Do not use '
                  'them for banking or passwords. Speed and availability vary.',
                  style: TextStyle(
                    color: dark ? const Color(0xFFFCD34D) : const Color(0xFF92400E),
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: RefreshIndicator(onRefresh: _refresh, child: body),
        ),
      ],
    );
  }
}

class _ServerCard extends StatelessWidget {
  final VpnServer server;
  final bool isConnected;
  final bool isDarkMode;
  final Color textColor;
  final Color mutedColor;
  final VoidCallback onTap;

  const _ServerCard({
    required this.server,
    required this.isConnected,
    required this.isDarkMode,
    required this.textColor,
    required this.mutedColor,
    required this.onTap,
  });

  String get _speedText {
    final bps = server.providerPayload?['speedBps'];
    final value = bps is num ? bps.toDouble() : 0.0;
    if (value <= 0) return '';
    final mbps = value / 1000000.0;
    return '${mbps.toStringAsFixed(mbps >= 100 ? 0 : 1)} Mbps';
  }

  @override
  Widget build(BuildContext context) {
    final speed = _speedText;
    final details = <String>[
      if (speed.isNotEmpty) speed,
      if (server.latency > 0) '${server.latency} ms',
      server.protocol,
    ].join('  •  ');

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isConnected
              ? const Color(0xFF10B981).withValues(alpha: 0.8)
              : (isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB)),
          width: isConnected ? 1.8 : 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isDarkMode
                          ? const Color(0xFF0F172A)
                          : const Color(0xFFF3F4F6),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: server.countryCode.trim().length == 2
                          ? FlagIcon(countryCode: server.countryCode, size: 28)
                          : Text(server.flag, style: const TextStyle(fontSize: 24)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          server.country.isNotEmpty ? server.country : server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor,
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          server.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: mutedColor, fontSize: 12),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          details,
                          style: TextStyle(color: mutedColor, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (isConnected)
                    const Icon(
                      Icons.check_circle,
                      color: Color(0xFF10B981),
                      size: 22,
                    )
                  else
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: mutedColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Third Party',
                        style: TextStyle(color: mutedColor, fontSize: 10),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
