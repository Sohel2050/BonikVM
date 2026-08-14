import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import '../core/api/api_service.dart'; // For VpnServer type

/// Model for temporarily unlocked premium server
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

  bool get isStillUnlocked => DateTime.now().isBefore(unlockedUntil);

  Duration get remainingTime {
    if (!isStillUnlocked) return Duration.zero;
    return unlockedUntil.difference(DateTime.now());
  }

  int get remainingSeconds => remainingTime.inSeconds;

  Map<String, dynamic> toJson() {
    return {
      'server_id': serverId,
      'server_name': serverName,
      'unlocked_until': unlockedUntil.toIso8601String(),
      'unlocked_by': unlockedBy,
    };
  }

  factory UnlockedPremiumServer.fromJson(Map<String, dynamic> json) {
    return UnlockedPremiumServer(
      serverId: json['server_id'],
      serverName: json['server_name'],
      unlockedUntil: DateTime.parse(json['unlocked_until']),
      unlockedBy: json['unlocked_by'] ?? 'ad',
    );
  }
}

/// Service to manage premium server unlocks via ads
class PremiumServerUnlockService {
  static final PremiumServerUnlockService _instance =
      PremiumServerUnlockService._internal();

  factory PremiumServerUnlockService() => _instance;
  PremiumServerUnlockService._internal();

  // Cache of unlocked servers - KEY IS STRING (server.id is String)
  final Map<String, UnlockedPremiumServer> _unlockedServers = {};
  static const String _storageKey = 'premium_server_unlocks';
  bool _initialized = false;
  // Cached future so concurrent callers all await the same load operation
  // instead of the second caller returning early with empty data.
  Future<void>? _initFuture;

  /// Initialize - load saved unlocks from storage.
  /// Safe to call multiple times and from concurrent callers.
  Future<void> initialize() async {
    debugPrint('\n🔄 PremiumServerUnlockService.initialize() called');
    debugPrint('   _initialized flag: $_initialized');

    if (_initialized) {
      debugPrint('   ⚠️ Already initialized, returning');
      return;
    }
    // If another caller already started loading, wait for it instead of
    // returning immediately with empty _unlockedServers.
    if (_initFuture != null) {
      debugPrint('   ⏳ Init already in progress, waiting...');
      return _initFuture!;
    }
    _initFuture = _doInitialize();
    return _initFuture!;
  }

  Future<void> _doInitialize() async {
    // NOTE: _initialized is set to true only AFTER data has been loaded so
    // that any caller which checks the flag can trust _unlockedServers is
    // already populated.  The _initFuture field prevents duplicate loads.
    try {
      final prefs = await SharedPreferences.getInstance();

      debugPrint('   📦 Fetching from SharedPreferences...');
      debugPrint('   📦 Storage key: $_storageKey');

      final savedData = prefs.getString(_storageKey);

      debugPrint('   📦 Saved data exists: ${savedData != null}');
      if (savedData != null) {
        debugPrint('   📦 Saved data length: ${savedData.length} chars');
        debugPrint('   📦 Saved data content: $savedData');
      }

      if (savedData != null && savedData.isNotEmpty) {
        try {
          final decoded = jsonDecode(savedData) as Map<String, dynamic>;
          debugPrint(
            '   📦 JSON decoded successfully: ${decoded.length} items',
          );

          decoded.forEach((key, value) {
            try {
              debugPrint('   📦 Loading item key=$key, value=$value');
              final unlock = UnlockedPremiumServer.fromJson(value);

              // Only keep if still valid
              if (unlock.isStillUnlocked) {
                _unlockedServers[key] = unlock; // KEY IS STRING
                debugPrint(
                  '   ✅ LOADED unlock for [$key]: until=${unlock.unlockedUntil.toLocal()}, remainingTime=${unlock.remainingSeconds}s',
                );
              } else {
                debugPrint(
                  '   ⏰ EXPIRED unlock for [$key] (until=${unlock.unlockedUntil.toLocal()}), skipping',
                );
              }
            } catch (e) {
              debugPrint('   ❌ Error parsing unlock for key $key: $e');
              debugPrint('      value was: $value');
            }
          });

          debugPrint(
            '✅ Initialize complete - Loaded ${_unlockedServers.length} valid unlocked premium servers',
          );
          debugPrint(
            '   Final _unlockedServers keys: ${_unlockedServers.keys.toList()}',
          );
        } catch (e) {
          debugPrint('   ❌ Error decoding JSON: $e');
          debugPrint('      Saved data was: $savedData');
        }
      } else {
        debugPrint('   📦 No saved data in SharedPreferences (empty or null)');
      }

      // Mark as fully loaded only after all data is in memory.
      _initialized = true;
    } catch (e, st) {
      debugPrint('❌ Error loading unlocked servers: $e');
      debugPrint('   Stack trace: $st');
      // Allow a future retry by clearing the in-progress future.
      _initFuture = null;
    }
  }

