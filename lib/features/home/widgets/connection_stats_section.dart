import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import '../../../shared/providers/app_providers.dart';
import 'home_small_widgets.dart';

/// Download / upload speed row shown on the Home screen while connected —
/// a plain two-column layout (arrow + label on top, big value below) split
/// by a thin vertical divider, matching the reference design.
class ConnectionStatsSection extends ConsumerWidget {
  const ConnectionStatsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speedData = ref.watch(networkSpeedProvider);

    final downloadValue = speedData.when(
      data: (data) => data.formattedDownloadSpeed,
      loading: () => '--.-',
      error: (_, __) => '0.0',
    );
    final uploadValue = speedData.when(
      data: (data) => data.formattedUploadSpeed,
      loading: () => '--.-',
      error: (_, __) => '0.0',
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 8),
              child: SpeedStat(
                label: 'Download',
                value: downloadValue,
                unit: '',
                color: const Color(0xFFAEEA1C),
                isDownload: true,
              ),
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: Colors.white.withValues(alpha: 0.12),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 20),
              child: SpeedStat(
                label: 'Upload',
                value: uploadValue,
                unit: '',
                color: const Color(0xFFF59E0B),
                isDownload: false,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
