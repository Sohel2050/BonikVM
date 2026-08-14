import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:flutter/foundation.dart';
import 'dart:io';
import '../config/app_config.dart';

class ApiService {
  static final ApiService _instance = ApiService._internal();
  factory ApiService() => _instance;

  static ApiService get instance => _instance;

  late Dio _dio;
  bool _isInitialized = false;

  ApiService._internal() {
    // Eagerly initialize _dio so it's never uninitialized even before initialize() is called
    _dio = Dio(
      BaseOptions(
        baseUrl: AppConfig.apiBaseUrl,
        connectTimeout: const Duration(seconds: 10),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
        },
      ),
    );
  }

  void initialize() {
    try {
      _dio = Dio(
        BaseOptions(
          baseUrl: AppConfig.apiBaseUrl,
          connectTimeout: const Duration(seconds: 10), // Increased for payments
          receiveTimeout: const Duration(
            seconds: 30,
          ), // Increased for payment processing
          sendTimeout: const Duration(seconds: 10), // Increased for uploads
          headers: {
            'Content-Type': 'application/json',
            'Accept': 'application/json',
            'X-API-Token': AppConfig.apiKey, // Add API token for authentication
            // Simple headers for better compatibility with all build types
            'User-Agent': 'AxeVPN/3.0.0',
            'X-App-Version': '3.0.0',
            // Add connection keep-alive
            'Connection': 'keep-alive',
          },
          // Add retry configuration
          followRedirects: false, // Handle redirects manually
          maxRedirects: 0,
          validateStatus: (status) =>
              status! < 400, // Accept redirects as valid
        ),
      );

      // Configure HTTP client for TLS compatibility issues
      (_dio.httpClientAdapter as IOHttpClientAdapter).createHttpClient = () {
        final client = HttpClient();
        // Handle bad certificates for servers with TLS issues
        client.badCertificateCallback = (cert, host, port) {
          return true;
        };
        return client;
      };

      // Add interceptors for logging and error handling
      if (kDebugMode) {
        _dio.interceptors.add(
          LogInterceptor(
            requestBody: true,
            responseBody: true,
            logPrint: (obj) => null, // Remove debug logging
          ),
        );
      }

      // Rate limiting and retry interceptor
      _dio.interceptors.add(
        InterceptorsWrapper(
          onError: (error, handler) async {
            // Handle 429 rate limiting with retry
            if (error.response?.statusCode == 429) {
              // Get retry-after header or default to 2 seconds
              final retryAfter = error.response?.headers.value('retry-after');
              final delaySeconds = retryAfter != null
                  ? int.tryParse(retryAfter) ?? 2
                  : 2;

              await Future.delayed(Duration(seconds: delaySeconds));

              try {
                // Clone the original request and retry
                final options = error.requestOptions;
                final response = await _dio.request(
                  options.path,
                  options: Options(
                    method: options.method,
                    headers: options.headers,
                  ),
                  data: options.data,
                  queryParameters: options.queryParameters,
                );

                return handler.resolve(response);
              } catch (retryError) {
                // Fall through to original error handling
              }
            }

            handler.next(error);
          },
        ),
      );

      _isInitialized = true;
    } catch (e) {
      _isInitialized = false;
    }
  }

  /// Ensure API service is initialized before making requests
  void _ensureInitialized() {
    if (!_isInitialized) {
      initialize();
    }
  }

  /// Make a request using HTTPS only (cleartext HTTP is not permitted)
  Future<Response> _makeRequestWithFallback(String endpoint) async {
    _ensureInitialized();

    final response = await _dio.get(endpoint);

    if (response.statusCode == 200) {
      return response;
    }

    throw DioException(
      requestOptions: RequestOptions(path: endpoint),
      message: 'Request failed with status ${response.statusCode}',
      type: DioExceptionType.unknown,
    );
  }

  // ── Protocol settings ────────────────────────────────────────────────

  /// Fetch which VPN protocols are globally enabled from the admin panel.
  /// Returns a map like: {'wireguard': true, 'v2ray': true, 'openvpn': true, 'openconnect': false}
  Future<Map<String, bool>> getEnabledProtocols() async {
    try {
      final response = await _dio.get('/v1/protocol-settings');
      if (response.statusCode == 200 && response.data is Map) {
        return Map<String, bool>.from(
          (response.data as Map).map(
            (k, v) => MapEntry(k.toString(), v == true || v == 1),
          ),
        );
      }
    } catch (_) {}
    // Default: everything enabled so servers still work even if endpoint is missing
    return {
      'wireguard': true,
      'v2ray': true,
      'openvpn': true,
      'openconnect': false,
    };
  }

  // Get servers with protocol support information
  Future<List<VpnServer>> getServersWithProtocols() async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // Use the new protocols endpoint
        final response = await _makeRequestWithFallback(
          '/api/${AppConfig.apiVersion}/servers/protocols',
        );

        if (response.statusCode == 200) {
          final List<dynamic> data = response.data is List
              ? response.data
              : response.data['data'] ?? [];

          final servers = data
              .map((json) => VpnServer.fromJsonWithProtocols(json))
              .toList();
          return servers;
        }
        throw Exception(
          'Failed to load servers with protocols - Status: ${response.statusCode}',
        );
      } catch (e) {
        retryCount++;
        if (retryCount < maxRetries) {
          await Future.delayed(Duration(seconds: retryCount * 2));
          continue;
        }

        // Fallback to regular servers endpoint

        return await getServers();
      }
    }

    // Final fallback
    return await getServers();
  }

  // Get all servers - using correct API endpoint with retry logic and TLS fallback
  Future<List<VpnServer>> getServers() async {
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        // Use the new fallback method
        final response = await _makeRequestWithFallback(
          '/api/${AppConfig.apiVersion}/list',
        );

        if (response.statusCode == 200) {
          // API returns direct array, not wrapped in 'data'
          final List<dynamic> data = response.data is List
              ? response.data
              : response.data['data'] ?? [];

          final servers = data.map((json) => VpnServer.fromJson(json)).toList();
          return servers;
        }
        throw Exception(
          'Failed to load servers - Status: ${response.statusCode}',
        );
      } catch (e) {
        retryCount++;
        if (e.toString().contains('Connection reset by peer') ||
            e.toString().contains('SocketException') ||
            e.toString().contains('Connection refused') ||
            e.toString().contains('HandshakeException')) {
          if (retryCount < maxRetries) {
            // Wait before retrying with exponential backoff
            await Future.delayed(Duration(seconds: retryCount * 2));
            continue;
          }
        }

        // If we've exhausted retries or it's not a network error, rethrow
        if (retryCount >= maxRetries) {
          throw Exception(
            'Failed to fetch servers after $maxRetries attempts: $e',
          );
        }

        rethrow;
      }
    }

    throw Exception('Failed to fetch servers after $maxRetries attempts');
  }

  // Get best server - using correct API endpoint
  Future<VpnServer?> getBestServer() async {
    try {
      final response = await _dio.get('/api/${AppConfig.apiVersion}/best');
      if (response.statusCode == 200) {
        // API returns just the server ID, so get all servers and find the best one
        final bestServerId = response.data.toString();
        final servers = await getServers();

        // Find server by ID
        for (final server in servers) {
          if (server.id == bestServerId) {
            return server;
          }
        }

        // Fallback to first server if best server not found
        return servers.isNotEmpty ? servers.first : null;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get app settings
  Future<AppSettings> getSettings() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/get-setting',
      );
      if (response.statusCode == 200) {
        return AppSettings.fromJson(response.data['data']);
      }
      throw Exception('Failed to load settings');
    } catch (e) {
      rethrow;
    }
  }

  // Get AdMob IDs
  Future<AdMobConfig> getAdIds() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/get-ad-ids',
      );
      if (response.statusCode == 200) {
        // API returns ad IDs directly, not wrapped in 'data'
        final responseData = response.data;
        if (responseData is Map<String, dynamic>) {
          return AdMobConfig.fromJson(responseData);
        } else {
          throw Exception('Invalid response format');
        }
      }
      throw Exception('Failed to load ad IDs');
    } catch (e) {
      rethrow;
    }
  }

  // Get app update info (force-update / min-version check against admin panel)
  Future<Map<String, dynamic>> getUpdateInfo({
    required String platform,
    required String version,
  }) async {
    final response = await _dio.get(
      '/api/${AppConfig.apiVersion}/app/update-info',
      queryParameters: {'platform': platform, 'version': version},
    );
    if (response.statusCode == 200 && response.data is Map<String, dynamic>) {
      return (response.data as Map<String, dynamic>)['data']
              as Map<String, dynamic>? ??
          {};
    }
    throw Exception('Failed to load update info');
  }

  // Get AdMob Settings from Admin Panel
  Future<Map<String, dynamic>> getAdmobSettings() async {
    try {
      _ensureInitialized();

      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/get-ad-settings',
      );
      if (response.statusCode == 200) {
        final responseData = response.data;
        if (responseData is Map<String, dynamic>) {
          return responseData;
        } else {
          throw Exception('Invalid admob settings response format');
        }
      }
      throw Exception('Failed to load admob settings');
    } catch (e) {
      rethrow;
    }
  }

  // Get Notification Settings from Admin Panel
  Future<Map<String, dynamic>> getNotificationSettings() async {
    try {
      _ensureInitialized();

      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/get-notification-settings',
      );
      if (response.statusCode == 200) {
        final responseData = response.data;
        if (responseData is Map<String, dynamic>) {
          return responseData;
        } else {
          throw Exception('Invalid notification settings response format');
        }
      }
      throw Exception('Failed to load notification settings');
    } catch (e) {
      rethrow;
    }
  }

  // Get Ad Configuration for a specific server
  Future<Map<String, dynamic>> getAdConfig(int serverId) async {
    try {
      _ensureInitialized();

      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/servers/ads?id=$serverId',
      );
      if (response.statusCode == 200) {
        final responseData = response.data;
        if (responseData is Map<String, dynamic>) {
          return responseData;
        } else {
          throw Exception('Invalid ad config response format');
        }
      }
      throw Exception('Failed to load ad config');
    } catch (e) {
      rethrow;
    }
  }

  // Get server OpenVPN configuration - simplified but using correct endpoint
  Future<String> getServerConfig(int serverId) async {
    try {
      _ensureInitialized();

      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/get?id=$serverId',
      );

      if (response.statusCode == 200) {
        final configData = response.data;

        // Handle both plain text and JSON responses
        if (configData is String && configData.isNotEmpty) {
          return configData;
        } else if (configData is Map<String, dynamic>) {
          if (configData.containsKey('config')) {
            final config = configData['config'];
            if (config is String && config.isNotEmpty) {
              return config;
            }
          } else if (configData.containsKey('error')) {
            // Surface the backend error message so callers can show it
            throw Exception('Server config error: ${configData['error']}');
          }
        }
        return '';
      } else {
        return '';
      }
    } on Exception {
      // Re-throw meaningful exceptions (e.g., "Server config error: ...") so
      // callers like _connectWireGuard can show the real reason to the user.
      rethrow;
    } catch (e) {
      return '';
    }
  }

  // Get protocol-specific configuration for a server
  Future<Map<String, dynamic>?> getProtocolConfig(
    String protocol,
    int serverId,
  ) async {
    try {
      _ensureInitialized();

      final response = await _makeRequestWithFallback(
        '/api/${AppConfig.apiVersion}/servers/$serverId/protocols/$protocol',
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Test protocol connectivity for a server
  Future<Map<String, dynamic>?> testProtocolConnectivity(
    String protocol,
    int serverId,
  ) async {
    try {
      _ensureInitialized();

      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/servers/$serverId/protocols/$protocol/test',
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Get legacy protocol config (backward compatibility)
  Future<Map<String, dynamic>?> getLegacyProtocolConfig(String protocol) async {
    try {
      _ensureInitialized();

      final response = await _makeRequestWithFallback(
        '/api/${AppConfig.apiVersion}/configs/$protocol',
      );

      if (response.statusCode == 200) {
        return response.data;
      } else {
        return null;
      }
    } catch (e) {
      return null;
    }
  }

  // Download VPN config - Now we create it locally based on server data
  Future<String> downloadConfig(String serverId) async {
    // This method is deprecated - we now create configs locally
    // Keeping for compatibility but returning empty string
    return '';
  }

  // Log connection with proper parameters
  Future<void> logConnect(
    String serverId,
    String deviceId, {
    bool isAuto = false,
  }) async {
    try {
      // Ensure API service is initialized
      _ensureInitialized(); // First get the user's IP address
      String userIP = '';
      try {
        final ipResponse = await _dio.get(
          '/api/${AppConfig.apiVersion}/request-ip',
        );
        userIP = ipResponse.data['value'] ?? '';
      } catch (ipError) {
        userIP = 'unknown';
      }

      // Use the correct endpoint that matches the backend API
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/log-connect',
        data: {
          'server_id': serverId,
          'device_id': deviceId,
          'ip': userIP,
          'is_auto': isAuto ? 'true' : 'false',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.data['success'] == true) {
      } else {}
    } catch (e) {
      // Don't throw error as this is not critical for VPN functionality

      // Log the specific error for debugging
      if (e.toString().contains('404')) {
      } else if (e.toString().contains('422')) {
      } else if (e.toString().contains('500')) {
      } else if (e.toString().contains('LateInitializationError')) {}
    }
  }

  // Log disconnection with proper parameters
  Future<void> logDisconnect(
    String serverId,
    String deviceId,
    Duration duration,
  ) async {
    try {
      // Ensure API service is initialized
      _ensureInitialized(); // Use the correct endpoint that matches the backend API
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/log-disconnect',
        data: {
          'server_id': serverId,
          'device_id': deviceId,
          'duration_seconds': duration.inSeconds,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.data['success'] == true) {
      } else {}
    } catch (e) {
      // Don't throw error as this is not critical for VPN functionality

      // Log the specific error for debugging
      if (e.toString().contains('404')) {
      } else if (e.toString().contains('422')) {
      } else if (e.toString().contains('500')) {
      } else if (e.toString().contains('LateInitializationError')) {}
    }
  }

  // Register FCM token
  Future<void> registerFcmToken(
    String token,
    String deviceId, {
    String? userId,
  }) async {
    try {
      final data = {
        'token': token,
        'device_id': deviceId,
        'platform': defaultTargetPlatform.name,
      };

      // Only include user_id if provided (when user is authenticated)
      if (userId != null && userId.isNotEmpty) {
        data['user_id'] = userId;
      }

      await _dio.post('/api/${AppConfig.apiVersion}/register-fcm', data: data);
    } catch (e) {}
  }

  // Get user IP
  Future<String?> getClientIp() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/request-ip',
      );
      if (response.statusCode == 200) {
        return response.data['ip'];
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  // Get available purchase plans
  Future<List<PurchasePlan>?> getPurchasePlans() async {
    try {
      final response = await _makeRequestWithFallback(
        '/api/${AppConfig.apiVersion}/purchase/plans',
      );

      if (response.statusCode == 200) {
        final data = response.data;

        if (data['success'] == true && data['data'] != null) {
          final plansData = data['data']['plans'] as List?;

          final plans = plansData
              ?.map((plan) => PurchasePlan.fromJson(plan))
              .toList();
          return plans;
        } else {
        }
      } else {
      }

      return null;
    } catch (e) {
      return null;
    }
  }

  // Verify purchase with backend
  Future<Map<String, dynamic>?> verifyPurchase({
    required dynamic userId, // Accept both String and int
    required String receiptData,
    required String productId,
    required String platform,
    String? transactionId,
    String? firebaseUid,
    String? userEmail,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/purchase/verify',
        options: Options(validateStatus: (s) => true),
        data: {
          'user_id': userId,
          'receipt_data': receiptData,
          'product_id': productId,
          'platform': platform,
          'transaction_id': transactionId,
          'firebase_uid': firebaseUid,
          'user_email': userEmail,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      return null;
    } catch (e) {
      return null;
    }
  }

  // Payment Methods Configuration
  Future<Map<String, dynamic>> getAvailablePaymentMethods() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/payment-methods',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return {
          'success': true,
          'payment_methods': data['payment_methods'] ?? [],
          'count': data['count'] ?? 0,
        };
      } else {
        return {
          'success': false,
          'error': 'Failed to load payment methods',
          'payment_methods': [],
        };
      }
    } catch (e) {
      return {
        'success': false,
        'error': 'Network error loading payment methods',
        'payment_methods': [],
      };
    }
  }

  /// Extract a readable error message from a Dio response or exception.
  String _extractPaymentError(dynamic e, String fallback) {
    if (e is DioException) {
      // Try to read the backend error message from the response body
      final body = e.response?.data;
      if (body is Map) {
        final msg = body['message'] ?? body['error'] ?? body['errors'];
        if (msg != null) return msg.toString();
      }
      if (body is String && body.isNotEmpty) return body;
    }
    return fallback;
  }

  // Payment processing methods - REAL IMPLEMENTATION
  Future<Map<String, dynamic>> createPayPalOrder({
    required String planId,
    required double amount,
    required String userId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/payments/paypal/create-order',
        options: Options(validateStatus: (s) => true),
        data: {
          'plan_id': planId,
          'amount': amount,
          'user_id': userId,
          'currency': 'USD',
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'message': 'Order creation failed'};
    } catch (e) {
      return {
        'success': false,
        'message': _extractPaymentError(e, 'Failed to create PayPal order'),
      };
    }
  }

  Future<Map<String, dynamic>> capturePayPalPayment({
    required String orderId,
    required String planId,
    required String userId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/payments/paypal/capture',
        options: Options(validateStatus: (s) => true),
        data: {'order_id': orderId, 'plan_id': planId, 'user_id': userId},
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'message': 'Payment capture failed'};
    } catch (e) {
      return {
        'success': false,
        'message': _extractPaymentError(e, 'Failed to capture PayPal payment'),
      };
    }
  }

  Future<Map<String, dynamic>> createStripePaymentIntent({
    required String planId,
    required double amount,
    required String userId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/payments/stripe/create-intent',
        options: Options(validateStatus: (s) => true),
        data: {
          'plan_id': planId,
          'amount': amount,
          'user_id': userId,
          'currency': 'USD',
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'message': 'Payment intent creation failed'};
    } catch (e) {
      return {
        'success': false,
        'message': _extractPaymentError(e, 'Failed to create Stripe payment'),
      };
    }
  }

  Future<Map<String, dynamic>> confirmStripePayment({
    required String paymentIntentId,
    required String planId,
    required String userId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/payments/stripe/confirm',
        options: Options(validateStatus: (s) => true),
        data: {
          'payment_intent_id': paymentIntentId,
          'plan_id': planId,
          'user_id': userId,
        },
      );

      final data = response.data;
      if (data is Map<String, dynamic>) return data;
      return {'success': false, 'message': 'Payment confirmation failed'};
    } catch (e) {
      return {
        'success': false,
        'message': _extractPaymentError(e, 'Failed to confirm Stripe payment'),
      };
    }
  }

  // Get user payment receipts/history
  Future<Map<String, dynamic>> getUserReceipts({required String userId}) async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/payments/receipts/$userId',
      );

      if (response.statusCode == 200) {
        final data = response.data;

        return data;
      }

      return {'success': false, 'error': 'Failed to fetch payment history'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  Future<Map<String, dynamic>> generateReceipt({
    required String transactionId,
    required String planId,
    required double amount,
    required String paymentMethod,
    required String userId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/payments/receipt',
        data: {
          'transaction_id': transactionId,
          'plan_id': planId,
          'amount': amount,
          'payment_method': paymentMethod,
          'user_id': userId,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;

        return data;
      }

      return {'success': false, 'error': 'Receipt generation failed'};
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Create a payment transaction record
  Future<Map<String, dynamic>> createPaymentTransaction({
    required String userId,
    required String transactionId,
    required String planId,
    required String paymentMethod,
    required double amount,
    required String gateway,
    required String status,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/payments/transaction',
        data: {
          'user_id': userId,
          'transaction_id': transactionId,
          'plan_id': planId,
          'payment_method': paymentMethod,
          'amount': amount,
          'gateway': gateway,
          'status': status,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      if (response.statusCode == 200) {
        final data = response.data;

        return data;
      } else {
        return {'success': false, 'error': 'HTTP ${response.statusCode}'};
      }
    } catch (e) {
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Get user payment transactions (purchase history)
  Future<List<Map<String, dynamic>>> getUserTransactions() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/payments/transactions',
      );

      if (response.statusCode == 200) {
        final data = response.data; // Handle paginated response structure
        if (data['data'] != null) {
          return List<Map<String, dynamic>>.from(data['data']);
        } else if (data is List) {
          return List<Map<String, dynamic>>.from(data);
        } else {
          return [];
        }
      } else {
        return [];
      }
    } catch (e) {
      return [];
    }
  }

  // Voucher Redemption Methods
  /// Validate a voucher code without redeeming it
  Future<Map<String, dynamic>> validateVoucherCode(String code) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/vouchers/validate',
        data: {'code': code},
      );

      if (response.statusCode == 200) {
        final data = response.data;

        return data;
      }

      return {'success': false, 'valid': false, 'message': 'Validation failed'};
    } catch (e) {
      return {
        'success': false,
        'valid': false,
        'message': 'Network error during validation',
      };
    }
  }

  /// Redeem a voucher code
  Future<Map<String, dynamic>> redeemVoucherCode(
    String code,
    String userId,
  ) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/vouchers/redeem',
        data: {'code': code, 'user_id': userId},
      );

      if (response.statusCode == 200) {
        final data = response.data;

        if (data['subscription'] != null) {}
        return data;
      }

      return {'success': false, 'message': 'Redemption failed'};
    } catch (e) {
      if (e is DioException && e.response != null) {
        final errorData = e.response!.data;
        return {
          'success': false,
          'message': errorData['message'] ?? 'Redemption failed',
        };
      }
      return {'success': false, 'message': 'Network error during redemption'};
    }
  }

  /// Get user's voucher redemption history
  Future<Map<String, dynamic>> getVoucherHistory() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/vouchers/history',
      );

      if (response.statusCode == 200) {
        final data = response.data;
        return data;
      }

      return {'success': false, 'redemptions': []};
    } catch (e) {
      return {'success': false, 'redemptions': []};
    }
  }

  /// Get current IP address information
  Future<Map<String, dynamic>> getCurrentIp() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/user/current-ip',
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {'success': false};
    } catch (e) {
      return {'success': false};
    }
  }

  /// Get public IP address from external service (fallback)
  Future<Map<String, dynamic>> getPublicIp() async {
    final externalDio = Dio();
    // 1st: ipinfo.io — reliable, works with VPN/datacenter IPs, 50k req/month free
    try {
      final response = await externalDio
          .get('https://ipinfo.io/json')
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['ip'] != null) {
          // ipinfo.io returns org like "AS12345 Provider Name" — map to isp
          data['isp'] = data['org'] ?? data['isp'];
          // ipinfo.io returns country as a bare 2-letter code (e.g. "DE") in
          // the `country` field — IpAddressInfo expects that in
          // `countryCode`/`country_code`, so mirror it there for the flag.
          data['countryCode'] = data['country'];
          return data;
        }
      }
    } catch (_) {}
    // 2nd: ipwho.is (free, HTTPS, good VPN support)
    try {
      final response = await externalDio
          .get('https://ipwho.is/')
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['ip'] != null) {
          // Normalize isp field from nested connection object
          if (data['connection'] is Map) {
            data['isp'] =
                (data['connection'] as Map)['isp'] ??
                (data['connection'] as Map)['org'];
          }
          return data;
        }
      }
    } catch (_) {}
    // 3rd: ipapi.co (may rate-limit on VPN IPs but try as last resort)
    try {
      final response = await externalDio
          .get('https://ipapi.co/json/')
          .timeout(const Duration(seconds: 5));
      if (response.statusCode == 200 && response.data is Map) {
        final data = Map<String, dynamic>.from(response.data as Map);
        if (data['ip'] != null && data['error'] == null) return data;
      }
    } catch (_) {}
    throw Exception('Failed to get IP address');
  }

  /// Delete user account
  Future<Map<String, dynamic>> deleteAccount({required String userId}) async {
    try {
      final response = await _dio.delete(
        '/api/${AppConfig.apiVersion}/user/account/$userId',
      );

      if (response.statusCode == 200) {
        return response.data;
      }

      return {'success': false, 'message': 'Failed to delete account'};
    } catch (e) {
      if (e is DioException && e.response != null) {
        final errorData = e.response!.data;
        return {
          'success': false,
          'message': errorData['message'] ?? 'Failed to delete account',
        };
      }
      return {
        'success': false,
        'message': 'Network error during account deletion',
      };
    }
  }
}

