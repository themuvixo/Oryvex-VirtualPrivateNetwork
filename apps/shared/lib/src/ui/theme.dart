import 'package:flutter/material.dart';

/// OryvexVPN design tokens, after apple.com's dark product pages.
///
/// A true-black canvas, #1D1D1F tiles with big soft corners, #F5F5F7 type set large and tight,
/// Apple's #86868B for everything secondary, and one blue: #2997FF for links and "on", #0071E3
/// for the filled call to action. Inter (the closest open face to SF Pro) for text, Inter Display
/// for headlines, JetBrains Mono (closest to SF Mono) for addresses and logs. All three ship
/// inside the app: nothing is fetched at runtime.
class Ox {
  Ox._();

  // Surfaces
  static const black = Color(0xFF000000);
  static const nav = Color(0xB8161617); // frosted bar, over a blur
  static const tile = Color(0xFF1D1D1F); // apple.com dark tile
  static const tileHi = Color(0xFF2C2C2E);
  static const tileTop = Color(0xFF3A3A3C); // segmented thumb, pressed rows
  static const field = Color(0xFF1C1C1E);
  static const hairline = Color(0xFF38383A);
  static const hairlineSoft = Color(0xFF2A2A2C);

  // Blue
  static const blue = Color(0xFF2997FF); // apple.com link blue on dark: every "on"
  static const blueCta = Color(0xFF0071E3); // apple.com button blue
  static const blueCtaHi = Color(0xFF0077ED); // its hover
  static const blueSoft = Color(0xFF6CB4FF);
  static const blueDeep = Color(0xFF0040DD);
  static const blueIce = Color(0xFFBFE0FF);

  // Type
  static const text = Color(0xFFF5F5F7);
  static const secondary = Color(0xFF86868B);
  static const tertiary = Color(0xFF6E6E73);

  // States
  static const danger = Color(0xFFFF453A);
  static const warn = Color(0xFFFF9F0A);

  // Fonts bundled by the oryvex_shared package (fonts/, SIL OFL 1.1). A font a package bundles
  // is only found under "packages/<package>/<family>".
  static const sans = 'packages/oryvex_shared/Inter';
  static const display = 'packages/oryvex_shared/InterDisplay';
  static const mono = 'packages/oryvex_shared/JetBrainsMono';
  static const fallback = <String>['Segoe UI Variable Text', 'Segoe UI', 'Roboto', 'Noto Sans', 'Arial'];
  static const monoFallback = <String>['Cascadia Mono', 'Consolas', 'Roboto Mono', 'Noto Sans Mono', 'monospace'];

  // Short names used across the widgets.
  static const card = tile;
  static const cardHi = tileHi;
  static const line = hairline;
  static const muted = secondary;
  static const faint = tertiary;
  static const surface = Color(0xFF0A0A0B);

  // Geometry
  static const radiusTile = 28.0; // apple.com tiles
  static const radiusGroup = 18.0;
  static const radiusField = 12.0;
  static const contentMax = 980.0; // apple.com's content width
  static const navHeight = 52.0;
  static const tabBarHeight = 64.0;

  // Motion. Apple's curves: a quick start that settles slowly, never a bounce on text.
  static const fast = Duration(milliseconds: 200);
  static const medium = Duration(milliseconds: 380);
  static const slow = Duration(milliseconds: 650);
  static const page = Duration(milliseconds: 460);
  static const ease = Cubic(0.25, 0.1, 0.25, 1.0); // apple.com's default ease
  static const easeOut = Cubic(0.16, 1.0, 0.3, 1.0); // expo-out: arrivals
  static const easeInOut = Cubic(0.65, 0.0, 0.35, 1.0); // state morphs
  static const easeIn = Cubic(0.4, 0.0, 1.0, 1.0); // departures

  /// Headline type: Inter Display, tight tracking, like apple.com's product headlines.
  static TextStyle headline(double size, {Color color = text, FontWeight weight = FontWeight.w700}) => TextStyle(
        fontFamily: display,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: 1.08,
        fontWeight: weight,
        letterSpacing: -0.022 * size,
        color: color,
      );

  static TextStyle body(double size, {Color color = text, FontWeight weight = FontWeight.w400, double height = 1.42}) =>
      TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: size >= 17 ? -0.022 * size * 0.5 : -0.003 * size,
        color: color,
      );

  /// The small blue line above a headline ("Protected", "Activity").
  static TextStyle eyebrow({Color color = blue}) => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallback,
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: color,
      );

  static TextStyle code(double size, {Color color = text, FontWeight weight = FontWeight.w400, double height = 1.5}) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        color: color,
      );
}

/// Breakpoints, by the width the page actually gets.
enum OxSize { compact, medium, expanded }

