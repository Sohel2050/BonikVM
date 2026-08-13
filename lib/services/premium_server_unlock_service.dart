import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api/api_service.dart';

/// Information about a temporarily unlocked premium server.
class UnlockedPremiumServer {
  final int? serverId;
  final String? serverName;
  final DateTime unlockedUntil;
  final String unlockedBy; // 'ad' or 'subscription'

  UnlockedPremiumServer({
    required this.serverId,
    required this.serverName,
    required this.unlockedUntil,
    required this.unlockedBy,
  });

  /// Whether the unlock is still valid.
  bool get isStillUnlocked {
    return DateTime.now().isBefore(unlockedUntil);
  }

  /// Remaining unlock duration.
  Duration get remainingTime {
    if (!isStillUnlocked) {
      return Duration.zero;
    }

    final duration = unlockedUntil.difference(DateTime.now());

    if (duration.isNegative) {
      return Duration.zero;
    }

    return duration;
  }

  /// Remaining seconds.
  int get remainingSeconds {
    return remainingTime.inSeconds;
  }

  Map<String, dynamic> toJson() {
    return {
      'server_id': serverId,
      'server_name': serverName,
      'unlocked_until': unlockedUntil.toIso8601String(),
      'unlocked_by': unlockedBy,
    };
  }

  factory UnlockedPremiumServer.fromJson(
      Map<String, dynamic> json,
      ) {
    final unlockedUntilString = json['unlocked_until']?.toString();

    if (unlockedUntilString == null || unlockedUntilString.isEmpty) {
      throw const FormatException(
        'Missing unlocked_until',
      );
    }

    final unlockedUntil = DateTime.parse(
      unlockedUntilString,
    );

    int? parsedServerId;

    final rawServerId = json['server_id'];

    if (rawServerId is int) {
      parsedServerId = rawServerId;
    } else if (rawServerId != null) {
      parsedServerId = int.tryParse(
        rawServerId.toString(),
      );
    }

    return UnlockedPremiumServer(
      serverId: parsedServerId,
      serverName: json['server_name']?.toString(),
      unlockedUntil: unlockedUntil,
      unlockedBy: json['unlocked_by']?.toString() ?? 'ad',
    );
  }
}

/// Service responsible for temporarily unlocking premium servers.
///
/// Supports:
/// - Reward ad unlock
/// - Subscription unlock
/// - SharedPreferences persistence
/// - App restart persistence
/// - String / int server IDs
/// - Automatic expired unlock cleanup
/// - Safe concurrent initialization
class PremiumServerUnlockService {
  PremiumServerUnlockService._internal();

  static final PremiumServerUnlockService _instance =
  PremiumServerUnlockService._internal();

  factory PremiumServerUnlockService() {
    return _instance;
  }

  static const String _storageKey = 'premium_server_unlocks';

  /// In-memory unlocked servers.
  ///
  /// Key is ALWAYS String.
  final Map<String, UnlockedPremiumServer> _unlockedServers = {};

  bool _initialized = false;

  /// Prevents multiple simultaneous initialization operations.
  Future<void>? _initFuture;

  /// Prevents simultaneous writes to SharedPreferences.
  Future<void> _saveQueue = Future<void>.value();

  // ---------------------------------------------------------------------------
  // INITIALIZATION
  // ---------------------------------------------------------------------------

