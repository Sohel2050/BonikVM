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
final ipAddressProvider = FutureProvider<IpAddressInfo>((ref) async {
  final apiService = ApiService.instance;

  int retries = 3;
  while (retries > 0) {
    try {
      final response = await apiService.getPublicIp();
      return IpAddressInfo.fromJson(response);
    } catch (e) {
      retries--;
      if (retries == 0) {
        throw Exception('Failed to get IP address');
      }
      await Future.delayed(const Duration(milliseconds: 1500));
    }
  }
  throw Exception('Failed to get IP address');
});

/// Caches the user's real (non-VPN) IP/location the last time it was
/// observed while disconnected. `ipAddressProvider` always reports
/// whatever public IP is visible right now — once connected, that IS the
/// VPN server's exit IP, so widgets that need to show "where the user
/// actually is" (e.g. the source side of the connection map) must read
/// this instead of `ipAddressProvider` directly.
final originalLocationProvider = StateProvider<IpAddressInfo?>((ref) => null);
