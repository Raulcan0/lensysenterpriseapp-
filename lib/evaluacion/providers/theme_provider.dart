// lib/providers/theme_provider.dart
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themeModeProvider =
  StateNotifierProvider<ThemeNotifier, ThemeMode>((ref) => ThemeNotifier()..loadTheme());

class ThemeNotifier extends StateNotifier<ThemeMode> {
  ThemeNotifier() : super(ThemeMode.light);

  static const _key = 'theme_mode';

  // Siempre carga y fuerza light
  Future<void> loadTheme() async {
  // opcional: leer prefs por compatibilidad, pero siempre usar light
  final prefs = await SharedPreferences.getInstance();
  final themeString = prefs.getString(_key);
  if (themeString != 'light') {
    // si había dark u otro valor, lo sobreescribimos por seguridad
    await prefs.setString(_key, 'light');
  }
  state = ThemeMode.light;
  }

  // Ignora cualquier intento de establecer dark y siempre pone light
  Future<void> setTheme(ThemeMode mode) async {
  state = ThemeMode.light;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(_key, 'light');
  }
}