  /// Initialize service and load saved unlocks.
  ///
  /// Safe to call multiple times.
  Future<void> initialize() {
    debugPrint(
      '\n🔄 PremiumServerUnlockService.initialize()',
    );

    if (_initialized) {
      debugPrint(
        '   ✅ Already initialized',
      );
      return Future<void>.value();
    }

    if (_initFuture != null) {
      debugPrint(
        '   ⏳ Initialization already running. Waiting...',
      );

      return _initFuture!;
    }

    _initFuture = _doInitialize();

    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    try {
      debugPrint(
        '   📦 Loading premium unlocks...',
      );

      final prefs = await SharedPreferences.getInstance();

      final savedData = prefs.getString(_storageKey);

      debugPrint(
        '   📦 Storage key: $_storageKey',
      );

      debugPrint(
        '   📦 Saved data exists: ${savedData != null}',
      );

      if (savedData == null || savedData.isEmpty) {
        debugPrint(
          '   📦 No saved unlock data.',
        );

        _initialized = true;
        return;
      }

      debugPrint(
        '   📦 Saved data length: ${savedData.length}',
      );

      try {
        final decoded = jsonDecode(savedData);

        if (decoded is! Map) {
          throw const FormatException(
            'Saved unlock data is not a JSON object',
          );
        }

        _unlockedServers.clear();

        int loadedCount = 0;
        int expiredCount = 0;
        int invalidCount = 0;

        for (final entry in decoded.entries) {
          final key = entry.key.toString();
          final value = entry.value;

          try {
            if (value is! Map) {
              invalidCount++;

              debugPrint(
                '   ❌ Invalid unlock data for key: $key',
              );

              continue;
            }

            final unlock =
            UnlockedPremiumServer.fromJson(
              Map<String, dynamic>.from(value),
            );

            if (unlock.isStillUnlocked) {
              _unlockedServers[key] = unlock;

              loadedCount++;

              debugPrint(
                '   ✅ Loaded server [$key]',
              );

              debugPrint(
                '      Name: ${unlock.serverName}',
              );

              debugPrint(
                '      Until: ${unlock.unlockedUntil.toLocal()}',
              );

              debugPrint(
                '      Remaining: ${unlock.remainingSeconds}s',
              );

              debugPrint(
                '      By: ${unlock.unlockedBy}',
              );
            } else {
              expiredCount++;

              debugPrint(
                '   ⏰ Expired server [$key]',
              );
            }
          } catch (e) {
            invalidCount++;

            debugPrint(
              '   ❌ Failed to parse unlock [$key]: $e',
            );
          }
        }

        debugPrint(
          '   📊 Load result:',
        );

        debugPrint(
          '      Loaded: $loadedCount',
        );

        debugPrint(
          '      Expired: $expiredCount',
        );

        debugPrint(
          '      Invalid: $invalidCount',
        );

        debugPrint(
          '      Active: ${_unlockedServers.length}',
        );

        // Remove expired/invalid data from storage.
        if (expiredCount > 0 || invalidCount > 0) {
          await _saveUnlocksToStorage();
        }
      } catch (e, st) {
        debugPrint(
          '   ❌ JSON decode error: $e',
        );

        debugPrint(
          '   Stack trace: $st',
        );

        // Do not crash the app because stored data is corrupted.
        _unlockedServers.clear();
      }

      // Important:
      // Set initialized ONLY after loading is complete.
      _initialized = true;

      debugPrint(
        '   ✅ PremiumServerUnlockService initialized.',
      );

      debugPrint(
        '   🔑 Active server IDs: '
            '${_unlockedServers.keys.toList()}',
      );
    } catch (e, st) {
      debugPrint(
        '❌ PremiumServerUnlockService initialization failed: $e',
      );

      debugPrint(
        '   Stack trace: $st',
      );

      // Allow next call to retry initialization.
      _initialized = false;
    } finally {
      _initFuture = null;
    }
  }

  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  // ---------------------------------------------------------------------------
  // SERVER ID
  // ---------------------------------------------------------------------------

