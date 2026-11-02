import 'dart:async';
import 'dart:math' as math;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/api/api_service.dart';

// IP Address Model
class IpAddressInfo {
  final String ip;
  final String? country;
  final String? countryCode;
  final String? city;
  final String? isp;
  final String? timezone;

  IpAddressInfo({
    required this.ip,
    this.country,
    this.countryCode,
    this.city,
    this.isp,
    this.timezone,
  });

  factory IpAddressInfo.fromJson(Map<String, dynamic> json) {
    return IpAddressInfo(
      ip: json['ip'] ?? json['query'] ?? 'Unknown',
      country: json['country'] ?? json['country_name'],
      countryCode: json['countryCode'] ?? json['country_code'],
      city: json['city'],
      isp: json['isp'] ?? json['org'] ?? json['as'],
      timezone: json['timezone'],
    );
  }
}

// IP Address Provider
//
// Never gives up for good: if every service fails (no internet yet, VPN interface
// still settling, a blocked service), it tries again by itself after a growing
// pause (6 s, 12 s, 24 s ... max 60 s) and the screen fills in as soon as one
// attempt works. The pause resets after a success.
int _ipFailStreak = 0;

/// Called by the manual Reload button so a tap starts a fresh attempt at once.
void resetIpRetryBackoff() => _ipFailStreak = 0;

final ipAddressProvider = FutureProvider<IpAddressInfo>((ref) async {
  final apiService = ApiService.instance;
  Timer? retryTimer;
  ref.onDispose(() => retryTimer?.cancel());

  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      final response = await apiService.getPublicIp();
      _ipFailStreak = 0;
      return IpAddressInfo.fromJson(response);
    } catch (_) {
      if (attempt == 0) await Future.delayed(const Duration(seconds: 1));
    }
  }

  final shift = _ipFailStreak > 4 ? 4 : _ipFailStreak;
  final pause = math.min(6 * (1 << shift), 60);
  _ipFailStreak++;
  retryTimer = Timer(Duration(seconds: pause), ref.invalidateSelf);
  throw Exception('Failed to get IP address');
});

/// Caches the user's real (non-VPN) IP/location the last time it was
/// observed while disconnected. `ipAddressProvider` always reports
/// whatever public IP is visible right now — once connected, that IS the
/// VPN server's exit IP, so widgets that need to show "where the user
/// actually is" (e.g. the source side of the connection map) must read
/// this instead of `ipAddressProvider` directly.
final originalLocationProvider = StateProvider<IpAddressInfo?>((ref) => null);
