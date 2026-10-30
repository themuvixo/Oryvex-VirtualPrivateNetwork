import 'package:flutter/material.dart';

/// OryvexVPN design tokens, after apple.com.
///
/// apple.com's light canvas: #F5F5F7 behind everything, white tiles with big soft corners and
/// barely-there shadows, #1D1D1F type set large and tight, #6E6E73 for everything secondary,
/// and one blue, #0071E3, for links, "on" and the filled call to action. Inter (the closest
/// open face to SF Pro) for text, Inter Display for headlines, JetBrains Mono (closest to SF
/// Mono) for addresses and logs. All three ship inside the app: nothing is fetched at runtime.
class Ox {
  Ox._();

  // Surfaces: switched as a group so custom controls follow the saved appearance setting.
  static const black = Color(0xFF000000);
  static bool darkMode = true;
  static Color canvas = const Color(0xFF0B0D12);
  static Color nav = const Color(0xD9141720);
  static Color tile = const Color(0xFF151922);
  static Color tileHi = const Color(0xFF252B36);
  static Color tileTop = const Color(0xFF202633);
  static Color field = const Color(0xFF1C222D);
  static Color hairline = const Color(0xFF303846);
  static Color hairlineSoft = const Color(0xFF252C37);

  // Blue
  static const blue = Color(0xFF0071E3); // apple.com blue: links and every "on"
  static const blueCta = Color(0xFF0071E3); // apple.com button blue
  static const blueCtaHi = Color(0xFF0077ED); // its hover
  static const blueSoft = Color(0xFF2997FF);
  static const blueDeep = Color(0xFF0040DD);
  static const blueIce = Color(0xFF6CB4FF);

  // Type
  static Color text = const Color(0xFFF4F6FA);
  static Color secondary = const Color(0xFFA7B0BF);
  static Color tertiary = const Color(0xFF7E899A);

  // States
  static const danger = Color(0xFFE3342F);
  static Color warn = const Color(0xFFFFB454);

