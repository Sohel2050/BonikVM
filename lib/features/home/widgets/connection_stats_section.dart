import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import '../../../core/localization/app_localizations.dart';
import '../../../shared/providers/app_providers.dart';
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

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: BoxDecoration(
        color: isDarkMode
            ? const Color(0xFF0A0E1A).withValues(alpha: 0.55)
            : Colors.white.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0xFF10B981).withValues(alpha: 0.18),
          width: 1.2,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            spreadRadius: 2,
          ),
        ],
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
                Expanded(
                  child: StatItem(
                    icon: Icons.timer_outlined,
                    value: durationString,
                    label: AppLocalizations.of(context).duration,
                    color: const Color(0xFF10B981),
                  ),
                ),

                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: isDarkMode ? Colors.white12 : Colors.black12,
                  indent: 8,
                  endIndent: 8,
                ),

                // Download speed
                Expanded(
                  child: StatItem(
                    icon: Icons.download_outlined,
                    value: speedData.when(
                      data: (data) => data.formattedDownloadSpeed,
                      loading: () => '--.-',
                      error: (_, __) => '0.0',
                    ),
                    label: 'Download',
                    color: isDarkMode
                        ? Colors.lightBlue[300] ?? Colors.lightBlue
                        : Colors.blueAccent,
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
                    icon: Icons.upload_outlined,
                    value: speedData.when(
                      data: (data) => data.formattedUploadSpeed,
                      loading: () => '--.-',
                      error: (_, __) => '0.0',
                    ),
                    label: 'Upload',
                    color: isDarkMode
                        ? Colors.lightGreen[300] ?? Colors.lightGreen
                        : Colors.greenAccent,
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
