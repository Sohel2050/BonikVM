import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class VpnDebugService {
  static final VpnDebugService _instance = VpnDebugService._internal();
  factory VpnDebugService() => _instance;
  VpnDebugService._internal();

  static VpnDebugService get instance => _instance;

  static const String _logKey = 'vpn_debug_logs';
  List<String> _logs = [];

  /// Add a debug log entry
  void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final logEntry = '[$timestamp] $message';
    _logs.add(logEntry);


    // Keep only last 1000 logs to prevent memory issues
    if (_logs.length > 1000) {
      _logs = _logs.sublist(_logs.length - 1000);
    }

    // Save to persistent storage
    _saveLogs();
  }

  /// Save logs to persistent storage
  Future<void> _saveLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_logKey, _logs);
    } catch (e) {

    }
  }

  /// Load logs from persistent storage
  Future<void> loadLogs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _logs = prefs.getStringList(_logKey) ?? [];
    } catch (e) {

    }
  }

  /// Get all logs
  List<String> getLogs() => List.from(_logs);

  /// Clear all logs
  Future<void> clearLogs() async {
    _logs.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_logKey);
    } catch (e) {

    }
  }

  /// Get logs as a formatted string
  String getLogsAsString() {
    return _logs.join('\n');
  }

  /// Check build configuration and log important details
  Future<void> logBuildConfig() async {
    log('=== BUILD CONFIGURATION ===');
    log(
      'Build Mode: ${kDebugMode ? 'DEBUG' : (kProfileMode ? 'PROFILE' : 'RELEASE')}',
    );
    log('Platform: ${Platform.operatingSystem}');
    log('Platform Version: ${Platform.operatingSystemVersion}');

    if (Platform.isAndroid) {
      log('Android Build: App Bundle optimized');
    }

    log('Dart Version: ${Platform.version}');
    log(
      'Environment: ${Platform.environment['FLUTTER_ROOT'] != null ? 'Flutter' : 'Standalone'}',
    );
  }

  /// Log OpenVPN plugin status
  void logOpenVpnStatus(String status) {
    log('OpenVPN Plugin: $status');
  }

  /// Log VPN configuration details
  void logVpnConfig(
    String serverId,
    String serverName,
    int configLength,
    bool hasCertificates,
  ) {
    log('=== VPN CONFIG ===');
    log('Server ID: $serverId');
    log('Server Name: $serverName');
    log('Config Length: $configLength chars');
    log('Has Certificates: $hasCertificates');
  }

  /// Log connection attempt
  void logConnectionAttempt(String serverIp, int port, String protocol) {
    log('=== CONNECTION ATTEMPT ===');
    log('Server: $serverIp:$port');
    log('Protocol: $protocol');
    log('Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log connection result
  void logConnectionResult(String result, String? error) {
    log('=== CONNECTION RESULT ===');
    log('Result: $result');
    if (error != null) {
      log('Error: $error');
    }
    log('Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log VPN state changes
  void logStateChange(String fromState, String toState, String reason) {
    log('=== STATE CHANGE ===');
    log('From: $fromState');
    log('To: $toState');
    log('Reason: $reason');
    log('Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log App Bundle vs Debug comparison
  void logAppBundleComparison(String operation, bool success, String details) {
    final buildType = kDebugMode ? 'DEBUG' : 'RELEASE';
    final isAppBundle = !kDebugMode && kReleaseMode;

    log('=== APP BUNDLE COMPARISON ===');
    log('Operation: $operation');
    log('Build Type: $buildType');
    log('Is App Bundle: $isAppBundle');
    log('Success: $success');
    log('Details: $details');
    log('Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log specific failure analysis
  void logFailureAnalysis(
    String component,
    String expectedBehavior,
    String actualBehavior,
    String possibleCause,
  ) {
    log('=== FAILURE ANALYSIS ===');
    log('Component: $component');
    log('Expected: $expectedBehavior');
    log('Actual: $actualBehavior');
    log('Possible Cause: $possibleCause');
    log('Build Type: ${kDebugMode ? 'DEBUG' : 'RELEASE'}');
    log('Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Log critical diagnostic information
  void logCriticalInfo(String category, Map<String, dynamic> data) {
    log('=== CRITICAL INFO: $category ===');
    data.forEach((key, value) {
      log('$key: $value');
    });
    log('Timestamp: ${DateTime.now().toIso8601String()}');
  }

  /// Export logs for debugging
  Future<String> exportLogs() async {
    await logBuildConfig();

    final buffer = StringBuffer();
    buffer.writeln('=== VPN MASTER DEBUG LOGS ===');
    buffer.writeln('Export Time: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Total Logs: ${_logs.length}');
    buffer.writeln();

    for (final log in _logs) {
      buffer.writeln(log);
    }

    return buffer.toString();
  }
}