extension OxSizeOf on BuildContext {
  OxSize get oxSize {
    final w = MediaQuery.sizeOf(this).width;
    if (w >= 1024) return OxSize.expanded;
    if (w >= 640) return OxSize.medium;
    return OxSize.compact;
  }

  bool get reduceMotion => MediaQuery.maybeDisableAnimationsOf(this) ?? false;
}

/// Route transition for anything pushed on top of the tabs (licenses, sheets): the new page
/// rises a little and comes into focus, the old one sinks back and dims, like apple.com's
/// overlays. Same on every platform, so desktop and Android feel like one app.
class OxPageTransitionsBuilder extends PageTransitionsBuilder {
  const OxPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final enter = CurvedAnimation(parent: animation, curve: Ox.easeOut, reverseCurve: Ox.easeIn);
    final behind = CurvedAnimation(parent: secondaryAnimation, curve: Ox.easeOut, reverseCurve: Ox.easeIn);
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: 0.55).animate(behind),
      child: ScaleTransition(
        scale: Tween<double>(begin: 1, end: 0.96).animate(behind),
        child: FadeTransition(
          opacity: enter,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, 0.04), end: Offset.zero).animate(enter),
            child: ScaleTransition(
              scale: Tween<double>(begin: 1.02, end: 1).animate(enter),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

ThemeData buildOxTheme() {
  const scheme = ColorScheme.dark(
    primary: Ox.blue,
    onPrimary: Colors.white,
    primaryContainer: Ox.blueCta,
    onPrimaryContainer: Colors.white,
    secondary: Ox.blueSoft,
    onSecondary: Ox.black,
    surface: Ox.black,
    onSurface: Ox.text,
    surfaceContainerHighest: Ox.tileHi,
    outline: Ox.hairline,
    error: Ox.danger,
    onError: Colors.white,
  );

  const transitions = PageTransitionsTheme(builders: {
    TargetPlatform.android: OxPageTransitionsBuilder(),
    TargetPlatform.windows: OxPageTransitionsBuilder(),
    TargetPlatform.linux: OxPageTransitionsBuilder(),
    TargetPlatform.macOS: OxPageTransitionsBuilder(),
    TargetPlatform.iOS: OxPageTransitionsBuilder(),
  });

  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: scheme,
    fontFamily: Ox.sans,
    fontFamilyFallback: Ox.fallback,
    scaffoldBackgroundColor: Ox.black,
    canvasColor: Ox.black,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: Colors.white.withValues(alpha: 0.04),
    focusColor: Ox.blue.withValues(alpha: 0.22),
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: transitions,
  );

  return base.copyWith(
    textTheme: base.textTheme.apply(
      bodyColor: Ox.text,
      displayColor: Ox.text,
      fontFamily: Ox.sans,
    ),
    dividerTheme: const DividerThemeData(color: Ox.hairlineSoft, thickness: 0.6, space: 0.6),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? Ox.tertiary : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return Ox.tileHi;
        return s.contains(WidgetState.selected) ? Ox.blueCta : const Color(0xFF39393D);
      }),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
      thumbIcon: const WidgetStatePropertyAll(null),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Ox.field,
      isDense: true,
      labelStyle: Ox.body(15, color: Ox.secondary),
      floatingLabelStyle: Ox.body(14, color: Ox.blue),
      hintStyle: Ox.body(15, color: Ox.tertiary),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(Ox.radiusField)),
        borderSide: BorderSide(color: Ox.hairlineSoft),
      ),
      enabledBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(Ox.radiusField)),
        borderSide: BorderSide(color: Ox.hairlineSoft),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(Ox.radiusField)),
        borderSide: BorderSide(color: Ox.blue, width: 1.4),
      ),
      errorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(Ox.radiusField)),
        borderSide: BorderSide(color: Ox.danger),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: Ox.blue,
      selectionColor: Ox.blue.withValues(alpha: 0.35),
      selectionHandleColor: Ox.blue,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(Colors.white.withValues(alpha: 0.22)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Ox.tileHi,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Ox.hairline),
      ),
      textStyle: Ox.body(14, color: Ox.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Ox.tileHi,
      contentTextStyle: Ox.body(15),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Ox.hairline),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Ox.tileHi,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: Ox.hairline),
      ),
      textStyle: Ox.body(15),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Ox.black,
      foregroundColor: Ox.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Ox.headline(22, weight: FontWeight.w600),
    ),
    cardTheme: const CardThemeData(
      color: Ox.tile,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Ox.radiusTile))),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(color: Ox.blue, linearTrackColor: Ox.tileHi),
    iconTheme: const IconThemeData(color: Ox.text),
  );
}
