import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import '../../../shared/providers/app_providers.dart';
import '../../../shared/providers/theme_provider.dart';
import 'home_small_widgets.dart';

/// Download / upload speed cards (with sparkline graphs) shown on the
/// Home screen while connected — matches the reference "VPN Master"
/// design's two side-by-side stat cards.
class ConnectionStatsSection extends ConsumerWidget {
  const ConnectionStatsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final speedData = ref.watch(networkSpeedProvider);
    final themeColor = ref.watch(themeColorProvider);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: SpeedStatCard(
            label: 'Download',
            value: speedData.when(
              data: (data) => data.formattedDownloadSpeed,
              loading: () => '--.-',
              error: (_, __) => '0.0',
            ),
            unit: 'Mbps',
            color: themeColor,
            isDownload: true,
            isDarkMode: isDarkMode,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: SpeedStatCard(
            label: 'Upload',
            value: speedData.when(
              data: (data) => data.formattedUploadSpeed,
              loading: () => '--.-',
              error: (_, __) => '0.0',
            ),
            unit: 'Mbps',
            color: const Color(0xFFF59E0B),
            isDownload: false,
            isDarkMode: isDarkMode,
          ),
        ),
      ],
    );
  }
}
