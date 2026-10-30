import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/backend.dart';
import 'core/controller.dart';
import 'ui/home_page.dart';
import 'ui/logs_page.dart';
import 'ui/settings_page.dart';
import 'ui/theme.dart';
import 'ui/widgets/brand.dart';
import 'ui/widgets/motion.dart';

/// Boots OryvexVPN on [backend]. Each app (desktop-src, android-src) calls this from main(),
/// after `WidgetsFlutterBinding.ensureInitialized()`.
Future<void> runOryvex(CoreBackend backend) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isAndroid) {
    // Draw behind the status and navigation bars (Android 15 enforces it anyway); the pages pad
    // themselves with the system insets.
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
      statusBarBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarDividerColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.dark,
      systemNavigationBarContrastEnforced: false,
    ));
  }
  Ox.setDarkMode(true);
  final controller = CoreController(backend);
  await controller.init();
  runApp(OryvexApp(controller: controller));
}

class OryvexApp extends StatefulWidget {
  const OryvexApp({super.key, required this.controller});

  final CoreController controller;

  @override
  State<OryvexApp> createState() => _OryvexAppState();
}

class _OryvexAppState extends State<OryvexApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        // Desktop: closing the window takes the core (and the system proxy) down with it.
        await widget.controller.shutdown();
        return ui.AppExitResponse.exit;
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    widget.controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final dark = widget.controller.settings.darkTheme;
        Ox.setDarkMode(dark);
        if (Platform.isAndroid) {
          SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            statusBarBrightness: dark ? Brightness.dark : Brightness.light,
            systemNavigationBarColor: Colors.transparent,
            systemNavigationBarDividerColor: Colors.transparent,
            systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
            systemNavigationBarContrastEnforced: false,
          ));
        }
        final selectedTheme = buildOxTheme(dark: dark);
        return MaterialApp(
          title: kAppName,
          debugShowCheckedModeBanner: false,
          // Build one selected palette and pin it to both platform brightnesses. Ox is a
          // shared token set used by custom-painted widgets, so building separate light/dark
          // themes here would leave the last palette built active for both modes.
          theme: selectedTheme,
          darkTheme: selectedTheme,
          themeMode: ThemeMode.light,
          home: Shell(controller: widget.controller),
        );
      },
    );
  }
}

class _Dest {
  const _Dest(this.icon, this.selectedIcon, this.label);

  final IconData icon;
  final IconData selectedIcon;
  final String label;
}

const _destinations = <_Dest>[
  _Dest(Icons.shield_outlined, Icons.shield_rounded, 'Connect'),
  _Dest(Icons.receipt_long_outlined, Icons.receipt_long_rounded, 'Activity'),
  _Dest(Icons.tune_outlined, Icons.tune_rounded, 'Settings'),
];

/// The frame around the three pages. Desktop (and tablets) get apple.com's frosted global nav
/// along the top; phones get a floating frosted tab bar at the bottom, within thumb reach.
/// Either way the pages move with a shared-axis transition and keep their state.
class Shell extends StatefulWidget {
  const Shell({super.key, required this.controller});

  final CoreController controller;

  @override
  State<Shell> createState() => _ShellState();
}

class _ShellState extends State<Shell> {
  int _tab = 0;

  void _go(int i) {
    if (i == _tab) return;
    setState(() => _tab = i);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    final mq = MediaQuery.of(context);
    final width = mq.size.width;
    final topNav = !c.backend.isAndroid || width >= 760;

    final pages = <Widget>[
      HomePage(controller: c, onOpenActivity: () => _go(1), showHeader: !topNav),
      LogsPage(controller: c),
      SettingsPage(controller: c),
    ];

    // The pages pad themselves with MediaQuery's padding: add the bars to it.
    final inner = mq.copyWith(
      padding: mq.padding.copyWith(
        top: topNav ? mq.padding.top + Ox.navHeight : mq.padding.top,
        bottom: topNav ? mq.padding.bottom : mq.padding.bottom + Ox.tabBarHeight + 20,
      ),
    );

    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): () => _go(0),
        const SingleActivator(LogicalKeyboardKey.digit2, control: true): () => _go(1),
        const SingleActivator(LogicalKeyboardKey.digit3, control: true): () => _go(2),
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: Ox.canvas,
          body: TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 700),
            curve: Ox.easeOut,
            builder: (context, v, child) => Opacity(
              opacity: v,
              child: Transform.scale(scale: 0.985 + 0.015 * v, child: child),
            ),
            child: Stack(
              children: [
                Positioned.fill(
                  child: MediaQuery(
                    data: inner,
                    child: PageSwitcher(index: _tab, children: pages),
                  ),
                ),
                if (topNav)
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopNav(controller: c, index: _tab, onSelect: _go, topInset: mq.padding.top, width: width),
                  )
                else
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _TabBar(index: _tab, onSelect: _go, bottomInset: mq.padding.bottom),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Frosted glass: whatever scrolls underneath shows through, blurred.
class _Glass extends StatelessWidget {
  const _Glass({required this.child, this.borderRadius = BorderRadius.zero});

  final Widget child;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: child,
      ),
    );
  }
}