  /// Ensure service is initialized before first use
  Future<void> _ensureInitialized() async {
    if (!_initialized) {
      await initialize();
    }
  }

  /// Unlock a premium server for a specified duration
  Future<void> unlockPremiumServer({
    required dynamic server,
    required int durationMinutes,
    required String unlockedBy, // 'ad' or 'subscription'
  }) async {
    debugPrint('\n🔓 unlockPremiumServer() called');
    debugPrint(
      '   server: $server, duration: $durationMinutes min, by: $unlockedBy',
    );

    await _ensureInitialized();

    try {
      // Extract server ID - ALWAYS convert to String to match server.id type
      String? serverId;
      if (server is String) {
        serverId = server;
      } else if (server is int) {
        serverId = server.toString();
      } else if (server is VpnServer) {
        serverId = server.id;
      } else if (server is Map && server['id'] != null) {
        serverId = server['id'].toString();
      } else if (server != null && server.id != null) {
        serverId = server.id.toString();
      }

      if (serverId == null || serverId.isEmpty) {
        debugPrint('❌ Invalid server ID for unlock: $server');
        return;
      }

      debugPrint(
        '   1️⃣ Extracted serverId: "$serverId" (type: ${serverId.runtimeType})',
      );

      final serverName = server is String
          ? server
          : (server is VpnServer
                ? server.name
                : (server is Map ? server['name'] : server?.name));

      final unlockedUntil = DateTime.now().add(
        Duration(minutes: durationMinutes),
      );
      debugPrint(
        '   2️⃣ Unlock time: now + $durationMinutes min = ${unlockedUntil.toLocal()}',
      );

      final unlock = UnlockedPremiumServer(
        serverId: int.tryParse(serverId),
        serverName: serverName ?? 'Premium Server',
        unlockedUntil: unlockedUntil,
        unlockedBy: unlockedBy,
      );

      // Store in memory using STRING KEY
      debugPrint('   3️⃣ Storing to _unlockedServers["$serverId"]');
      _unlockedServers[serverId] = unlock;
      debugPrint(
        '   ✅ Stored in memory. _unlockedServers now has ${_unlockedServers.length} items',
      );
      debugPrint('      Keys: ${_unlockedServers.keys.toList()}');

      // Persist to storage
      debugPrint('   4️⃣ Calling _saveUnlocksToStorage()...');
      await _saveUnlocksToStorage();

      debugPrint(
        '✅ Premium server $serverId unlocked until ${unlockedUntil.toLocal()}',
      );
    } catch (e) {
      debugPrint('❌ Error unlocking premium server: $e');
      debugPrint('   Stack trace: $e');
    }
  }

  /// Check if a server is currently unlocked
  bool isPremiumServerUnlocked(dynamic serverId) {
    try {
      // Convert to String to match key type
      final id = serverId is String
          ? serverId
          : (serverId is int ? serverId.toString() : serverId?.toString());

      if (id == null || id.isEmpty) return false;

      final unlock = _unlockedServers[id];
      if (unlock == null) return false;

      if (!unlock.isStillUnlocked) {
        _unlockedServers.remove(id);
        // Save updated state (fire and forget is OK here since it's just cleanup)
        // But we log it
        debugPrint('   🗑️  Removed expired unlock for $id, saving state...');
        _saveUnlocksToStorage(); // Safe to not await cleanup saves
        return false;
      }

      return true;
    } catch (e) {
      debugPrint('❌ Error checking unlock status: $e');
      return false;
    }
  }