  /// Converts any supported server value into a String ID.
  String? _extractServerId(dynamic server) {
    if (server == null) {
      return null;
    }

    if (server is String) {
      final value = server.trim();

      return value.isEmpty ? null : value;
    }

    if (server is int) {
      return server.toString();
    }

    if (server is VpnServer) {
      final id = server.id;

      if (id == null) {
        return null;
      }

      final value = id.toString().trim();

      return value.isEmpty ? null : value;
    }

    if (server is Map) {
      final id = server['id'];

      if (id == null) {
        return null;
      }

      final value = id.toString().trim();

      return value.isEmpty ? null : value;
    }

    // Last-resort support for objects exposing an id getter.
    try {
      final dynamic id = server.id;

      if (id == null) {
        return null;
      }

      final value = id.toString().trim();

      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  /// Extract server name safely.
  String _extractServerName(dynamic server) {
    if (server == null) {
      return 'Premium Server';
    }

    if (server is String) {
      return server.trim().isEmpty
          ? 'Premium Server'
          : server.trim();
    }

    if (server is VpnServer) {
      final name = server.name;

      return name?.toString().trim().isNotEmpty == true
          ? name.toString()
          : 'Premium Server';
    }

    if (server is Map) {
      final name = server['name'];

      return name?.toString().trim().isNotEmpty == true
          ? name.toString()
          : 'Premium Server';
    }

    try {
      final dynamic name = server.name;

      return name?.toString().trim().isNotEmpty == true
          ? name.toString()
          : 'Premium Server';
    } catch (_) {
      return 'Premium Server';
    }
  }

  // ---------------------------------------------------------------------------
  // UNLOCK
  // ---------------------------------------------------------------------------

  /// Unlock a premium server for [durationMinutes].
  Future<bool> unlockPremiumServer({
    required dynamic server,
    required int durationMinutes,
    required String unlockedBy,
  }) async {
    debugPrint(
      '\n🔓 unlockPremiumServer() called',
    );

    debugPrint(
      '   Duration: $durationMinutes minutes',
    );

    debugPrint(
      '   Unlocked by: $unlockedBy',
    );

    await _ensureInitialized();

    if (durationMinutes <= 0) {
      debugPrint(
        '   ❌ Invalid duration: $durationMinutes',
      );

      return false;
    }

    final serverId = _extractServerId(server);

    if (serverId == null) {
      debugPrint(
        '   ❌ Could not extract server ID.',
      );

      debugPrint(
        '   Server: $server',
      );

      return false;
    }

    final serverName = _extractServerName(server);

    final unlockedUntil = DateTime.now().add(
      Duration(minutes: durationMinutes),
    );

    final unlock = UnlockedPremiumServer(
      serverId: int.tryParse(serverId),
      serverName: serverName,
      unlockedUntil: unlockedUntil,
      unlockedBy: unlockedBy,
    );

    // Store in memory first.
    _unlockedServers[serverId] = unlock;

    debugPrint(
      '   ✅ Stored in memory',
    );

    debugPrint(
      '      ID: $serverId',
    );

    debugPrint(
      '      Name: $serverName',
    );

    debugPrint(
      '      Until: ${unlockedUntil.toLocal()}',
    );

    debugPrint(
      '      Remaining: ${unlock.remainingSeconds}s',
    );

    debugPrint(
      '      Total unlocked servers: '
          '${_unlockedServers.length}',
    );

    // Persist.
    final saved = await _saveUnlocksToStorage();

    if (!saved) {
      debugPrint(
        '   ⚠️ Unlock is active in memory, '
            'but storage save failed.',
      );
    }

    return true;
  }

  // ---------------------------------------------------------------------------
  // CHECK UNLOCK
  // ---------------------------------------------------------------------------

  /// Check whether a server is currently unlocked.
  bool isPremiumServerUnlocked(dynamic serverId) {
    try {
      final id = _extractServerId(serverId);

      if (id == null) {
        return false;
      }

      final unlock = _unlockedServers[id];

      if (unlock == null) {
        return false;
      }

      if (!unlock.isStillUnlocked) {
        debugPrint(
          '   ⏰ Unlock expired: $id',
        );

        _unlockedServers.remove(id);

        // Save cleanup asynchronously.
        _saveUnlocksToStorage();

        return false;
      }

      return true;
    } catch (e) {
      debugPrint(
        '❌ Error checking premium unlock: $e',
      );

      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // GET UNLOCK INFO
  // ---------------------------------------------------------------------------

  /// Returns unlock information if the server is currently unlocked.
  UnlockedPremiumServer? getUnlockInfo(
      dynamic serverId,
      ) {
    try {
      final id = _extractServerId(serverId);

      if (id == null) {
        return null;
      }

      final unlock = _unlockedServers[id];

      if (unlock == null) {
        return null;
      }

      if (!unlock.isStillUnlocked) {
        _unlockedServers.remove(id);

        _saveUnlocksToStorage();

        return null;
      }

      return unlock;
    } catch (e) {
      debugPrint(
        '❌ Error getting unlock info: $e',
      );

      return null;
    }
  }

  // ---------------------------------------------------------------------------
  // REMAINING TIME
  // ---------------------------------------------------------------------------

  /// Remaining unlock time in seconds.
  int getRemainingUnlockTime(
      dynamic serverId,
      ) {
    final unlock = getUnlockInfo(serverId);

    return unlock?.remainingSeconds ?? 0;
  }

  /// Remaining unlock time in minutes.
  ///
  /// Uses ceil:
  /// 5.2 minutes => 6 minutes
  /// 0.5 minutes => 1 minute
  int getRemainingMinutes(
      dynamic serverId,
      ) {
    final seconds = getRemainingUnlockTime(serverId);

    if (seconds <= 0) {
      return 0;
    }

    return (seconds / 60).ceil();
  }

  // ---------------------------------------------------------------------------
  // ALL UNLOCKED SERVERS
  // ---------------------------------------------------------------------------

  /// Get all currently unlocked servers.
  Map<String, UnlockedPremiumServer> getAllUnlockedServers() {
    // Remove expired entries.
    final expiredIds = <String>[];

    _unlockedServers.forEach(
          (key, unlock) {
        if (!unlock.isStillUnlocked) {
          expiredIds.add(key);
        }
      },
    );

    if (expiredIds.isNotEmpty) {
      for (final id in expiredIds) {
        _unlockedServers.remove(id);
      }

      // Persist cleanup.
      _saveUnlocksToStorage();
    }

    return Map<String, UnlockedPremiumServer>.from(
      _unlockedServers,
    );
  }

  // ---------------------------------------------------------------------------
  // REMOVE ONE
  // ---------------------------------------------------------------------------

  /// Remove unlock for a specific server.
  Future<bool> removeUnlock(
      dynamic serverId,
      ) async {
    try {
      await _ensureInitialized();

      final id = _extractServerId(serverId);

      if (id == null) {
        debugPrint(
          '   ❌ Invalid server ID for removeUnlock',
        );

        return false;
      }

      final existed = _unlockedServers.remove(id);

      if (existed == null) {
        debugPrint(
          '   ℹ️ No unlock found for server $id',
        );

        return false;
      }

      await _saveUnlocksToStorage();

      debugPrint(
        '   ✅ Removed unlock for server $id',
      );

      return true;
    } catch (e) {
      debugPrint(
        '❌ Error removing unlock: $e',
      );

      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // CLEAR ALL
  // ---------------------------------------------------------------------------

  /// Clear all premium server unlocks.
  Future<bool> clearAllUnlocks() async {
    try {
      await _ensureInitialized();

      _unlockedServers.clear();

      final prefs = await SharedPreferences.getInstance();

      final result = await prefs.remove(
        _storageKey,
      );

      debugPrint(
        '   🗑️ All premium unlocks cleared.',
      );

      debugPrint(
        '   Storage remove result: $result',
      );

      return result;
    } catch (e, st) {
      debugPrint(
        '❌ Error clearing unlocks: $e',
      );

      debugPrint(
        '   Stack trace: $st',
      );

      return false;
    }
  }

  // ---------------------------------------------------------------------------
  // SAVE
  // ---------------------------------------------------------------------------

  /// Save unlocks to SharedPreferences.
  ///
  /// Writes are queued so multiple save operations cannot
  /// overwrite each other unpredictably.
  Future<bool> _saveUnlocksToStorage() {
    final completer = _SaveCompleter();

    _saveQueue = _saveQueue
        .catchError(
          (Object error, StackTrace stackTrace) {
        debugPrint(
          '⚠️ Previous save failed: $error',
        );
      },
    )
        .then(
          (_) async {
        try {
          final result =
          await _performSaveUnlocks();

          completer.complete(result);
        } catch (e, st) {
          debugPrint(
            '❌ Save operation failed: $e',
          );

          debugPrint(
            '   Stack trace: $st',
          );

          completer.complete(false);
        }
      },
    );

    return completer.future;
  }

  Future<bool> _performSaveUnlocks() async {
    debugPrint(
      '\n💾 Saving premium server unlocks...',
    );

    final prefs = await SharedPreferences.getInstance();

    final data = <String, dynamic>{};

    final expiredIds = <String>[];

    _unlockedServers.forEach(
          (serverId, unlock) {
        if (unlock.isStillUnlocked) {
          data[serverId] = unlock.toJson();
        } else {
          expiredIds.add(serverId);
        }
      },
    );

    // Remove expired entries from memory too.
    for (final id in expiredIds) {
      _unlockedServers.remove(id);
    }

    final jsonString = jsonEncode(data);

    debugPrint(
      '   Active unlocks: ${data.length}',
    );

    debugPrint(
      '   Server IDs: ${data.keys.toList()}',
    );

    final saveResult = await prefs.setString(
      _storageKey,
      jsonString,
    );

    debugPrint(
      '   setString result: $saveResult',
    );

    if (!saveResult) {
      debugPrint(
        '   ❌ SharedPreferences setString returned false.',
      );

      return false;
    }

    // Verify immediately.
    final verifyData = prefs.getString(
      _storageKey,
    );

    final verified = verifyData == jsonString;

    debugPrint(
      '   🔎 Verification: '
          '${verified ? "SUCCESS" : "FAILED"}',
    );

    if (!verified) {
      debugPrint(
        '   Expected length: ${jsonString.length}',
      );

      debugPrint(
        '   Actual length: ${verifyData?.length ?? 0}',
      );
    }

    if (verified) {
      debugPrint(
        '   ✅ Premium unlocks saved successfully.',
      );
    }

    return verified;
  }

  // ---------------------------------------------------------------------------
  // DEBUG / UTILITY
  // ---------------------------------------------------------------------------

  /// Returns number of currently active unlocked servers.
  int get unlockedServerCount {
    return getAllUnlockedServers().length;
  }

  /// Returns whether service has finished initialization.
  bool get isInitialized {
    return _initialized;
  }

  /// Debug information.
  void debugPrintStatus() {
    debugPrint(
      '\n================ PREMIUM UNLOCK STATUS ================',
    );

    debugPrint(
      'Initialized: $_initialized',
    );

    debugPrint(
      'Active servers: ${_unlockedServers.length}',
    );

    if (_unlockedServers.isEmpty) {
      debugPrint(
        'No premium servers currently unlocked.',
      );
    } else {
      _unlockedServers.forEach(
            (id, unlock) {
          debugPrint(
            'Server ID: $id',
          );

          debugPrint(
            '  Name: ${unlock.serverName}',
          );

          debugPrint(
            '  Until: ${unlock.unlockedUntil.toLocal()}',
          );

          debugPrint(
            '  Remaining: ${unlock.remainingSeconds}s',
          );

          debugPrint(
            '  By: ${unlock.unlockedBy}',
          );

          debugPrint(
            '  Active: ${unlock.isStillUnlocked}',
          );
        },
      );
    }

    debugPrint(
      '========================================================\n',
    );
  }
}

/// Small helper used to return the result of a queued save.
class _SaveCompleter {
  final Completer<bool> _completer =
  Completer<bool>();

  Future<bool> get future => _completer.future;

  void complete(bool value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }
}