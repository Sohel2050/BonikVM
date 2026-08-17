import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/api_service.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/widgets/flag_icon.dart';
import '../utils/country_emoji.dart';

/// The "connected server" card shown on the Home screen while a VPN
/// connection is active — flag, name, protocol/latency chips and a
/// "Connected" badge. Tapping it opens the server details bottom sheet.
class ConnectedServerCard extends ConsumerWidget {
  const ConnectedServerCard({
    super.key,
    required this.currentServer,
    required this.onTap,
  });

  final VpnServer currentServer;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final latencies = ref.watch(serverLatencyProvider);
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: const Color(0xFF22C55E).withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF22C55E).withValues(alpha: 0.08),
              blurRadius: 12,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Row(
          children: [
            // Flag
            currentServer.countryCode.trim().length == 2
                ? FlagIcon(countryCode: currentServer.countryCode, size: 28)
                : Text(
                    countryEmoji(currentServer.countryCode),
                    style: const TextStyle(fontSize: 28),
                  ),
            const SizedBox(width: 12),
            // Server name, city, protocol
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    currentServer.name,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isDarkMode
                          ? Colors.white
                          : const Color(0xFF111827),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF2563EB).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          currentServer.vpnProtocolType.toUpperCase(),
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF2563EB),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (latencies[currentServer.id] != null) ...[
                        const SizedBox(width: 6),
                        Text(
                          '${latencies[currentServer.id]} ms',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF22C55E),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            // Connected badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFF22C55E).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFF22C55E).withValues(alpha: 0.4),
                  width: 1,
                ),
              ),
              child: Text(
                AppLocalizations.of(context).connected,
                style: const TextStyle(
                  fontSize: 12,
                  color: Color(0xFF16A34A),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "pick a server" card shown on the Home screen while disconnected —
/// either the currently-selected server or a "Smart Location" placeholder,
/// with a "Change" button that opens server selection.
class SelectionLocationCard extends StatelessWidget {
  const SelectionLocationCard({
    super.key,
    required this.currentServer,
    required this.isDarkMode,
    required this.themeColor,
    required this.onChangePressed,
  });

  final VpnServer? currentServer;
  final bool isDarkMode;
  final Color themeColor;
  final VoidCallback onChangePressed;

  @override
  Widget build(BuildContext context) {
    final countryCode = currentServer?.countryCode ?? '';
    final name = currentServer != null ? currentServer!.name : 'Smart Location';
    final sub = currentServer != null
        ? currentServer!.country
        : 'Select the fastest server automatically';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDarkMode ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Flag/Icon
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isDarkMode ? const Color(0xFF0F172A) : const Color(0xFFF3F4F6),
              borderRadius: BorderRadius.circular(12),
            ),
            child: countryCode.trim().length == 2
                ? FlagIcon(countryCode: countryCode, size: 24)
                : const Text('🌍', style: TextStyle(fontSize: 24)),
          ),
          const SizedBox(width: 14),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: isDarkMode ? Colors.white : const Color(0xFF111827),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  style: TextStyle(
                    fontSize: 12,
                    color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Select button
          ElevatedButton(
            onPressed: onChangePressed,
            style: ElevatedButton.styleFrom(
              backgroundColor: themeColor.withValues(alpha: 0.12),
              foregroundColor: themeColor,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Change',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                SizedBox(width: 4),
                Icon(Icons.arrow_forward_ios, size: 10),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
