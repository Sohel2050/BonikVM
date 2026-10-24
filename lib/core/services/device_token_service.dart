import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'device_identity.dart';

/// Keeps a server-signed, short-lived token that identifies this app install.
///
/// The token is requested from `POST /api/v1/device/register` and sent as the
/// `X-Device-Token` header on every API call (see ApiService). The server can
/// then refuse requests that do not carry a valid token.
class DeviceTokenService {
  DeviceTokenService._();
  static final DeviceTokenService instance = DeviceTokenService._();

  static const String _tokenKey = 'device_token_v1';
  static const String _expiryKey = 'device_token_exp_v1';
  static const Duration _refreshMargin = Duration(days: 2);

  String? _token;
  int _expiryMs = 0;
  bool _loaded = false;
  Future<String?>? _inflight;

  Future<void> _loadFromDisk() async {
    if (_loaded) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      _token = prefs.getString(_tokenKey);
      _expiryMs = prefs.getInt(_expiryKey) ?? 0;
    } catch (_) {}
    _loaded = true;
  }

  bool get _isFresh {
    if (_token == null) return false;
    final limit = DateTime.now().add(_refreshMargin).millisecondsSinceEpoch;
    return _expiryMs > limit;
  }

  /// Returns a usable token, registering the device first when needed.
  /// Never throws; returns null if no token could be obtained.
  Future<String?> token() async {
    await _loadFromDisk();
    if (_isFresh) return _token;

    final fresh = await refresh().timeout(
      const Duration(seconds: 6),
      onTimeout: () => null,
    );
    if (fresh != null) return fresh;

    // Registration failed: fall back to an older token that has not expired.
    if (_token != null && _expiryMs > DateTime.now().millisecondsSinceEpoch) {
      return _token;
    }
    return null;
  }

  void invalidate() {
    _token = null;
    _expiryMs = 0;
  }

  Future<String?> refresh({bool force = false}) {
    final running = _inflight;
    if (running != null) return running;

    final future = _register().whenComplete(() => _inflight = null);
    _inflight = future;
    return future;
  }

  Future<String?> _register() async {
    try {
      final deviceId = await DeviceIdentity.id();

      final dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          sendTimeout: const Duration(seconds: 8),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-API-Token': AppConfig.apiKey,
          },
          validateStatus: (status) => status != null && status < 500,
        ),
      );

      final response = await dio.post(
        '/api/${AppConfig.apiVersion}/device/register',
        data: {'device_id': deviceId},
      );

      if (response.statusCode != 200 || response.data is! Map) {
        return null;
      }

      final data = response.data as Map;
      final token = data['token']?.toString();
      final expiresIn = int.tryParse('${data['expires_in']}') ?? 0;
      if (token == null || token.isEmpty || expiresIn <= 0) return null;

      _token = token;
      _expiryMs = DateTime.now()
          .add(Duration(seconds: expiresIn))
          .millisecondsSinceEpoch;

      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_tokenKey, token);
        await prefs.setInt(_expiryKey, _expiryMs);
      } catch (_) {}

      return token;
    } catch (e) {
      if (kDebugMode) debugPrint('[DeviceToken] register failed: $e');
      return null;
    }
  }
}
