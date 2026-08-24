import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class ThemeManager extends ChangeNotifier {
  static const _key = 'cloud_audiobook_theme';

  // Built-in color schemes
  static const builtInColors = [
    _ThemePreset('深紫', Color(0xFF6750A4)),
    _ThemePreset('蓝色', Color(0xFF1E88E5)),
    _ThemePreset('青色', Color(0xFF00897B)),
    _ThemePreset('绿色', Color(0xFF43A047)),
    _ThemePreset('琥珀', Color(0xFFFF8F00)),
    _ThemePreset('橙色', Color(0xFFF4511E)),
    _ThemePreset('红色', Color(0xFFE53935)),
    _ThemePreset('粉色', Color(0xFFD81B60)),
    _ThemePreset('灰色', Color(0xFF757575)),
  ];

  String _mode = 'system'; // 'system', 'dynamic', 'custom'
  String get mode => _mode;

  Color _seedColor = const Color(0xFF6750A4);
  Color get seedColor => _seedColor;

  ColorScheme? _dynamicLight;
  ColorScheme? _dynamicDark;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _mode = prefs.getString('${_key}_mode') ?? 'system';
    final colorVal = prefs.getInt('${_key}_seed');
    if (colorVal != null) _seedColor = Color(colorVal);
    notifyListeners();
  }

  Future<void> setMode(String mode) async {
    _mode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('${_key}_mode', mode);
    notifyListeners();
  }

  Future<void> setSeedColor(Color color) async {
    _seedColor = color;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('${_key}_seed', color.value);
    notifyListeners();
  }

  void updateDynamicColors(ColorScheme light, ColorScheme dark) {
    _dynamicLight = light;
    _dynamicDark = dark;
    notifyListeners();
  }

  ThemeData get lightTheme {
    if (_mode == 'dynamic' && _dynamicLight != null) {
      return ThemeData(
        useMaterial3: true,
        colorScheme: _dynamicLight,
        brightness: Brightness.light,
      );
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      ),
    );
  }

  ThemeData get darkTheme {
    if (_mode == 'dynamic' && _dynamicDark != null) {
      return ThemeData(
        useMaterial3: true,
        colorScheme: _dynamicDark,
        brightness: Brightness.dark,
      );
    }
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ),
    );
  }
}

class _ThemePreset {
  final String name;
  final Color color;
  const _ThemePreset(this.name, this.color);
}