// Data Models
class VpnServer {
  final String id;
  final String name;
  final String ip;
  final String country;
  final String countryCode;
  final String flag;
  final bool premium;
  final int latency;
  final String configUrl;
  final bool isActive;
  final double load;
  final String protocol;
  final String tcpPort;
  final String udpPort;
  final int port;
  final String vpnUsername;
  final String vpnPassword;
  final bool useFile;
  final int freeConnectDuration;
  final int connectedDevices;
  final int order;
  final int capacity; // Server capacity from backend
  final double loadPercentage; // Actual load percentage from backend
  final bool isFull; // Whether server is at full capacity
  final List<String>? protocols; // Supported protocols for this server
  final String
  vpnProtocolType; // 'openvpn', 'wireguard', 'v2ray', 'openconnect', or 'oneconnect'
  final String provider; // 'manual' or 'oneconnect'
  final String? providerServerId; // Remote ID from OneConnect
  final Map<String, dynamic>? providerPayload; // Decoded OneConnect payload
  final String? flagUrl; // CDN flag URL (OneConnect)
  final bool isImported; // True when synced from a provider

  // ── V2Ray / Xray fields ───────────────────────────────────────────────
  final String? v2raySubProtocol; // vless | vmess | trojan | shadowsocks
  final String? v2rayUuid;
  final String? v2rayNetwork; // tcp | ws | grpc
  final String? v2raySecurity; // none | tls | reality
  final String? v2rayPath;
  final String? v2rayHost;
  final String? v2rayPublicKey; // Reality public key
  final String? v2rayShortId;
  final int? v2rayPort;