class _TopNav extends StatelessWidget {
  const _TopNav({
    required this.controller,
    required this.index,
    required this.onSelect,
    required this.topInset,
    required this.width,
  });

  final CoreController controller;
  final int index;
  final ValueChanged<int> onSelect;
  final double topInset;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tabW = width < 500 ? 64.0 : 88.0;
    return _Glass(
      child: Container(
        height: topInset + Ox.navHeight,
        padding: EdgeInsets.only(top: topInset, left: 18, right: 14),
        decoration: BoxDecoration(
          color: Ox.nav,
          border: Border(bottom: BorderSide(color: Ox.hairlineSoft, width: 0.6)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  const OxMark(size: 22),
                  const SizedBox(width: 9),
                  Flexible(child: OxWordmark(size: width < 420 ? 14 : 17)),
                ],
              ),
            ),
            SizedBox(
              width: tabW * _destinations.length,
              height: 34,
              child: Stack(
                children: [
                  AnimatedPositioned(
                    duration: context.reduceMotion ? Duration.zero : Ox.medium,
                    curve: Ox.easeOut,
                    left: tabW * index,
                    top: 0,
                    bottom: 0,
                    width: tabW,
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < _destinations.length; i++)
                        SizedBox(
                          width: tabW,
                          child: Pressable(
                            onTap: () => onSelect(i),
                            scale: 0.95,
                            semanticLabel: _destinations[i].label,
                            borderRadius: BorderRadius.circular(99),
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: Ox.fast,
                                style: Ox.body(14,
                                    weight: i == index ? FontWeight.w600 : FontWeight.w500,
                                    color: i == index ? Ox.text : Ox.secondary),
                                child: Text(_destinations[i].label),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Align(
                alignment: Alignment.centerRight,
                child: ListenableBuilder(
                  listenable: controller,
                  builder: (context, _) => StatusPill(
                    state: controller.state,
                    vpnUp: controller.vpnUp,
                    dense: true,
                    showLabel: width >= 600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TabBar extends StatelessWidget {
  const _TabBar({required this.index, required this.onSelect, required this.bottomInset});

  final int index;
  final ValueChanged<int> onSelect;
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 0, 18, bottomInset + 12),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(32),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 28, offset: const Offset(0, 10)),
              ],
            ),
            child: _Glass(
              borderRadius: BorderRadius.circular(32),
              child: Container(
                height: Ox.tabBarHeight,
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Ox.nav,
                  borderRadius: BorderRadius.circular(32),
                  border: Border.all(color: Colors.black.withValues(alpha: 0.06), width: 0.8),
                ),
                child: LayoutBuilder(
                  builder: (context, box) {
                    final seg = box.maxWidth / _destinations.length;
                    return Stack(
                      children: [
                        AnimatedPositioned(
                          duration: context.reduceMotion ? Duration.zero : Ox.medium,
                          curve: Ox.easeOut,
                          left: seg * index,
                          top: 0,
                          bottom: 0,
                          width: seg,
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.06),
                              borderRadius: BorderRadius.circular(26),
                            ),
                          ),
                        ),
                        Row(
                          children: [
                            for (var i = 0; i < _destinations.length; i++)
                              Expanded(
                                child: Pressable(
                                  onTap: () => onSelect(i),
                                  scale: 0.92,
                                  semanticLabel: _destinations[i].label,
                                  borderRadius: BorderRadius.circular(26),
                                  child: _TabItem(dest: _destinations[i], selected: i == index),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TabItem extends StatelessWidget {
  const _TabItem({required this.dest, required this.selected});

  final _Dest dest;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final color = selected ? Ox.blue : Ox.secondary;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        AnimatedScale(
          scale: selected ? 1.08 : 1.0,
          duration: Ox.medium,
          curve: Ox.easeOut,
          child: AnimatedSwitcher(
            duration: Ox.fast,
            child: Icon(
              selected ? dest.selectedIcon : dest.icon,
              key: ValueKey<bool>(selected),
              size: 22,
              color: color,
            ),
          ),
        ),
        const SizedBox(height: 3),
        AnimatedDefaultTextStyle(
          duration: Ox.fast,
          style: Ox.body(12, weight: selected ? FontWeight.w600 : FontWeight.w500, color: selected ? Ox.text : Ox.secondary, height: 1.1),
          child: Text(dest.label),
        ),
      ],
    );
  }
}
