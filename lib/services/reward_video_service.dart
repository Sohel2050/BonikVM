import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

/// Model to track reward video state
class RewardVideoState {
  final int watchedCount; // 0-3 videos watched today
  final List<int>
  watchedVideoIndices; // Which videos have been watched (0, 1, or 2)
  final DateTime? lastResetDate; // Date when counter was last reset
  final bool canWatchMore; // Whether user can watch more videos today
  final int minutesEarned; // Total minutes earned from videos today

  RewardVideoState({
    this.watchedCount = 0,
    this.watchedVideoIndices = const [],
    this.lastResetDate,
    this.canWatchMore = true,
    this.minutesEarned = 0,
  });

  /// Check if a specific video can still be watched
  bool canWatchVideo(int index) {
    if (watchedCount >= 3) return false;
    if (watchedVideoIndices.contains(index)) return false;
    return true;
  }

  /// Create a copy with updated values
  RewardVideoState copyWith({
    int? watchedCount,
    List<int>? watchedVideoIndices,
    DateTime? lastResetDate,
    bool? canWatchMore,
    int? minutesEarned,
  }) {
    return RewardVideoState(
      watchedCount: watchedCount ?? this.watchedCount,
      watchedVideoIndices: watchedVideoIndices ?? this.watchedVideoIndices,
      lastResetDate: lastResetDate ?? this.lastResetDate,
      canWatchMore: canWatchMore ?? this.canWatchMore,
      minutesEarned: minutesEarned ?? this.minutesEarned,
    );
  }

  @override
  String toString() =>
      'RewardVideoState(watched: $watchedCount/3, earned: $minutesEarned minutes, canWatchMore: $canWatchMore)';
}

/// Service to manage reward video state and persistence
class RewardVideoService {
  static final RewardVideoService _instance = RewardVideoService._internal();
  static const String _prefsKey = 'reward_video_state';
  static const String _lastResetKey = 'reward_video_last_reset';
  static const int _maxVideosPerDay = 3;
  static const int _minutesPerVideo = 5;

  late SharedPreferences _prefs;
  RewardVideoState _state = RewardVideoState();

  /// Private constructor for singleton
  RewardVideoService._internal();

  /// Get singleton instance
  factory RewardVideoService() {
    return _instance;
  }

  /// Initialize the service
  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      await _refreshState();
      debugPrint('✅ RewardVideoService initialized: $_state');
    } catch (e) {
      debugPrint('❌ RewardVideoService initialization error: $e');
      _state = RewardVideoState();
    }
  }

  /// Get current state
  RewardVideoState get state => _state;

  /// Check if should reset daily counter
  bool _shouldResetDaily() {
    final lastReset = _state.lastResetDate;
    if (lastReset == null) return true;

    final now = DateTime.now();
    final lastResetDate = DateTime(
      lastReset.year,
      lastReset.month,
      lastReset.day,
    );
    final todayDate = DateTime(now.year, now.month, now.day);

    return lastResetDate.isBefore(todayDate);
  }

  /// Reset daily counter if needed
  Future<void> _refreshState() async {
    try {
      final savedState = _prefs.getString(_prefsKey);
      if (savedState != null) {
        final jsonData = jsonDecode(savedState) as Map<String, dynamic>;
        final lastReset = jsonData['lastResetDate'] != null
            ? DateTime.parse(jsonData['lastResetDate'] as String)
            : null;

        _state = RewardVideoState(
          watchedCount: jsonData['watchedCount'] as int? ?? 0,
          watchedVideoIndices: List<int>.from(
            (jsonData['watchedVideoIndices'] as List<dynamic>?) ?? [],
          ),
          lastResetDate: lastReset,
          canWatchMore: jsonData['canWatchMore'] as bool? ?? true,
          minutesEarned: jsonData['minutesEarned'] as int? ?? 0,
        );
      }

      // Check if we need to reset for a new day
      if (_shouldResetDaily()) {
        await _resetDailyCounter();
      }
    } catch (e) {
      debugPrint('❌ Error refreshing reward state: $e');
      _state = RewardVideoState();
    }
  }

  /// Reset daily counter
  Future<void> _resetDailyCounter() async {
    try {
      _state = RewardVideoState(
        watchedCount: 0,
        watchedVideoIndices: const [],
        lastResetDate: DateTime.now(),
        canWatchMore: true,
        minutesEarned: 0,
      );
      await _saveState();
      debugPrint('🔄 Daily reward counter reset');
    } catch (e) {
      debugPrint('❌ Error resetting daily counter: $e');
    }
  }

  /// Mark a video as watched
  Future<void> markVideoWatched(int videoIndex) async {
    try {
      if (!_state.canWatchVideo(videoIndex)) {
        debugPrint('⚠️ Video $videoIndex already watched');
        return;
      }

      final updatedIndices = List<int>.from(_state.watchedVideoIndices)
        ..add(videoIndex);
      final newCount = updatedIndices.length;
      final newCanWatch = newCount < _maxVideosPerDay;
      final earnedMinutes = newCount * _minutesPerVideo;

      _state = _state.copyWith(
        watchedCount: newCount,
        watchedVideoIndices: updatedIndices,
        canWatchMore: newCanWatch,
        minutesEarned: earnedMinutes,
      );

      await _saveState();
      debugPrint(
        '✅ Video $videoIndex marked watched. Total: ${_state.watchedCount}/$_maxVideosPerDay',
      );
    } catch (e) {
      debugPrint('❌ Error marking video watched: $e');
    }
  }

  /// Check if a specific video can be watched
  bool canWatchVideo(int videoIndex) {
    return _state.canWatchVideo(videoIndex);
  }

  /// Get total minutes earned today
  int getTodayMinutesEarned() {
    return _state.minutesEarned;
  }

  /// Get remaining videos that can be watched
  int getRemainingVideos() {
    return _maxVideosPerDay - _state.watchedCount;
  }

  /// Reset for testing purposes
  Future<void> resetForTesting() async {
    _state = RewardVideoState();
    await _saveState();
    debugPrint('🧪 Reward video state reset for testing');
  }

  /// Save state to preferences
  Future<void> _saveState() async {
    try {
      final jsonData = {
        'watchedCount': _state.watchedCount,
        'watchedVideoIndices': _state.watchedVideoIndices,
        'lastResetDate':
            _state.lastResetDate?.toIso8601String() ??
            DateTime.now().toIso8601String(),
        'canWatchMore': _state.canWatchMore,
        'minutesEarned': _state.minutesEarned,
      };
      await _prefs.setString(_prefsKey, jsonEncode(jsonData));
      debugPrint('💾 Reward video state saved');
    } catch (e) {
      debugPrint('❌ Error saving reward state: $e');
    }
  }

  /// Get reward video state as string for UI
  String getRewardStatusText() {
    if (_state.watchedCount >= _maxVideosPerDay) {
      return 'Daily limit reached';
    }
    return '${_state.watchedCount}/$_maxVideosPerDay videos watched';
  }

  /// Dispose service
  void dispose() {
    debugPrint('🔌 RewardVideoService disposed');
  }
}