  // ── OpenConnect (Cisco AnyConnect compatible) fields ──────────────────
  final String? ocServerUrl;
  final String? ocAuthGroup;
  final String? ocServercert;
  final String? ocUsername;
  final String? ocPassword;

  VpnServer({
    required this.id,
    required this.name,
    required this.ip,
    required this.country,
    required this.countryCode,
    required this.flag,
    required this.premium,
    required this.latency,
    required this.configUrl,
    this.isActive = true,
    this.load = 0.0,
    required this.protocol,
    required this.tcpPort,
    required this.udpPort,
    required this.port,
    required this.vpnUsername,
    required this.vpnPassword,
    required this.useFile,
    required this.freeConnectDuration,
    required this.connectedDevices,
    required this.order,
    this.capacity = 100,
    this.loadPercentage = 0.0,
    this.isFull = false,
    this.protocols,
    this.vpnProtocolType = 'openvpn',
    this.provider = 'manual',
    this.providerServerId,
    this.providerPayload,
    this.flagUrl,
    this.isImported = false,
    // V2Ray
    this.v2raySubProtocol,
    this.v2rayUuid,
    this.v2rayNetwork,
    this.v2raySecurity,
    this.v2rayPath,
    this.v2rayHost,
    this.v2rayPublicKey,
    this.v2rayShortId,
    this.v2rayPort,
    // OpenConnect
    this.ocServerUrl,
    this.ocAuthGroup,
    this.ocServercert,
    this.ocUsername,
    this.ocPassword,
  });

