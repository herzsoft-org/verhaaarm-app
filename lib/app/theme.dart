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

/// Shifts a color's HSL lightness by [delta] (positive = brighter, negative
/// = darker), clamped to a valid lightness.
Color _adjustLightness(Color base, double delta) {
  final hsl = HSLColor.fromColor(base);
  return hsl.withLightness((hsl.lightness + delta).clamp(0.0, 1.0)).toColor();
}

/// The page/scaffold background. In dark mode Material 3's [ColorScheme.surface]
/// already reads well, so it's used as-is. In light mode it's close to pure
/// white and still carries the seed color's (cool, purple) hue, which reads
/// as a pink/lilac tint once darkened - re-hue it to a warm, neutral
/// eggshell off-white instead, independent of the seed color.
Color _pageBackgroundColor(ColorScheme scheme) {
  if (scheme.brightness == Brightness.dark) return scheme.surface;
  return const HSLColor.fromAHSL(1.0, 45, 0.25, 0.93).toColor();
}

/// Nudges a surface-container color further away from the page background
/// so that "boxes" (cards, dialogs, sheets, ...) read with more contrast
/// against the page background: brighter in dark mode, darker in light mode.
/// Applied on top of Material 3's tonal roles, which alone are too close to
/// the background to read as clearly separated boxes.
Color _boxSurfaceColor(Color base, Brightness brightness) {
  final delta = brightness == Brightness.dark ? 0.045 : -0.075;
  return _adjustLightness(base, delta);
}

ThemeData buildAppTheme(Brightness brightness) {
  const seed = Color(0xFF7B61FF);

  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
  );

  final pageBackgroundColor = _pageBackgroundColor(scheme);
  final boxColor = _boxSurfaceColor(scheme.surfaceContainerLow, brightness);

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
    scaffoldBackgroundColor: pageBackgroundColor,
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
      color: boxColor,
      shape: cardShape,
      // Obtainium uses margin: zero and manages spacing between cards at every
      // call site. This app doesn't do that consistently everywhere, so keep a
      // small default margin (matches Flutter's pre-M3-Expressive default) as a
      // safety net for screens that rely on it instead of explicit spacing.
      margin: const EdgeInsets.all(4),
    ),
    dialogTheme: DialogThemeData(backgroundColor: boxColor, shape: dialogShape),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: boxColor,
      shape: const RoundedSuperellipseBorder(
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
