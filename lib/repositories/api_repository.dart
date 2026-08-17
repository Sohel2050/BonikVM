import 'package:dio/dio.dart';
import '../models/user_model.dart';
import '../core/config/app_config.dart';

class ApiRepository {
  late final Dio _dio;
  final String baseUrl;

  ApiRepository({String? baseUrl}) : baseUrl = baseUrl ?? AppConfig.apiBaseUrl {
    _initializeDio();
  }

  void _initializeDio() {
    _dio = Dio(
      BaseOptions(
        baseUrl:
            baseUrl, // Use base URL directly since endpoints will include /api/${AppConfig.apiVersion}
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 30),
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'X-API-Token': AppConfig.apiKey,
        },
      ),
    );

    // Add interceptors
    _dio.interceptors.add(
      LogInterceptor(
        requestBody: true,
        responseBody: true,
        requestHeader: true,
        responseHeader: true,
        logPrint: (message) {},
      ),
    );

    // Add error interceptor
    _dio.interceptors.add(
      InterceptorsWrapper(
        onError: (error, handler) {
          handler.next(error);
        },
      ),
    );
  }

  /// Set authentication token
  void setAuthToken(String token) {
    _dio.options.headers['Authorization'] = 'Bearer $token';
  }

  /// Clear authentication token
  void clearAuthToken() {
    _dio.options.headers.remove('Authorization');
  }

  /// Sync user with backend
  Future<Map<String, dynamic>> syncUser(UserModel user) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/auth/sync',
        data: user.toMap(),
      );
      return response.data;
    } catch (e) {
      if (e is DioException) {}
      throw _handleError(e);
    }
  }

  /// Delete user from backend
  Future<void> deleteUser(String userId) async {
    try {
      await _dio.delete('/api/${AppConfig.apiVersion}/user/account/$userId');
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Restore purchases for user
  Future<Map<String, dynamic>> restorePurchases(String userId) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/purchases/restore',
        data: {'user_id': userId},
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Verify purchase receipt
  Future<Map<String, dynamic>> verifyPurchase({
    required String userId,
    required String productId,
    required String transactionId,
    required String receiptData,
    required String platform,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/purchase/verify',
        data: {
          'user_id': userId,
          'product_id': productId,
          'transaction_id': transactionId,
          'receipt_data': receiptData,
          'platform': platform,
        },
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get user subscriptions
  Future<List<Map<String, dynamic>>> getUserSubscriptions(String userId) async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/purchases/subscriptions/$userId',
      );
      return List<Map<String, dynamic>>.from(
        response.data['subscriptions'] ?? [],
      );
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get user payment transactions (purchase history)
  Future<List<Map<String, dynamic>>> getUserTransactions() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/payments/transactions',
      );

      // Handle the updated response structure
      if (response.data['success'] == true && response.data['data'] != null) {
        if (response.data['data']['transactions'] != null) {
          return List<Map<String, dynamic>>.from(
            response.data['data']['transactions'],
          );
        } else if (response.data['data'] is List) {
          return List<Map<String, dynamic>>.from(response.data['data']);
        }
      } else if (response.data is List) {
        return List<Map<String, dynamic>>.from(response.data);
      }

      return [];
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get product prices
  Future<Map<String, dynamic>> getProductPrices() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/purchases/prices',
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Cancel subscription
  Future<Map<String, dynamic>> cancelSubscription({
    required String userId,
    required String productId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/purchases/cancel',
        data: {'user_id': userId, 'product_id': productId},
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get user profile
  Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/auth/profile/$userId',
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Update user profile
  Future<Map<String, dynamic>> updateUserProfile(
    String userId,
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _dio.put(
        '/api/${AppConfig.apiVersion}/auth/profile/$userId',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Check subscription status
  Future<Map<String, dynamic>> checkSubscriptionStatus(String userId) async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/subscription/status',
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Report issue
  Future<Map<String, dynamic>> reportIssue({
    required String userId,
    required String subject,
    required String description,
    String? category,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/support/issue',
        data: {
          'user_id': userId,
          'subject': subject,
          'description': description,
          'category': category,
        },
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get VPN servers
  Future<List<Map<String, dynamic>>> getVpnServers() async {
    try {
      final response = await _dio.get('/api/${AppConfig.apiVersion}/list');
      return List<Map<String, dynamic>>.from(response.data['servers'] ?? []);
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get user connection stats
  Future<Map<String, dynamic>> getUserStats(String userId) async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/auth/stats/$userId',
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Register FCM token for push notifications
  Future<Map<String, dynamic>> registerFcmToken({
    required String userId,
    required String deviceToken,
    required String deviceType,
    required String deviceId,
    String? appVersion,
  }) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/notifications/register-token',
        data: {
          'user_id': userId,
          'device_token': deviceToken,
          'device_type': deviceType,
          'device_id': deviceId,
          'app_version': appVersion,
        },
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Cancel subscription by ID
  Future<Map<String, dynamic>> cancelSubscriptionById(
    String userId,
    int subscriptionId,
  ) async {
    try {
      final response = await _dio.post(
        '/api/${AppConfig.apiVersion}/payments/cancel-subscription',
        data: {'user_id': userId, 'subscription_id': subscriptionId},
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Get app configuration
  Future<Map<String, dynamic>> getAppConfig() async {
    try {
      final response = await _dio.get(
        '/api/${AppConfig.apiVersion}/app/config',
      );
      return response.data;
    } catch (e) {
      throw _handleError(e);
    }
  }

  /// Handle API errors
  Exception _handleError(dynamic error) {
    if (error is DioException) {
      switch (error.type) {
        case DioExceptionType.connectionTimeout:
        case DioExceptionType.sendTimeout:
        case DioExceptionType.receiveTimeout:
          return Exception(
            'Connection timeout. Please check your internet connection.',
          );
        case DioExceptionType.badResponse:
          final statusCode = error.response?.statusCode;
          final message =
              error.response?.data?['message'] ?? 'Server error occurred';
          return Exception('Server error ($statusCode): $message');
        case DioExceptionType.cancel:
          return Exception('Request was cancelled');
        case DioExceptionType.connectionError:
          return Exception(
            'No internet connection. Please check your network.',
          );
        default:
          return Exception('An unexpected error occurred: ${error.message}');
      }
    }
    return Exception('An unexpected error occurred: $error');
  }
}