  /// Check if this server uses OneConnect provider
  bool get isOneConnect =>
      provider == 'oneconnect' || vpnProtocolType == 'oneconnect';

  /// Check if this server supports OpenVPN
  bool get supportsOpenVPN =>
      vpnProtocolType == 'openvpn' || (protocols?.contains('openvpn') ?? false);

  /// Check if this server supports WireGuard
  bool get supportsWireGuard =>
      vpnProtocolType == 'wireguard' ||
      (protocols?.contains('wireguard') ?? false);

  /// Check if this server uses V2Ray / Xray
  bool get isV2Ray => vpnProtocolType == 'v2ray';

  /// Check if this server uses OpenConnect
  bool get isOpenConnect => vpnProtocolType == 'openconnect';

  /// Get human-readable protocol name
  String get protocolDisplayName {
    switch (vpnProtocolType) {
      case 'wireguard':
        return 'WireGuard';
      case 'oneconnect':
        return 'OneConnect';
      case 'openvpn':
        return 'OpenVPN';
      case 'v2ray':
        final sub = v2raySubProtocol?.toUpperCase() ?? 'V2Ray';
        return 'V2Ray ($sub)';
      case 'openconnect':
        return 'OpenConnect';
      default:
        return 'VPN';
    }
  }

  factory VpnServer.fromJson(Map<String, dynamic> json) {
    // Handle the API response format from /api/${AppConfig.apiVersion}/list endpoint
    final countryCode = (json['country_code'] ?? '').toString().toUpperCase();
    final connectedDevices = _parseToInt(json['connected_devices']) ?? 0;
    final capacity = _parseToInt(json['capacity']) ?? 100;
    final isFull = (json['is_full'] as bool?) ?? (connectedDevices >= capacity);
    final loadPercentage =
        (json['load_percentage'] as num?)?.toDouble() ??
        (capacity > 0 ? (connectedDevices / capacity * 100) : 0.0);

    return VpnServer(
      id: json['id'].toString(),
      // 'city' is the API field name; 'name' is what toJson() saves — accept both.
      name: (json['city']?.toString().isNotEmpty == true)
          ? json['city'].toString()
          : (json['name']?.toString().isNotEmpty == true)
          ? json['name'].toString()
          : 'Unknown Server',
      ip: json['ip'] ?? '',
      country: (json['city']?.toString().isNotEmpty == true)
          ? json['city'].toString()
          : (json['country']?.toString().isNotEmpty == true)
          ? json['country'].toString()
          : '',
      countryCode: countryCode,
      flag: _getCountryFlag(countryCode),
      // API uses 'is_premium'; toJson() saves 'premium' — accept both keys.
      premium:
          (json['is_premium'] == true ||
          json['is_premium'] == 1 ||
          json['premium'] == true ||
          json['premium'] == 1),
      latency: 0, // Will be calculated via ping
      configUrl: json['config_url'] ?? '', // toJson saves as 'config_url'
      isActive: (_parseToInt(json['use_file']) ?? 0) == 1,
      load: (json['load'] as num?)?.toDouble() ?? loadPercentage / 100.0,
      protocol: json['protocol'] ?? 'udp',
      tcpPort: json['tcp_port']?.toString() ?? '1194',
      udpPort: json['udp_port']?.toString() ?? '1194',
      port: _parseToInt(json['port']) ?? 1194,
      vpnUsername: json['vpn_username'] ?? '',
      vpnPassword: json['vpn_password'] ?? '',
      useFile: (json['use_file'] ?? 0) == 1,
      freeConnectDuration: _parseToInt(json['free_connect_duration']) ?? 0,
      connectedDevices: connectedDevices,
      order: _parseToInt(json['order']) ?? 0,
      capacity: capacity,
      loadPercentage: loadPercentage,
      isFull: isFull,
      protocols: json['protocols'] != null
          ? List<String>.from(json['protocols'])
          : null,
      // toJson() saves as 'vpn_protocol_type'; also fall back to it here.
      vpnProtocolType: json['vpn_protocol_type']?.toString() ?? 'openvpn',
      provider: json['provider']?.toString() ?? 'manual',
      providerServerId: json['provider_server_id']?.toString(),
      providerPayload: json['provider_payload'] is Map
          ? Map<String, dynamic>.from(json['provider_payload'] as Map)
          : null,
      flagUrl: json['flag_url']?.toString(),
      isImported: json['is_imported'] == true || json['is_imported'] == 1,
      // V2Ray fields
      v2raySubProtocol: json['v2ray_sub_protocol']?.toString(),
      v2rayUuid: json['v2ray_uuid']?.toString(),
      v2rayNetwork: json['v2ray_network']?.toString(),
      v2raySecurity: json['v2ray_security']?.toString(),
      v2rayPath: json['v2ray_path']?.toString(),
      v2rayHost: json['v2ray_host']?.toString(),
      v2rayPublicKey: json['v2ray_public_key']?.toString(),
      v2rayShortId: json['v2ray_short_id']?.toString(),
      v2rayPort: _parseToInt(json['v2ray_port']),
      // OpenConnect fields
      ocServerUrl: json['oc_server_url']?.toString(),
      ocAuthGroup: json['oc_auth_group']?.toString(),
      ocServercert: json['oc_servercert']?.toString(),
      ocUsername: json['oc_username']?.toString(),
      ocPassword: json['oc_password']?.toString(),
    );
  }

