import 'dart:io';
import 'package:vpn_master/core/config/app_config.dart';
import 'package:dio/dio.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Encrypted, OS-backed storage (Keychain/Keystore/DPAPI/libsecret) for the
// bearer auth token — SharedPreferences is a plaintext file, unsuitable for
// credentials.
const _secureStorage = FlutterSecureStorage();
const _authTokenKey = 'auth_token';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  ApiClient._internal() {
    // Initialize Dio with defaults so it is never uninitialized
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.baseUrl,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: kDebugMode,
        responseBody: kDebugMode,
        error: kDebugMode,
      ),
    );
    // Automatically inject Firebase ID token before every request
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              // Use cached token (no force-refresh) — Firebase auto-refreshes when expired
              final idToken = await user.getIdToken().timeout(
                const Duration(seconds: 6),
                onTimeout: () => '',
              );
              options.headers['Authorization'] = 'Bearer $idToken';
            }
          } catch (e) {
          }
          handler.next(options);
        },
      ),
    );
  }

  late Dio _dio;
  String? _baseUrl;
  String? _authToken;

  // Initialize the API client
  Future<void> initialize() async {
    final prefs = await SharedPreferences.getInstance();
    _baseUrl = prefs.getString('api_base_url') ?? AppConfig.baseUrl;
    _authToken = await _secureStorage.read(key: _authTokenKey);

    _dio = Dio(
      BaseOptions(
        baseUrl: _baseUrl!,
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          if (_authToken != null) 'Authorization': 'Bearer $_authToken',
        },
      ),
    );

    // Add interceptors
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: kDebugMode,
        responseBody: kDebugMode,
        error: kDebugMode,
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          // Inject Firebase ID token on every request (use cached token)
          try {
            final user = FirebaseAuth.instance.currentUser;
            if (user != null) {
              // No force-refresh — Firebase SDK auto-refreshes expired tokens
              final idToken = await user.getIdToken().timeout(
                const Duration(seconds: 6),
                onTimeout: () => '',
              );
              options.headers['Authorization'] = 'Bearer $idToken';
            } else if (_authToken != null) {
              options.headers['Authorization'] = 'Bearer $_authToken';
            }
          } catch (e) {
            if (_authToken != null) {
              options.headers['Authorization'] = 'Bearer $_authToken';
            }
          }
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            // Token expired, try to refresh or logout
            await _handleUnauthorized();
          }
          handler.next(error);
        },
      ),
    );
  }

  // Set base URL
  Future<void> setBaseUrl(String baseUrl) async {
    _baseUrl = baseUrl;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('api_base_url', baseUrl);

    _dio.options.baseUrl = baseUrl;
  }

  // Set auth token
  Future<void> setAuthToken(String? token) async {
    _authToken = token;

    if (token != null) {
      await _secureStorage.write(key: _authTokenKey, value: token);
    } else {
      await _secureStorage.delete(key: _authTokenKey);
    }

    if (token != null) {
      _dio.options.headers['Authorization'] = 'Bearer $token';
    } else {
      _dio.options.headers.remove('Authorization');
    }
  }

  // GET request
  Future<Response> get(
      String path, {
        Map<String, dynamic>? queryParameters,
        Options? options,
      }) async {
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // POST request
  Future<Response> post(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Options? options,
      }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // PUT request
  Future<Response> put(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Options? options,
      }) async {
    try {
      return await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // DELETE request
  Future<Response> delete(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Options? options,
      }) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // PATCH request
  Future<Response> patch(
      String path, {
        dynamic data,
        Map<String, dynamic>? queryParameters,
        Options? options,
      }) async {
    try {
      return await _dio.patch(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // Upload file
  Future<Response> uploadFile(
      String path,
      File file, {
        String? fileName,
        Map<String, dynamic>? data,
        ProgressCallback? onSendProgress,
      }) async {
    try {
      FormData formData = FormData.fromMap({
        'file': await MultipartFile.fromFile(
          file.path,
          filename: fileName ?? file.path.split('/').last,
        ),
        if (data != null) ...data,
      });

      return await _dio.post(
        path,
        data: formData,
        options: Options(headers: {'Content-Type': 'multipart/form-data'}),
        onSendProgress: onSendProgress,
      );
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // Download file
  Future<Response> downloadFile(
      String path,
      String savePath, {
        ProgressCallback? onReceiveProgress,
        Map<String, dynamic>? queryParameters,
      }) async {
    try {
      return await _dio.download(
        path,
        savePath,
        queryParameters: queryParameters,
        onReceiveProgress: onReceiveProgress,
      );
    } catch (e) {
      _handleError(e);
      rethrow;
    }
  }

  // Handle errors
  void _handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          break;
        case DioExceptionType.connectionError:
          break;
        case DioExceptionType.badResponse:
          break;
        case DioExceptionType.cancel:
          break;
        case DioExceptionType.unknown:
          break;
        default:
      }
    } else {}
  }

  // Handle unauthorized access
  Future<void> _handleUnauthorized() async {
    _authToken = null;
    await _secureStorage.delete(key: _authTokenKey);

    // Here you might want to navigate to login screen
    // or trigger an event to handle logout
  }

  // Test API connection
  Future<bool> testConnection() async {
    try {
      final response = await get('/api/health');
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Get per-user VPN peer config (new v2 flow). Returns null on any failure
  // (404 because backend/server doesn't support it yet, network error, etc.)
  // so callers can fall back to the old shared-config endpoint. Firebase ID
  // token is attached automatically by the interceptor above, so the
  // backend can identify which user this peer belongs to.
  Future<Map<String, dynamic>?> getPeerConfig(
      int serverId,
      String protocol, // 'wireguard' | 'openvpn'
      ) async {
    try {
      final response = await get(
        '/api/v2/peer',
        queryParameters: {'server_id': serverId, 'protocol': protocol},
      );
      if (response.statusCode == 200 &&
          response.data is Map<String, dynamic>) {
        final data = response.data as Map<String, dynamic>;
        if (data.containsKey('config')) return data;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get current base URL
  String? get baseUrl => _baseUrl;

  // Get current auth token
  String? get authToken => _authToken;

  // Check if authenticated
  bool get isAuthenticated => _authToken != null;

  // Clear all data
  Future<void> clear() async {
    _authToken = null;
    await _secureStorage.delete(key: _authTokenKey);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('api_base_url');
  }
}
