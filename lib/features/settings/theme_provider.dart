import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeProvider extends ChangeNotifier {
  bool _isDarkMode = true;

  bool get isDarkMode => _isDarkMode;

  ThemeProvider() {
    _loadTheme();
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    _isDarkMode = prefs.getBool('isDarkMode') ?? true;
    notifyListeners();
  }

  Future<void> toggleTheme() async {
    _isDarkMode = !_isDarkMode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('isDarkMode', _isDarkMode);
    notifyListeners();
  }

  // ============================================
  // DARK THEME
  // ============================================
  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF0F1117),
      primaryColor: const Color(0xFF6C63FF),
      colorScheme: const ColorScheme.dark(
        primary: Color(0xFF6C63FF),
        secondary: Color(0xFF3D5AFE),
        surface: Color(0xFF1A1D2E),
        background: Color(0xFF0F1117),
        onPrimary: Colors.white,
        onSurface: Colors.white,
        onBackground: Colors.white,
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0F1117),
        foregroundColor: Colors.white,
        elevation: 0,
        iconTheme: IconThemeData(color: Colors.white),
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardColor: const Color(0xFF1A1D2E),
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Color(0xFF1A1D2E),
        selectedItemColor: Color(0xFF6C63FF),
        unselectedItemColor: Colors.white38,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFF1A1D2E),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        hintStyle: const TextStyle(color: Colors.white38),
        labelStyle: const TextStyle(color: Colors.white70),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Colors.white),
        bodyLarge: TextStyle(color: Colors.white),
        bodyMedium: TextStyle(color: Colors.white70),
        bodySmall: TextStyle(color: Colors.white54),
      ),
      dividerColor: Colors.white12,
      iconTheme: const IconThemeData(color: Colors.white),
    );
  }

  // ============================================
  // LIGHT THEME
  // ============================================
  static ThemeData get lightTheme {
    return ThemeData(
      brightness: Brightness.light,
      scaffoldBackgroundColor: const Color(0xFFF5F5F5),
      primaryColor: const Color(0xFF6C63FF),
      colorScheme: const ColorScheme.light(
        primary: Color(0xFF6C63FF),
        secondary: Color(0xFF3D5AFE),
        surface: Colors.white,
        background: Color(0xFFF5F5F5),
        onPrimary: Colors.white,
        onSurface: Color(0xFF1A1A2E),
        onBackground: Color(0xFF1A1A2E),
      ),
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.white,
        foregroundColor: Color(0xFF1A1A2E),
        elevation: 0,
        iconTheme: IconThemeData(color: Color(0xFF1A1A2E)),
        titleTextStyle: TextStyle(
          color: Color(0xFF1A1A2E),
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
      ),
      cardColor: Colors.white,
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: Colors.white,
        selectedItemColor: Color(0xFF6C63FF),
        unselectedItemColor: Colors.black38,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        hintStyle: const TextStyle(color: Colors.black38),
        labelStyle: const TextStyle(color: Colors.black54),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6C63FF),
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textTheme: const TextTheme(
        headlineLarge: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold),
        headlineMedium: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold),
        titleLarge: TextStyle(color: Color(0xFF1A1A2E), fontWeight: FontWeight.bold),
        titleMedium: TextStyle(color: Color(0xFF1A1A2E)),
        bodyLarge: TextStyle(color: Color(0xFF1A1A2E)),
        bodyMedium: TextStyle(color: Color(0xFF4A4A4A)),
        bodySmall: TextStyle(color: Color(0xFF6A6A6A)),
      ),
      dividerColor: const Color(0xFFE0E0E0),
      iconTheme: const IconThemeData(color: Color(0xFF1A1A2E)),
    );
  }
}

// ============================================
// APP COLORS HELPER — use anywhere in the app
// ============================================
class AppColors {
  static Color background(BuildContext context) =>
      Theme.of(context).scaffoldBackgroundColor;

  static Color card(BuildContext context) =>
      Theme.of(context).cardColor;

  static Color text(BuildContext context) =>
      Theme.of(context).textTheme.bodyLarge?.color ?? Colors.black;

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).textTheme.bodyMedium?.color ?? Colors.grey;

  static Color textHint(BuildContext context) =>
      Theme.of(context).textTheme.bodySmall?.color ?? Colors.grey;

  static Color divider(BuildContext context) =>
      Theme.of(context).dividerColor;

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  static Color surface(BuildContext context) =>
      isDark(context) ? const Color(0xFF1A1D2E) : Colors.white;

  static Color surfaceVariant(BuildContext context) =>
      isDark(context) ? const Color(0xFF252836) : const Color(0xFFF0F0F0);

  static Color border(BuildContext context) =>
      isDark(context) ? Colors.white12 : const Color(0xFFE0E0E0);

  static Color icon(BuildContext context) =>
      isDark(context) ? Colors.white : const Color(0xFF1A1A2E);
}