  factory VpnServer.fromJsonWithProtocols(Map<String, dynamic> json) {
    // Handle the enhanced API response format from /api/v1/servers/protocols endpoint
    final countryCode = (json['country_code'] ?? '').toString().toUpperCase();
    final connectedDevices = _parseToInt(json['connected_devices']) ?? 0;
    final capacity = _parseToInt(json['capacity']) ?? 100;
    final isFull = (json['is_full'] as bool?) ?? (connectedDevices >= capacity);
    final loadPercentage =
        (json['load_percentage'] as num?)?.toDouble() ??
        (capacity > 0 ? (connectedDevices / capacity * 100) : 0.0);

    // Parse VPN protocol type (default to OpenVPN for backward compatibility)
    final vpnProtocolType = json['vpn_protocol_type']?.toString() ?? 'openvpn';

    // Parse supported protocols
    List<String>? supportedProtocols;
    if (json['protocols'] != null) {
      supportedProtocols = List<String>.from(json['protocols']);
    } else if (json['supported_protocols'] != null) {
      supportedProtocols = List<String>.from(json['supported_protocols']);
    }

    // Check for V2Ray protocols in protocol_config
    if (supportedProtocols == null && json['protocol_config'] != null) {
      supportedProtocols = [vpnProtocolType]; // Include primary protocol
      final protocolConfig = json['protocol_config'] as Map<String, dynamic>;
      supportedProtocols.addAll(protocolConfig.keys);
    }

    return VpnServer(
      id: json['id'].toString(),
      name: (json['name']?.toString().isNotEmpty == true)
          ? json['name'].toString()
          : (json['city']?.toString().isNotEmpty == true)
          ? json['city'].toString()
          : 'Unknown Server',
      ip: json['ip'] ?? '',
      country: (json['city']?.toString().isNotEmpty == true)
          ? json['city'].toString()
          : (json['country']?.toString().isNotEmpty == true)
          ? json['country'].toString()
          : '',
      countryCode: countryCode,
      flag: _getCountryFlag(countryCode),
      premium:
          (json['is_premium'] == true || json['is_premium'] == 1) ||
          (json['is_free'] == 0 ||
              json['is_free'] == false), // Correct premium logic
      latency: 0, // Will be calculated via ping
      configUrl:
          json['v2ray_share_url'] ?? '', // Use V2Ray share URL if available
      isActive: true, // Assume enabled servers are active
      load: loadPercentage / 100.0, // Convert percentage to 0.0-1.0 range
      protocol: json['protocol'] ?? 'udp',
      tcpPort: json['tcp_port']?.toString() ?? '1194',
      udpPort: json['udp_port']?.toString() ?? '1194',
      port: _parseToInt(json['port']) ?? 1194,
      vpnUsername: json['vpn_username'] ?? '',
      vpnPassword: json['vpn_password'] ?? '',
      useFile: (json['use_file'] ?? 0) == 1,
      freeConnectDuration: _parseToInt(json['free_connect_duration']) ?? 0,
      connectedDevices: connectedDevices,
      order: _parseToInt(json['order']) ?? 0,
      capacity: capacity,
      loadPercentage: loadPercentage,
      isFull: isFull,
      protocols: supportedProtocols,
      vpnProtocolType: vpnProtocolType,
      provider: json['provider']?.toString() ?? 'manual',
      providerServerId: json['provider_server_id']?.toString(),
      providerPayload: json['provider_payload'] is Map
          ? Map<String, dynamic>.from(json['provider_payload'] as Map)
          : null,
      flagUrl: json['flag_url']?.toString(),
      isImported: json['is_imported'] == true || json['is_imported'] == 1,
      // V2Ray fields
      v2raySubProtocol: json['v2ray_sub_protocol']?.toString(),
      v2rayUuid: json['v2ray_uuid']?.toString(),
      v2rayNetwork: json['v2ray_network']?.toString(),
      v2raySecurity: json['v2ray_security']?.toString(),
      v2rayPath: json['v2ray_path']?.toString(),
      v2rayHost: json['v2ray_host']?.toString(),
      v2rayPublicKey: json['v2ray_public_key']?.toString(),
      v2rayShortId: json['v2ray_short_id']?.toString(),
      v2rayPort: _parseToInt(json['v2ray_port']),
      // OpenConnect fields
      ocServerUrl: json['oc_server_url']?.toString(),
      ocAuthGroup: json['oc_auth_group']?.toString(),
      ocServercert: json['oc_servercert']?.toString(),
      ocUsername: json['oc_username']?.toString(),
      ocPassword: json['oc_password']?.toString(),
    );
  }

