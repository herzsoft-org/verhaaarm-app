import 'package:flutter/material.dart';

/// Corner radius for the outer corners of a connected tile run.
const double connectedTileBigRadius = 24;

/// Corner radius for the inner (joined) corners of a connected tile run.
const double connectedTileSmallRadius = 6;

/// Radius for a run of visually grouped tiles (e.g. settings sections),
/// mirroring the "connected card" look: only the first/last tile in a run
/// gets the big outer radius, the joined edges in between get a small one.
BorderRadius positionalTileRadius({required bool isFirst, required bool isLast}) {
  return BorderRadius.vertical(
    top: Radius.circular(isFirst ? connectedTileBigRadius : connectedTileSmallRadius),
    bottom: Radius.circular(isLast ? connectedTileBigRadius : connectedTileSmallRadius),
  );
}

ThemeData buildAppTheme(Brightness brightness) {
  const seed = Color(0xFF7B61FF);

  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );

  final cardShape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(24));
  const buttonShape = StadiumBorder();
  final dialogShape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(28));
  final fieldShape = RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16));

  const pillButtonStyle = ButtonStyle(
    shape: WidgetStatePropertyAll(buttonShape),
    minimumSize: WidgetStatePropertyAll(Size(0, 48)),
  );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: scheme.surface,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      },
    ),
    appBarTheme: const AppBarTheme(centerTitle: false),
    cardTheme: CardThemeData(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: scheme.surfaceContainerLow,
      shape: cardShape,
      // Obtainium uses margin: zero and manages spacing between cards at every
      // call site. This app doesn't do that consistently everywhere, so keep a
      // small default margin (matches Flutter's pre-M3-Expressive default) as a
      // safety net for screens that rely on it instead of explicit spacing.
      margin: const EdgeInsets.all(4),
    ),
    dialogTheme: DialogThemeData(shape: dialogShape),
    bottomSheetTheme: const BottomSheetThemeData(
      shape: RoundedSuperellipseBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHigh,
      contentTextStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(16)),
    ),
    expansionTileTheme: ExpansionTileThemeData(shape: cardShape, collapsedShape: cardShape),
    listTileTheme: ListTileThemeData(shape: fieldShape),
    chipTheme: const ChipThemeData(shape: StadiumBorder()),
    filledButtonTheme: const FilledButtonThemeData(style: pillButtonStyle),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: pillButtonStyle),
    outlinedButtonTheme: const OutlinedButtonThemeData(style: pillButtonStyle),
    textButtonTheme: const TextButtonThemeData(
      style: ButtonStyle(shape: WidgetStatePropertyAll(buttonShape)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      shape: RoundedSuperellipseBorder(borderRadius: BorderRadius.circular(20)),
      elevation: 4,
      focusElevation: 6,
      hoverElevation: 8,
      highlightElevation: 6,
    ),
    inputDecorationTheme: InputDecorationTheme(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
    ),
    sliderTheme: SliderThemeData(
      // Opts into the updated (post-"2023") Material 3 slider look. Flutter
      // has deprecated the flag pending a framework-default flip with no
      // replacement API; safe to delete once that lands.
      // ignore: deprecated_member_use
      year2023: false,
      activeTrackColor: scheme.primary,
      inactiveTrackColor: scheme.surfaceContainerHighest,
      thumbColor: scheme.primary,
      overlayColor: scheme.primary.withValues(alpha: 0.12),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      // See the note on sliderTheme.year2023 above.
      // ignore: deprecated_member_use
      year2023: false,
    ),
  );
}
