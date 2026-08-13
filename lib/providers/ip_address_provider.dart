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

  // Always use public IP service for accurate location info
  try {
    final response = await apiService.getPublicIp();
    return IpAddressInfo.fromJson(response);
  } catch (e) {
    print('[IP] Error getting public IP: $e');
    throw Exception('Failed to get IP address');
  }
});