  // Helper method to safely parse strings to integers
  static int? _parseToInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is String) {
      return int.tryParse(value);
    }
    return null;
  }

  static String _getCountryFlag(String countryCode) {
    final flags = {
      'AF': '🇦🇫',
      'AX': '🇦🇽',
      'AL': '🇦🇱',
      'DZ': '🇩🇿',
      'AS': '🇦🇸',
      'AD': '🇦🇩',
      'AO': '🇦🇴',
      'AI': '🇦🇮',
      'AQ': '🇦🇶',
      'AG': '🇦🇬',
      'AR': '🇦🇷',
      'AM': '🇦🇲',
      'AW': '🇦🇼',
      'AU': '🇦🇺',
      'AT': '🇦🇹',
      'AZ': '🇦🇿',
      'BS': '🇧🇸',
      'BH': '🇧🇭',
      'BD': '🇧🇩',
      'BB': '🇧🇧',
      'BY': '🇧🇾',
      'BE': '🇧🇪',
      'BZ': '🇧🇿',
      'BJ': '🇧🇯',
      'BM': '🇧🇲',
      'BT': '🇧🇹',
      'BO': '🇧🇴',
      'BA': '🇧🇦',
      'BW': '🇧🇼',
      'BV': '🇧🇻',
      'BR': '🇧🇷',
      'IO': '🇮🇴',
      'BN': '🇧🇳',
      'BG': '🇧🇬',
      'BF': '🇧🇫',
      'BI': '🇧🇮',
      'KH': '🇰🇭',
      'CM': '🇨🇲',
      'CA': '🇨🇦',
      'CV': '🇨🇻',
      'KY': '🇰🇾',
      'CF': '🇨🇫',
      'TD': '🇹🇩',
      'CL': '🇨🇱',
      'CN': '🇨🇳',
      'CX': '🇨🇽',
      'CC': '🇨🇨',
      'CO': '🇨🇴',
      'KM': '🇰🇲',
      'CG': '🇨🇬',
      'CD': '🇨🇩',
      'CK': '🇨🇰',
      'CR': '🇨🇷',
      'CI': '🇨🇮',
      'HR': '🇭🇷',
      'CU': '🇨🇺',
      'CY': '🇨🇾',
      'CZ': '🇨🇿',
      'DK': '🇩🇰',
      'DJ': '🇩🇯',
      'DM': '🇩🇲',
      'DO': '🇩🇴',
      'EC': '🇪🇨',
      'EG': '🇪🇬',
      'SV': '🇸🇻',
      'GQ': '🇬🇶',
      'ER': '🇪🇷',
      'EE': '🇪🇪',
      'ET': '🇪🇹',
      'FK': '🇫🇰',
      'FO': '🇫🇴',
      'FJ': '🇫🇯',
      'FI': '🇫🇮',
      'FR': '🇫🇷',
      'GF': '🇬🇫',
      'PF': '🇵🇫',
      'TF': '🇹🇫',
      'GA': '🇬🇦',
      'GM': '🇬🇲',
      'GE': '🇬🇪',
      'DE': '🇩🇪',
      'GH': '🇬🇭',
      'GI': '🇬🇮',
      'GR': '🇬🇷',
      'GL': '🇬🇱',
      'GD': '🇬🇩',
      'GP': '🇬🇵',
      'GU': '🇬🇺',
      'GT': '🇬🇹',
      'GG': '🇬🇬',
      'GN': '🇬🇳',
      'GW': '🇬🇼',
      'GY': '🇬🇾',
      'HT': '🇭🇹',
      'HM': '🇭🇲',
      'VA': '🇻🇦',
      'HN': '🇭🇳',
      'HK': '🇭🇰',
      'HU': '🇭🇺',
      'IS': '🇮🇸',
      'IN': '🇮🇳',
      'ID': '🇮🇩',
      'IR': '🇮🇷',
      'IQ': '🇮🇶',
      'IE': '🇮🇪',
      'IM': '🇮🇲',
      'IL': '🇮🇱',
      'IT': '🇮🇹',
      'JM': '🇯🇲',
      'JP': '🇯🇵',
      'JE': '🇯🇪',
      'JO': '🇯🇴',
      'KZ': '🇰🇿',
      'KE': '🇰🇪',
      'KI': '🇰🇮',
      'KP': '🇰🇵',
      'KR': '🇰🇷',
      'KW': '🇰🇼',
      'KG': '🇰🇬',
      'LA': '🇱🇦',
      'LV': '🇱🇻',
      'LB': '🇱🇧',
      'LS': '🇱🇸',
      'LR': '🇱🇷',
      'LY': '🇱🇾',
      'LI': '🇱🇮',
      'LT': '🇱🇹',
      'LU': '🇱🇺',
      'MO': '🇲🇴',
      'MK': '🇲🇰',
      'MG': '🇲🇬',
      'MW': '🇲🇼',
      'MY': '🇲🇾',
      'MV': '🇲🇻',
      'ML': '🇲🇱',
      'MT': '🇲🇹',
      'MH': '🇲🇭',
      'MQ': '🇲🇶',
      'MR': '🇲🇷',
      'MU': '🇲🇺',
      'YT': '🇾🇹',
      'MX': '🇲🇽',
      'FM': '🇫🇲',
      'MD': '🇲🇩',
      'MC': '🇲🇨',
      'MN': '🇲🇳',
      'ME': '🇲🇪',
      'MS': '🇲🇸',
      'MA': '🇲🇦',
      'MZ': '🇲🇿',
      'MM': '🇲🇲',
      'NA': '🇳🇦',
      'NR': '🇳🇷',
      'NP': '🇳🇵',
      'NL': '🇳🇱',
      'NC': '🇳🇨',
      'NZ': '🇳🇿',
      'NI': '🇳🇮',
      'NE': '🇳🇪',
      'NG': '🇳🇬',
      'NU': '🇳🇺',
      'NF': '🇳🇫',
      'MP': '🇲🇵',
      'NO': '🇳🇴',
      'OM': '🇴🇲',
      'PK': '🇵🇰',
      'PW': '🇵🇼',
      'PS': '🇵🇸',
      'PA': '🇵🇦',
      'PG': '🇵🇬',
      'PY': '🇵🇾',
      'PE': '🇵🇪',
      'PH': '🇵🇭',
      'PN': '🇵🇳',
      'PL': '🇵🇱',
      'PT': '🇵🇹',
      'PR': '🇵🇷',
      'QA': '🇶🇦',
      'RE': '🇷🇪',
      'RO': '🇷🇴',
      'RU': '🇷🇺',
      'RW': '🇷🇼',
      'BL': '🇧🇱',
      'SH': '🇸🇭',
      'KN': '🇰🇳',
      'LC': '🇱🇨',
      'MF': '🇲🇫',
      'PM': '🇵🇲',
      'VC': '🇻🇨',
      'WS': '🇼🇸',
      'SM': '🇸🇲',
      'ST': '🇸🇹',
      'SA': '🇸🇦',
      'SN': '🇸🇳',
      'RS': '🇷🇸',
      'SC': '🇸🇨',
      'SL': '🇸🇱',
      'SG': '🇸🇬',
      'SX': '🇸🇽',
      'SK': '🇸🇰',
      'SI': '🇸🇮',
      'SB': '🇸🇧',
      'SO': '🇸🇴',
      'ZA': '🇿🇦',
      'GS': '🇬🇸',
      'SS': '🇸🇸',
      'ES': '🇪🇸',
      'LK': '🇱🇰',
      'SD': '🇸🇩',
      'SR': '🇸🇷',
      'SJ': '🇸🇯',
      'SZ': '🇸🇿',
      'SE': '🇸🇪',
      'CH': '🇨🇭',
      'SY': '🇸🇾',
      'TW': '🇹🇼',
      'TJ': '🇹🇯',
      'TZ': '🇹🇿',
      'TH': '🇹🇭',
      'TL': '🇹🇱',
      'TG': '🇹🇬',
      'TK': '🇹🇰',
      'TO': '🇹🇴',
      'TT': '🇹🇹',
      'TN': '🇹🇳',
      'TR': '🇹🇷',
      'TM': '🇹🇲',
      'TC': '🇹🇨',
      'TV': '🇹🇻',
      'UG': '🇺🇬',
      'UA': '🇺🇦',
      'AE': '🇦🇪',
      'GB': '🇬🇧',
      'UK': '🇬🇧',
      'US': '🇺🇸',
      'UM': '🇺🇲',
      'UY': '🇺🇾',
      'UZ': '🇺🇿',
      'VU': '🇻🇺',
      'VE': '🇻🇪',
      'VN': '🇻🇳',
      'VG': '🇻🇬',
      'VI': '🇻🇮',
      'WF': '🇼🇫',
      'EH': '🇪🇭',
      'YE': '🇾🇪',
      'ZM': '🇿🇲',
      'ZW': '🇿🇼',
    };
    return flags[countryCode] ?? '🌍';
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      // Also save as 'city' so the restored object looks identical to an API
      // response, enabling fromJson() to deserialise it correctly.
      'city': name,
      'ip': ip,
      'country': country,
      'country_code': countryCode,
      'flag': flag,
      // Save under both key names so fromJson() (which checks both) works
      // regardless of where the JSON came from.
      'premium': premium,
      'is_premium': premium,
      'latency': latency,
      'config_url': configUrl,
      'is_active': isActive,
      'load': load,
      'capacity': capacity,
      'load_percentage': loadPercentage,
      'is_full': isFull,
      'protocol': protocol,
      'tcp_port': tcpPort,
      'udp_port': udpPort,
      'port': port,
      'vpn_username': vpnUsername,
      'vpn_password': vpnPassword,
      'use_file': useFile,
      'free_connect_duration': freeConnectDuration,
      'connected_devices': connectedDevices,
      'order': order,
      'protocols': protocols,
      'vpn_protocol_type': vpnProtocolType,
    };
  }

  /// Get all supported protocol types for display
  List<String> get supportedProtocolTypes {
    final types = <String>[];

    if (supportsOpenVPN) {
      types.add('OpenVPN');
    }

    if (supportsWireGuard) {
      types.add('WireGuard');
    }

    return types.isEmpty ? ['OpenVPN'] : types; // Default to OpenVPN
  }
}