  /// Get unlock info for a server (if unlocked)
  UnlockedPremiumServer? getUnlockInfo(dynamic serverId) {
    try {
      // Convert to String to match key type
      final id = serverId is String
          ? serverId
          : (serverId is int ? serverId.toString() : serverId?.toString());

      if (id == null || id.isEmpty) return null;

      final unlock = _unlockedServers[id];

      if (unlock != null && unlock.isStillUnlocked) {
        return unlock;
      }

      return null;
    } catch (e) {
      debugPrint('❌ Error getting unlock info: $e');
      return null;
    }
  }

  /// Get remaining unlock time in seconds
  int getRemainingUnlockTime(dynamic serverId) {
    final unlock = getUnlockInfo(serverId);
    return unlock?.remainingSeconds ?? 0;
  }

  /// Get remaining unlock time in minutes (rounded up)
  int getRemainingMinutes(dynamic serverId) {
    final seconds = getRemainingUnlockTime(serverId);
    if (seconds <= 0) return 0;
    return (seconds / 60).ceil(); // Ceil to round up (5.2 min becomes 6m)
  }

  /// Get all currently unlocked servers
  Map<String, UnlockedPremiumServer> getAllUnlockedServers() {
    // Clean expired unlocks
    _unlockedServers.removeWhere((_, unlock) => !unlock.isStillUnlocked);
    return Map.from(_unlockedServers);
  }

  /// Remove unlock for a specific server
  Future<void> removeUnlock(dynamic serverId) async {
    try {
      // Convert to String to match key type
      final id = serverId is String
          ? serverId
          : (serverId is int ? serverId.toString() : serverId?.toString());

      if (id != null && id.isNotEmpty) {
        _unlockedServers.remove(id);
        await _saveUnlocksToStorage();
        debugPrint('✅ Removed unlock for server $id');
      }
    } catch (e) {
      debugPrint('❌ Error removing unlock: $e');
    }
  }

  /// Clear all unlocks
  Future<void> clearAllUnlocks() async {
    try {
      _unlockedServers.clear();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKey);
      debugPrint('✅ All unlocks cleared');
    } catch (e) {
      debugPrint('❌ Error clearing unlocks: $e');
    }
  }

  /// Save unlocks to storage
  Future<void> _saveUnlocksToStorage() async {
    try {
      debugPrint('\n💾 Saving unlocks to SharedPreferences...');
      debugPrint('   [SAVE START] _unlockedServers content:');
      debugPrint('      Map length: ${_unlockedServers.length}');
      debugPrint('      Map keys: ${_unlockedServers.keys.toList()}');

      _unlockedServers.forEach((key, unlock) {
        debugPrint(
          '      [$key] -> serverId=${unlock.serverId}, isStillUnlocked=${unlock.isStillUnlocked}, until=${unlock.unlockedUntil.toLocal()}',
        );
      });

      final prefs = await SharedPreferences.getInstance();
      final data = <String, dynamic>{};

      _unlockedServers.forEach((serverId, unlock) {
        debugPrint(
          '   Processing unlock: serverId=$serverId, isStillUnlocked=${unlock.isStillUnlocked}',
        );
        if (unlock.isStillUnlocked) {
          final jsonData = unlock.toJson();
          data[serverId.toString()] = jsonData;
          debugPrint('      ✅ Added to save data: $serverId -> $jsonData');
        } else {
          debugPrint('      ⏰ Unlock expired, skipping: $serverId');
        }
      });

      debugPrint('   Total items to save: ${data.length}');
      final jsonStr = jsonEncode(data);
      debugPrint('   Data to save: $jsonStr');
      debugPrint('   JSON length: ${jsonStr.length} chars');

      // CRITICAL: Actually save to SharedPreferences
      debugPrint('   [SAVE POINT] Calling prefs.setString()...');
      final saveResult = await prefs.setString(_storageKey, jsonStr);
      debugPrint('   [SAVE RESULT] setString returned: $saveResult');

      // VERIFY: Read back immediately
      final verifyRead = prefs.getString(_storageKey);
      debugPrint(
        '   [VERIFY READ AFTER SAVE] SharedPreferences contains: ${verifyRead != null ? "${verifyRead.length} chars" : "null"}',
      );

      debugPrint('✅ Unlocks saved to SharedPreferences (key: $_storageKey)');
      debugPrint(
        '   Verification - Saved JSON length: ${jsonStr.length} chars',
      );
    } catch (e, st) {
      debugPrint('❌ Error saving unlocks: $e');
      debugPrint('   Stack trace: $st');
    }
  }
}
