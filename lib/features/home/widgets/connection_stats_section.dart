import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/theme_provider.dart';
import 'home_small_widgets.dart';

/// Duration / download-speed / upload-speed row shown on the Home screen
/// while connected.
class ConnectionStatsSection extends ConsumerWidget {
  const ConnectionStatsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final vpnService = ref.read(vpnServiceProvider);
    final speedData = ref.watch(networkSpeedProvider);
    final themeColor = ref.watch(themeColorProvider);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isDarkMode ? const Color(0xFF334155) : const Color(0xFFE5E7EB),
        ),
      ),
      child: StreamBuilder<VpnStatus?>(
        stream: vpnService.vpnStatusStream,
        builder: (context, snapshot) {
          final status = snapshot.data;
          final durationString = status?.duration ?? '00:00:00';

          return IntrinsicHeight(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Duration



                // Download speed
                Expanded(
                  child: StatItem(
                    icon: Icons.arrow_downward,
                    value: speedData.when(
                      data: (data) => data.formattedDownloadSpeed,
                      loading: () => '--.-',
                      error: (_, __) => '0.0',
                    ),
                    label: 'Download',
                    color: themeColor,
                  ),
                ),

                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: isDarkMode ? Colors.white12 : Colors.black12,
                  indent: 8,
                  endIndent: 8,
                ),

                // Upload speed
                Expanded(
                  child: StatItem(
                    icon: Icons.arrow_upward,
                    value: speedData.when(
                      data: (data) => data.formattedUploadSpeed,
                      loading: () => '--.-',
                      error: (_, __) => '0.0',
                    ),
                    label: 'Upload',
                    color: const Color(0xFFF59E0B),
                  ),
                ),
              ],
            ),
          ); // IntrinsicHeight
        },
      ),
    );
  }
}