class AppSettings {
  final String appName;
  final String appVersion;
  final bool forceUpdate;
  final String updateUrl;
  final bool maintenanceMode;
  final String maintenanceMessage;

  AppSettings({
    required this.appName,
    required this.appVersion,
    required this.forceUpdate,
    required this.updateUrl,
    required this.maintenanceMode,
    required this.maintenanceMessage,
  });

  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      appName: json['app_name'] ?? 'VPN MASTER',
      appVersion: json['app_version'] ?? '3.0.0',
      forceUpdate: json['force_update'] == true,
      updateUrl: json['update_url'] ?? '',
      maintenanceMode: json['maintenance_mode'] == true,
      maintenanceMessage: json['maintenance_message'] ?? '',
    );
  }
}

class AdMobConfig {
  final String bannerAndroid;
  final String bannerIos;
  final String interstitialAndroid;
  final String interstitialIos;
  final String rewardedAndroid;
  final String rewardedIos;
  final String nativeAndroid;
  final String nativeIos;
  final String appOpenAndroid;
  final String appOpenIos;

  AdMobConfig({
    required this.bannerAndroid,
    required this.bannerIos,
    required this.interstitialAndroid,
    required this.interstitialIos,
    required this.rewardedAndroid,
    required this.rewardedIos,
    required this.nativeAndroid,
    required this.nativeIos,
    required this.appOpenAndroid,
    required this.appOpenIos,
  });

