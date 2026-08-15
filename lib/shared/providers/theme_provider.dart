import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

// Available theme colors
class AppThemeColors {
  static const Map<String, Color> colors = {
    'green': Color(0xFF4CAF50),
    'blue': Color(0xFF2196F3),
    'red': Color(0xFFE53E3E),
    'purple': Color(0xFF7C3AED),
    'orange': Color(0xFFF59E0B),
    'pink': Color(0xFFEC4899),
    'indigo': Color(0xFF4338CA),
    'teal': Color(0xFF14B8A6),
  };

  static List<String> get colorKeys => colors.keys.toList();
  static List<Color> get colorValues => colors.values.toList();
}

// Theme mode provider (light/dark/system)
final themeModeProvider = StateNotifierProvider<ThemeModeNotifier, ThemeMode>((
  ref,
) {
  return ThemeModeNotifier();
});

// Theme color provider
final themeColorProvider = StateNotifierProvider<ThemeColorNotifier, Color>((
  ref,
) {
  return ThemeColorNotifier();
});

// Theme color key provider for UI
final themeColorKeyProvider =
    StateNotifierProvider<ThemeColorKeyNotifier, String>((ref) {
      return ThemeColorKeyNotifier();
    });

// Combined theme data provider
final themeDataProvider = Provider<ThemeData>((ref) {
  final themeColor = ref.watch(themeColorProvider);
  return _buildLightTheme(themeColor);
});

// Dark theme data provider
final darkThemeDataProvider = Provider<ThemeData>((ref) {
  final themeColor = ref.watch(themeColorProvider);
  return _buildDarkTheme(themeColor);
});

ThemeData _buildLightTheme(Color primaryColor) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: Brightness.light,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    colorScheme: colorScheme,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: const Color(0xFFF8F9FA),
    appBarTheme: AppBarTheme(
      backgroundColor: primaryColor,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor.withValues(alpha: 0.5);
        }
        return null;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryColor),
  );
}

ThemeData _buildDarkTheme(Color primaryColor) {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: primaryColor,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: colorScheme,
    primaryColor: primaryColor,
    scaffoldBackgroundColor: const Color(0xFF0D1117),
    appBarTheme: AppBarTheme(
      backgroundColor: const Color(0xFF161B22),
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor;
        }
        return null;
      }),
      trackColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.selected)) {
          return primaryColor.withValues(alpha: 0.5);
        }
        return null;
      }),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: primaryColor),
  );
}

class ThemeColorKeyNotifier extends StateNotifier<String> {
  ThemeColorKeyNotifier() : super('green') {
    _loadThemeColorKey();
  }

  static const String _themeColorKeyKey = 'theme_color_key';

  Future<void> _loadThemeColorKey() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorKey = prefs.getString(_themeColorKeyKey);
      if (colorKey != null && AppThemeColors.colors.containsKey(colorKey)) {
        state = colorKey;
      }
    } catch (e) {
      state = 'green';
    }
  }

  Future<void> setThemeColorKey(String colorKey) async {
    if (AppThemeColors.colors.containsKey(colorKey)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_themeColorKeyKey, colorKey);
        state = colorKey;
      } catch (e) {
        // Handle error
      }
    }
  }
}

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier() : super(ThemeMode.dark) {
    _loadThemeMode();
  }

  static const String _themeModeKey = 'theme_mode';

  Future<void> _loadThemeMode() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeModeIndex = prefs.getInt(_themeModeKey);
      state = themeModeIndex != null
          ? ThemeMode.values[themeModeIndex]
          : ThemeMode.dark;
    } catch (e) {
      state = ThemeMode.dark;
    }
  }

  Future<void> setThemeMode(ThemeMode themeMode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_themeModeKey, themeMode.index);
      state = themeMode;
    } catch (e) {
      // Handle error
    }
  }

  void toggleTheme() {
    switch (state) {
      case ThemeMode.light:
        setThemeMode(ThemeMode.dark);
        break;
      case ThemeMode.dark:
        setThemeMode(ThemeMode.system);
        break;
      case ThemeMode.system:
        setThemeMode(ThemeMode.light);
        break;
    }
  }
}

class ThemeColorNotifier extends StateNotifier<Color> {
  ThemeColorNotifier() : super(AppThemeColors.colors['green']!) {
    _loadThemeColor();
  }

  static const String _themeColorKey = 'theme_color_key_v2';

  Future<void> _loadThemeColor() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final colorKey = prefs.getString(_themeColorKey) ?? 'green';
      if (AppThemeColors.colors.containsKey(colorKey)) {
        state = AppThemeColors.colors[colorKey]!;
      }
    } catch (e) {
      state = AppThemeColors.colors['green']!;
    }
  }

  Future<void> setThemeColorByKey(String colorKey) async {
    if (AppThemeColors.colors.containsKey(colorKey)) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_themeColorKey, colorKey);
        state = AppThemeColors.colors[colorKey]!;
      } catch (e) {
        // Handle error
      }
    }
  }

  Future<void> setThemeColor(Color color) async {
    // Find the color key for the given color
    String? colorKey;
    for (final entry in AppThemeColors.colors.entries) {
      if (entry.value == color) {
        colorKey = entry.key;
        break;
      }
    }

    if (colorKey != null) {
      await setThemeColorByKey(colorKey);
    }
  }
}

// Theme helper extension
extension ThemeExtension on BuildContext {
  bool get isDarkMode {
    return Theme.of(this).brightness == Brightness.dark;
  }

  ColorScheme get colorScheme {
    return Theme.of(this).colorScheme;
  }

  TextTheme get textTheme {
    return Theme.of(this).textTheme;
  }
}

