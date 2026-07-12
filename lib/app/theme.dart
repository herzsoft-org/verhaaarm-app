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

/// Hue of the app's purple seed color, reused at near-zero saturation for the
/// light-mode neutral scale below so backgrounds/surfaces stay in quiet
/// harmony with the accent color while still reading as clean neutrals
/// rather than tinted beige or lavender.
const double _neutralHue = 250;

Color _neutral(double saturation, double lightness) =>
    HSLColor.fromAHSL(1.0, _neutralHue, saturation, lightness).toColor();

/// Lightness of the light-mode "chrome" (scaffold background and, via
/// [ColorScheme.surface], the app bar) - kept a clear step darker than the
/// near-white "box" surfaces (cards, dialogs, ...) so boxes stand out.
const double _lightChromeLightness = 0.85;

/// The page/scaffold background. In dark mode Material 3's [ColorScheme.surface]
/// already reads well, so it's used as-is. In light mode it uses a clean,
/// neutral gray - clearly deeper than the near-white card surfaces - so
/// cards visibly float above the page.
Color _pageBackgroundColor(ColorScheme scheme) {
  if (scheme.brightness == Brightness.dark) return scheme.surface;
  return _neutral(0.02, _lightChromeLightness);
}

/// Nudges a surface-container color further away from the page background so
/// that "boxes" (cards, dialogs, sheets, ...) read as clearly separated: in
/// dark mode boxes are brightened relative to Material 3's tonal role, which
/// alone sits too close to the background. In light mode the neutral
/// [ColorScheme.surfaceContainerLow] override passed into [buildAppTheme] is
/// already tuned to be near-white against the page background, so it's used
/// as-is.
Color _boxSurfaceColor(Color base, Brightness brightness) {
  if (brightness == Brightness.light) return base;
  return _adjustLightness(base, 0.045);
}

ThemeData buildAppTheme(Brightness brightness) {
  const seed = Color(0xFF7B61FF);
  final isLight = brightness == Brightness.light;

  final scheme = ColorScheme.fromSeed(
    seedColor: seed,
    brightness: brightness,
    // Light mode only: Material 3's seed-derived neutral tones carry a faint
    // purple/lavender cast that clashed with the (formerly beige) page
    // background. Replace just the neutral/neutral-variant-derived roles
    // (surfaces + on-surface text/icons + outlines) with a clean, low-
    // saturation neutral scale, and push text/icon roles darker for
    // stronger contrast. Primary/secondary/tertiary/error (and their
    // "on"/container pairs) are left as Material 3 computes them, so the
    // purple accent and existing color-coding elsewhere stay unchanged.
    // Dark mode passes null for all of these, so it is unaffected.
    //
    // The "chrome" roles (surface -> app bar; surfaceContainer ->
    // NavigationBar, via their Material 3 defaults) sit at
    // [_lightChromeLightness], a clear step darker than the "box" roles
    // (surfaceContainerLow and above, used for cards/dialogs/sheets/the
    // highlighted event card/snackbars), so boxes read as clearly raised
    // above the scaffold background, header, and bottom navigation bar.
    surface: isLight ? _neutral(0.02, _lightChromeLightness) : null,
    surfaceDim: isLight ? _neutral(0.02, 0.76) : null,
    surfaceBright: isLight ? _neutral(0.02, 0.96) : null,
    surfaceContainerLowest: isLight ? _neutral(0.0, 1.0) : null,
    surfaceContainerLow: isLight ? _neutral(0.02, 0.985) : null,
    surfaceContainer: isLight ? _neutral(0.02, _lightChromeLightness - 0.01) : null,
    surfaceContainerHigh: isLight ? _neutral(0.02, 0.96) : null,
    surfaceContainerHighest: isLight ? _neutral(0.02, 0.97) : null,
    onSurface: isLight ? _neutral(0.04, 0.12) : null,
    onSurfaceVariant: isLight ? _neutral(0.04, 0.32) : null,
    outline: isLight ? _neutral(0.03, 0.50) : null,
    outlineVariant: isLight ? _neutral(0.03, 0.82) : null,
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