  factory AdMobConfig.fromJson(Map<String, dynamic> json) {
    return AdMobConfig(
      // Map the actual API response keys to our expected format
      bannerAndroid: json['abi'] ?? '', // Android Banner ID
      bannerIos: json['ibi'] ?? '', // iOS Banner ID
      interstitialAndroid: json['aii'] ?? '', // Android Interstitial ID
      interstitialIos: json['iii'] ?? '', // iOS Interstitial ID
      rewardedAndroid: json['ari'] ?? '', // Android Rewarded ID
      rewardedIos: json['iri'] ?? '', // iOS Rewarded ID
      nativeAndroid: json['ani'] ?? '', // Android Native ID
      nativeIos: json['ini'] ?? '', // iOS Native ID
      appOpenAndroid: json['aai'] ?? '', // Android App Open ID
      appOpenIos: json['iai'] ?? '', // iOS App Open ID
    );
  }
}

class PurchasePlan {
  final String id;
  final String name;
  final double price;
  final String currency;
  final String period;
  final int? durationDays;
  final String? discount;
  final int discountPercentage;
  final double? originalPrice;
  final double? savings;
  final List<String> features;
  final bool isPopular;
  final int sortOrder;
  final String formattedPrice;
  final String? formattedOriginalPrice;
  final String? formattedSavings;

  PurchasePlan({
    required this.id,
    required this.name,
    required this.price,
    required this.currency,
    required this.period,
    this.durationDays,
    this.discount,
    required this.discountPercentage,
    this.originalPrice,
    this.savings,
    required this.features,
    required this.isPopular,
    required this.sortOrder,
    required this.formattedPrice,
    this.formattedOriginalPrice,
    this.formattedSavings,
  });

  factory PurchasePlan.fromJson(Map<String, dynamic> json) {
    // Parse price safely - handle both string and number
    double price = 0.0;
    if (json['price'] is String) {
      price = double.tryParse(json['price'] as String) ?? 0.0;
    } else if (json['price'] is num) {
      price = (json['price'] as num).toDouble();
    }

    return PurchasePlan(
      id: json['id'] ?? '',
      name: json['name'] ?? '',
      price: price,
      currency: json['currency'] ?? 'USD',
      period: json['period'] ?? '',
      durationDays: json['duration_days'],
      discount: json['discount'],
      discountPercentage: json['discount_percentage'] ?? 0,
      originalPrice: json['original_price']?.toDouble(),
      savings: json['savings']?.toDouble(),
      features: List<String>.from(json['features'] ?? []),
      isPopular:
          (json['is_popular'] == true ||
          json['is_popular'] == 1), // Handle both boolean and integer
      sortOrder: json['sort_order'] ?? 0,
      formattedPrice: json['formatted_price'] ?? '',
      formattedOriginalPrice: json['formatted_original_price'],
      formattedSavings: json['formatted_savings'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'price': price,
      'currency': currency,
      'period': period,
      'duration_days': durationDays,
      'discount': discount,
      'discount_percentage': discountPercentage,
      'original_price': originalPrice,
      'savings': savings,
      'features': features,
      'is_popular': isPopular,
      'sort_order': sortOrder,
      'formatted_price': formattedPrice,
      'formatted_original_price': formattedOriginalPrice,
      'formatted_savings': formattedSavings,
    };
  }
}
