import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../core/config/app_config.dart';

/// Legacy: previously fetched the Windows "Desktop app" Google OAuth
/// client ID from the admin panel for the now-removed Windows desktop
/// build. No longer called from app startup; kept only so
/// AppConfig.setRemoteGoogleDesktopClientId continues to compile.
class GoogleLoginConfigService {
  static final GoogleLoginConfigService _instance =
      GoogleLoginConfigService._internal();
  factory GoogleLoginConfigService() => _instance;
  GoogleLoginConfigService._internal();

  /// Call once at app startup (Windows only) — best-effort, silently no-ops
  /// on failure since AppConfig.googleDesktopClientId already falls back to
  /// .env if this never completes.
  Future<void> refresh() async {
    try {
      final dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-API-Token': AppConfig.apiKey,
          },
        ),
      );

      final response = await dio.get('/api/v1/app-config');
      if (response.statusCode != 200) return;

      final data = response.data;
      if (data is! Map<String, dynamic>) return;

      final googleLogin = data['google_login'] as Map<String, dynamic>?;
      final clientId = googleLogin?['client_id_desktop'] as String?;
      final clientSecret = googleLogin?['client_secret_desktop'] as String?;
      AppConfig.setRemoteGoogleDesktopClientId(clientId);
      AppConfig.setRemoteGoogleDesktopClientSecret(clientSecret);
      debugPrint('✅ Google Desktop client ID/secret synced from admin panel');
    } catch (e) {
      debugPrint('⚠️ Could not fetch Google login config: $e');
    }
  }
}