  /// The soft lift apple.com gives its tiles.
  static List<BoxShadow> tileShadow = const <BoxShadow>[
    BoxShadow(color: Color(0x44000000), blurRadius: 24, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x22000000), blurRadius: 3, offset: Offset(0, 1)),
  ];

  // Fonts bundled by the oryvex_shared package (fonts/, SIL OFL 1.1). A font a package bundles
  // is only found under "packages/<package>/<family>".
  static const sans = 'packages/oryvex_shared/Inter';
  static const display = 'packages/oryvex_shared/InterDisplay';
  static const mono = 'packages/oryvex_shared/JetBrainsMono';
  static const fallback = <String>['Segoe UI Variable Text', 'Segoe UI', 'Roboto', 'Noto Sans', 'Arial'];
  static const monoFallback = <String>['Cascadia Mono', 'Consolas', 'Roboto Mono', 'Noto Sans Mono', 'monospace'];

  // Short names used across the widgets.
  static Color get card => tile;
  static Color get cardHi => tileHi;
  static Color get line => hairline;
  static Color get muted => secondary;
  static Color get faint => tertiary;
  static Color get surface => tile;

  static void setDarkMode(bool dark) {
    darkMode = dark;
    canvas = dark ? const Color(0xFF0B0D12) : const Color(0xFFF5F5F7);
    nav = dark ? const Color(0xD9141720) : const Color(0xD9FBFBFD);
    tile = dark ? const Color(0xFF151922) : const Color(0xFFFFFFFF);
    tileHi = dark ? const Color(0xFF252B36) : const Color(0xFFE8E8ED);
    tileTop = dark ? const Color(0xFF202633) : const Color(0xFFFFFFFF);
    field = dark ? const Color(0xFF1C222D) : const Color(0xFFF0F0F3);
    hairline = dark ? const Color(0xFF303846) : const Color(0xFFD2D2D7);
    hairlineSoft = dark ? const Color(0xFF252C37) : const Color(0xFFE6E6EB);
    text = dark ? const Color(0xFFF4F6FA) : const Color(0xFF1D1D1F);
    secondary = dark ? const Color(0xFFA7B0BF) : const Color(0xFF6E6E73);
    tertiary = dark ? const Color(0xFF7E899A) : const Color(0xFF86868B);
    warn = dark ? const Color(0xFFFFB454) : const Color(0xFFC25E00);
    tileShadow = dark ? const <BoxShadow>[] : const <BoxShadow>[
      BoxShadow(color: Color(0x0F000000), blurRadius: 24, offset: Offset(0, 8)),
      BoxShadow(color: Color(0x08000000), blurRadius: 3, offset: Offset(0, 1)),
    ];
  }

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
  static TextStyle headline(double size, {Color? color, FontWeight weight = FontWeight.w700}) => TextStyle(
        fontFamily: display,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: 1.08,
        fontWeight: weight,
        letterSpacing: -0.022 * size,
        color: color ?? text,
      );

  static TextStyle body(double size, {Color? color, FontWeight weight = FontWeight.w400, double height = 1.42}) =>
      TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        letterSpacing: size >= 17 ? -0.022 * size * 0.5 : -0.003 * size,
        color: color ?? text,
      );

  /// The small blue line above a headline ("Protected", "Activity").
  static TextStyle eyebrow({Color? color}) => TextStyle(
        fontFamily: sans,
        fontFamilyFallback: fallback,
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        letterSpacing: -0.1,
        color: color ?? blue,
      );

  static TextStyle code(double size, {Color? color, FontWeight weight = FontWeight.w400, double height = 1.5}) =>
      TextStyle(
        fontFamily: mono,
        fontFamilyFallback: monoFallback,
        fontSize: size,
        height: height,
        fontWeight: weight,
        color: color ?? text,
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

ThemeData buildOxTheme({required bool dark}) {
  Ox.setDarkMode(dark);
  final scheme = dark ? ColorScheme.dark(
    primary: Ox.blue,
    onPrimary: Colors.white,
    primaryContainer: Ox.blueCta,
    onPrimaryContainer: Colors.white,
    secondary: Ox.blueSoft,
    onSecondary: Colors.white,
    surface: Ox.canvas,
    onSurface: Ox.text,
    surfaceContainerHighest: Ox.tileHi,
    outline: Ox.hairline,
    error: Ox.danger,
    onError: Colors.white,
  ) : ColorScheme.light(
    primary: Ox.blue,
    onPrimary: Colors.white,
    primaryContainer: Ox.blueCta,
    onPrimaryContainer: Colors.white,
    secondary: Ox.blueSoft,
    onSecondary: Colors.white,
    surface: Ox.canvas,
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
    brightness: dark ? Brightness.dark : Brightness.light,
    colorScheme: scheme,
    fontFamily: Ox.sans,
    fontFamilyFallback: Ox.fallback,
    scaffoldBackgroundColor: Ox.canvas,
    canvasColor: Ox.canvas,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: Colors.transparent,
    hoverColor: Colors.black.withValues(alpha: 0.04),
    focusColor: Ox.blue.withValues(alpha: 0.22),
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: transitions,
  );

  return base.copyWith(
    brightness: dark ? Brightness.dark : Brightness.light,
    textTheme: base.textTheme.apply(
      bodyColor: Ox.text,
      displayColor: Ox.text,
      fontFamily: Ox.sans,
    ),
    dividerTheme: DividerThemeData(color: Ox.hairlineSoft, thickness: 0.6, space: 0.6),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.disabled) ? Ox.tertiary : Colors.white,
      ),
      trackColor: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.disabled)) return Ox.tileHi;
        return s.contains(WidgetState.selected)
            ? const Color(0xFF34C759)
            : (dark ? const Color(0xFF454D5A) : const Color(0xFFE9E9EB));
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
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ox.radiusField),
        borderSide: BorderSide(color: Ox.hairlineSoft),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Ox.radiusField),
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
      thumbColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.22)),
      radius: const Radius.circular(8),
      thickness: const WidgetStatePropertyAll(6),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Ox.tile,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Ox.hairline),
      ),
      textStyle: Ox.body(14, color: Ox.text),
      waitDuration: const Duration(milliseconds: 500),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Ox.tile,
      contentTextStyle: Ox.body(15),
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      insetPadding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Ox.hairline),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: Ox.tile,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Ox.hairline),
      ),
      textStyle: Ox.body(15),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Ox.canvas,
      foregroundColor: Ox.text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: Ox.headline(22, weight: FontWeight.w600),
    ),
    cardTheme: CardThemeData(
      color: Ox.tile,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(Ox.radiusTile))),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(color: Ox.blue, linearTrackColor: Ox.tileHi),
    iconTheme: IconThemeData(color: Ox.text),
  );
}
