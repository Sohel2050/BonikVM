import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// Service to cache API responses and prevent excessive API calls
class ApiCacheService {
  static final ApiCacheService _instance = ApiCacheService._internal();
  factory ApiCacheService() => _instance;
  ApiCacheService._internal();

  static const Duration _defaultCacheExpiry = Duration(minutes: 5);
  static const String _cachePrefix = 'api_cache_';
  static const String _timestampSuffix = '_timestamp';

  /// Cache an API response with timestamp
  Future<void> cacheResponse(String key, Map<String, dynamic> data) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = jsonEncode(data);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      
      await prefs.setString('$_cachePrefix$key', jsonString);
      await prefs.setInt('$_cachePrefix$key$_timestampSuffix', timestamp);
      

    } catch (e) {

    }
  }

  /// Get cached response if still valid
  Future<Map<String, dynamic>?> getCachedResponse(
    String key, {
    Duration? maxAge,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('$_cachePrefix$key');
      final timestamp = prefs.getInt('$_cachePrefix$key$_timestampSuffix');
      
      if (jsonString == null || timestamp == null) {

        return null;
      }
      
      final age = DateTime.now().millisecondsSinceEpoch - timestamp;
      final maxAgeMs = (maxAge ?? _defaultCacheExpiry).inMilliseconds;
      
      if (age > maxAgeMs) {

        await clearCache(key);
        return null;
      }
      
      final data = jsonDecode(jsonString) as Map<String, dynamic>;

      return data;
    } catch (e) {

      return null;
    }
  }

  /// Clear cache for specific key
  Future<void> clearCache(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_cachePrefix$key');
      await prefs.remove('$_cachePrefix$key$_timestampSuffix');

    } catch (e) {

    }
  }

  /// Clear all API cache
  Future<void> clearAllCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final keys = prefs.getKeys().where((key) => key.startsWith(_cachePrefix));
      
      for (final key in keys) {
        await prefs.remove(key);
      }
      

    } catch (e) {

    }
  }

  /// Check if cache exists and is valid
  Future<bool> isCacheValid(String key, {Duration? maxAge}) async {
    final cached = await getCachedResponse(key, maxAge: maxAge);
    return cached != null;
  }
}

