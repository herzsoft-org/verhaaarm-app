import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF7B61FF); // kannst du später ändern
  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: Brightness.dark,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: scheme.surface,
  );
}
