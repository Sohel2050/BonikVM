import 'dart:async';
import 'package:axevpn_flutter/openvpn_flutter.dart';
import 'vpn_service.dart';

class NetworkSpeedData {
  final double downloadSpeedMbps;
  final double uploadSpeedMbps;
  final int downloadBytes;
  final int uploadBytes;
  final DateTime timestamp;

  NetworkSpeedData({
    required this.downloadSpeedMbps,
    required this.uploadSpeedMbps,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.timestamp,
  });

  String get formattedDownloadSpeed {
    if (downloadSpeedMbps < 1) {
      return '↓ ${(downloadSpeedMbps * 1024).toStringAsFixed(1)} KB/s';
    }
    return '↓ ${downloadSpeedMbps.toStringAsFixed(1)} MB/s';
  }

  String get formattedUploadSpeed {
    if (uploadSpeedMbps < 1) {
      return '↑ ${(uploadSpeedMbps * 1024).toStringAsFixed(1)} KB/s';
    }
    return '↑ ${uploadSpeedMbps.toStringAsFixed(1)} MB/s';
  }
}

class NetworkSpeedService {
  static final NetworkSpeedService _instance = NetworkSpeedService._internal();
  factory NetworkSpeedService() => _instance;
  NetworkSpeedService._internal();

  static NetworkSpeedService get instance => _instance;

  StreamSubscription<VpnStatus?>? _vpnStatusSubscription;
  final StreamController<NetworkSpeedData> _speedController =
  StreamController<NetworkSpeedData>.broadcast();

  Stream<NetworkSpeedData> get speedStream => _speedController.stream;

  int _lastDownloadBytes = 0;
  int _lastUploadBytes = 0;
  DateTime? _lastMeasurement;
  bool _isMonitoring = false;
  int _totalDownloadBytes = 0;
  int _totalUploadBytes = 0;

  Future<void> startMonitoring() async {
    if (_isMonitoring) return;
    _isMonitoring = true;
    _lastDownloadBytes = 0;
    _lastUploadBytes = 0;
    _totalDownloadBytes = 0;
    _totalUploadBytes = 0;
    _lastMeasurement = null;
    // Emit an immediate zero-speed event so the StreamProvider exits
    // "loading" state right away instead of showing "--.-".
    _speedController.add(
      NetworkSpeedData(
        downloadSpeedMbps: 0,
        uploadSpeedMbps: 0,
        downloadBytes: 0,
        uploadBytes: 0,
        timestamp: DateTime.now(),
      ),
    );
    _vpnStatusSubscription = VpnService.instance.vpnStatusStream.listen(
      _onVpnStatus,
      onError: (_) {},
    );
  }

  void _onVpnStatus(VpnStatus? status) {
    if (!_isMonitoring || status == null) return;
    final now = DateTime.now();
    final currentDownload = int.tryParse(status.byteIn ?? '0') ?? 0;
    final currentUpload = int.tryParse(status.byteOut ?? '0') ?? 0;
    _totalDownloadBytes = currentDownload;
    _totalUploadBytes = currentUpload;
    if (_lastMeasurement != null) {
      final elapsed = now.difference(_lastMeasurement!).inMilliseconds;
      if (elapsed > 0) {
        final downloadDiff = (currentDownload - _lastDownloadBytes).clamp(
          0,
          1 << 30,
        );
        final uploadDiff = (currentUpload - _lastUploadBytes).clamp(0, 1 << 30);

        // The native plugin doesn't push a new byte-count on every tick of
        // this 1-second local timer — sometimes it's slower. If neither
        // counter moved since the last reading, this isn't a real "0 KB/s"
        // moment, it's a stale/duplicate sample. Skip emitting so the UI
        // keeps showing the last real reading instead of flashing to 0 —
        // but still record this timestamp/byte-count below so the *next*
        // real update measures the correct elapsed window.
        if (!(downloadDiff == 0 && uploadDiff == 0)) {
          final elapsedSeconds = elapsed / 1000.0;
          final downloadMbps = (downloadDiff / (1024 * 1024)) / elapsedSeconds;
          final uploadMbps = (uploadDiff / (1024 * 1024)) / elapsedSeconds;
          _speedController.add(
            NetworkSpeedData(
              downloadSpeedMbps: downloadMbps.clamp(0.0, 1000.0),
              uploadSpeedMbps: uploadMbps.clamp(0.0, 1000.0),
              downloadBytes: currentDownload,
              uploadBytes: currentUpload,
              timestamp: now,
            ),
          );
        }
      }
    }
    _lastDownloadBytes = currentDownload;
    _lastUploadBytes = currentUpload;
    _lastMeasurement = now;
  }

  void stopMonitoring() {
    _isMonitoring = false;
    _vpnStatusSubscription?.cancel();
    _vpnStatusSubscription = null;
    _lastDownloadBytes = 0;
    _lastUploadBytes = 0;
    _totalDownloadBytes = 0;
    _totalUploadBytes = 0;
    _lastMeasurement = null;
  }

  void dispose() {
    stopMonitoring();
    _speedController.close();
  }
}
