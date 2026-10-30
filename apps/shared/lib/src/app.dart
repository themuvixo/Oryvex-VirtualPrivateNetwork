import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import 'core/backend.dart';
import 'core/controller.dart';
import 'core/internet_check.dart';
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

class _OryvexAppState extends State<OryvexApp> with WindowListener {
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final SystemTray _systemTray = SystemTray();
  bool _trayReady = false;
  bool _closeDialogOpen = false;
  bool _offlineDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_checkInternetAndShowDialog()));
    if (Platform.isWindows) {
      windowManager.addListener(this);
      unawaited(_initTray());
    }
  }

  Future<void> _checkInternetAndShowDialog() async {
    if (!mounted || _offlineDialogOpen) return;
    final online = await hasInternetAccess();
    if (!mounted || online || _offlineDialogOpen) return;
    final context = _navigatorKey.currentContext;
    if (context == null) return;

    _offlineDialogOpen = true;
    await showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Internet connection unavailable',
      barrierColor: Colors.black.withValues(alpha: 0.58),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => _OfflineDialog(
        onRetry: hasInternetAccess,
      ),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(curved), child: child),
        );
      },
    );
    _offlineDialogOpen = false;
  }

  Future<void> _initTray() async {
    try {
      final exe = File(Platform.resolvedExecutable).parent.path;
      final icon = '$exe\\data\\flutter_assets\\assets\\app_icon.ico';
      await _systemTray.initSystemTray(iconPath: icon, toolTip: 'OryvexVPN');
      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(label: 'Show OryvexVPN', onClicked: (_) => unawaited(_showWindow())),
        MenuSeparator(),
        MenuItemLabel(label: 'Quit OryvexVPN', onClicked: (_) => unawaited(_quitFromTray())),
      ]);
      await _systemTray.setContextMenu(menu);
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick) unawaited(_showWindow());
        if (eventName == kSystemTrayEventRightClick) unawaited(_systemTray.popUpContextMenu());
      });
      _trayReady = true;
    } catch (_) {
      _trayReady = false;
    }
  }

  Future<void> _quitFromTray() async {
    await widget.controller.shutdown();
    await windowManager.setPreventClose(false);
    await windowManager.close();
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  @override
  void onWindowClose() => unawaited(_askCloseChoice());

  Future<void> _askCloseChoice() async {
    final context = _navigatorKey.currentContext;
    if (context == null || !mounted || _closeDialogOpen) return;
    _closeDialogOpen = true;
    final choice = await showGeneralDialog<String>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close options',
      barrierColor: Colors.black.withValues(alpha: 0.55),
      transitionDuration: const Duration(milliseconds: 240),
      pageBuilder: (context, animation, secondaryAnimation) => _CloseChoiceDialog(trayReady: _trayReady),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(opacity: curved, child: ScaleTransition(scale: Tween<double>(begin: 0.94, end: 1).animate(curved), child: child));
      },
    );
    _closeDialogOpen = false;
    if (choice == 'tray' && _trayReady) {
      await windowManager.hide();
    } else if (choice == 'quit') {
      await widget.controller.shutdown();
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }

  @override
  void dispose() {
    if (Platform.isWindows) windowManager.removeListener(this);
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
          navigatorKey: _navigatorKey,
          debugShowCheckedModeBanner: false,
          // Build one selected palette and pin it to both platform brightnesses. Ox is a
          // shared token set used by custom-painted widgets, so building separate light/dark
          // themes here would leave the last palette built active for both modes.
          theme: selectedTheme,
          darkTheme: selectedTheme,
          themeMode: ThemeMode.light,
          home: Platform.isWindows
              ? DragToResizeArea(child: Shell(controller: widget.controller))
              : Shell(controller: widget.controller),
        );
      },
    );
  }
}

class _OfflineDialog extends StatefulWidget {
  const _OfflineDialog({required this.onRetry});

  final Future<bool> Function() onRetry;

  @override
  State<_OfflineDialog> createState() => _OfflineDialogState();
}

class _OfflineDialogState extends State<_OfflineDialog> {
  bool _checking = false;
  String? _status;

  Future<void> _retry() async {
    if (_checking) return;
    setState(() {
      _checking = true;
      _status = null;
    });
    final online = await widget.onRetry();
    if (!mounted) return;
    setState(() {
      _checking = false;
      _status = online ? null : 'Still offline. Check your connection and try again.';
    });
    if (online) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: double.infinity,
          constraints: const BoxConstraints(maxWidth: 410),
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Ox.card,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Ox.hairlineSoft),
            boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.38), blurRadius: 48, offset: const Offset(0, 20))],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: Ox.danger.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(15)),
                child: const Icon(Icons.wifi_off_rounded, color: Ox.danger, size: 25),
              ),
              const SizedBox(height: 18),
              Text('No internet connection', style: Ox.headline(22)),
              const SizedBox(height: 8),
              Text(
                'OryvexVPN can’t reach the internet right now. Check your Wi-Fi or mobile data, then try again.',
                style: Ox.body(14, color: Ox.secondary),
              ),
              if (_status != null) ...[
                const SizedBox(height: 12),
                Text(_status!, style: Ox.body(13, color: Ox.warn)),
              ],
              const SizedBox(height: 22),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _checking ? null : () => Navigator.of(context).pop(),
                    child: Text('Continue offline', style: Ox.body(14, color: Ox.secondary, weight: FontWeight.w600)),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: _checking ? null : _retry,
                    icon: _checking
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.refresh_rounded, size: 18),
                    label: Text(_checking ? 'Checking…' : 'Try again'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CloseChoiceDialog extends StatelessWidget {
  const _CloseChoiceDialog({required this.trayReady});
  final bool trayReady;

  @override
  Widget build(BuildContext context) {
    final options = <Widget>[
      if (trayReady)
        _CloseOption(icon: Icons.notifications_active_outlined, title: 'Keep running in tray', subtitle: 'Hide the window, leave the VPN running', value: 'tray'),
      _CloseOption(icon: Icons.power_settings_new_rounded, title: 'Quit OryvexVPN', subtitle: 'Disconnect and close the app', value: 'quit'),
      _CloseOption(icon: Icons.arrow_back_rounded, title: 'Cancel', subtitle: 'Go back to the app', value: 'cancel'),
    ];
    return Center(
      child: Material(
        color: Colors.transparent,
        child: Container(
          width: 390,
          margin: const EdgeInsets.all(24),
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(color: Ox.card, borderRadius: BorderRadius.circular(22), border: Border.all(color: Ox.hairlineSoft), boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 48, offset: const Offset(0, 20))]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Close OryvexVPN?', style: Ox.headline(22)),
            const SizedBox(height: 7),
            Text('Choose what happens to your connection.', style: Ox.body(14, color: Ox.secondary)),
            const SizedBox(height: 18),
            ...options.map((option) => Padding(padding: const EdgeInsets.only(top: 8), child: option)),
          ]),
        ),
      ),
    );
  }
}

class _CloseOption extends StatelessWidget {
  const _CloseOption({required this.icon, required this.title, required this.subtitle, required this.value});
  final IconData icon;
  final String title, subtitle, value;

  @override
  Widget build(BuildContext context) => InkWell(
    borderRadius: BorderRadius.circular(14),
    onTap: () => Navigator.of(context).pop(value == 'cancel' ? null : value),
    child: Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(color: Ox.nav, borderRadius: BorderRadius.circular(14), border: Border.all(color: Ox.hairlineSoft)),
      child: Row(children: [
        Icon(icon, color: Ox.blue, size: 20),
        const SizedBox(width: 12),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: Ox.body(14, weight: FontWeight.w600)),
          const SizedBox(height: 3),
          Text(subtitle, style: Ox.body(12, color: Ox.secondary)),
        ])),
        Icon(Icons.chevron_right_rounded, color: Ox.secondary, size: 19),
      ]),
    ),
  );
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
                  child: MediaQuery(data: inner, child: PageSwitcher(index: _tab, children: pages)),
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
  const _TopNav({required this.controller, required this.index, required this.onSelect, required this.topInset, required this.width});
  final CoreController controller;
  final int index;
  final ValueChanged<int> onSelect;
  final double topInset;
  final double width;

  @override
  Widget build(BuildContext context) {
    final tabW = width < 500 ? 64.0 : 88.0;
    final bar = _Glass(
      child: Container(
        height: topInset + Ox.navHeight,
        padding: EdgeInsets.only(top: topInset, left: 18, right: Platform.isWindows ? 0 : 14),
        decoration: BoxDecoration(color: Ox.nav, border: Border(bottom: BorderSide(color: Ox.hairlineSoft, width: 0.6))),
        child: Row(children: [
          Expanded(child: Row(children: [const OxMark(size: 22), const SizedBox(width: 9), Flexible(child: OxWordmark(size: width < 420 ? 14 : 17))])),
          SizedBox(
            width: tabW * _destinations.length,
            height: 34,
            child: Stack(children: [
              AnimatedPositioned(
                duration: context.reduceMotion ? Duration.zero : Ox.medium,
                curve: Ox.easeOut,
                left: tabW * index,
                top: 0,
                bottom: 0,
                width: tabW,
                child: Container(decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.06), borderRadius: BorderRadius.circular(99))),
              ),
              Row(children: [
                for (var i = 0; i < _destinations.length; i++)
                  SizedBox(
                    width: tabW,
                    child: Pressable(
                      onTap: () => onSelect(i),
                      scale: 0.95,
                      semanticLabel: _destinations[i].label,
                      borderRadius: BorderRadius.circular(99),
                      child: Center(child: AnimatedDefaultTextStyle(
                        duration: Ox.fast,
                        style: Ox.body(14, weight: i == index ? FontWeight.w600 : FontWeight.w500, color: i == index ? Ox.text : Ox.secondary),
                        child: Text(_destinations[i].label),
                      )),
                    ),
                  ),
              ]),
            ]),
          ),
          Expanded(child: Align(
            alignment: Alignment.centerRight,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              ListenableBuilder(
                listenable: controller,
                builder: (context, _) => StatusPill(state: controller.state, vpnUp: controller.vpnUp, dense: true, showLabel: width >= 600),
              ),
              if (Platform.isWindows) ...[
                const SizedBox(width: 12),
                Container(width: 1, height: 20, color: Ox.hairlineSoft),
                const SizedBox(width: 6),
                const _WindowControls(),
              ],
            ]),
          )),
        ]),
      ),
    );
    return Platform.isWindows ? DragToMoveArea(child: bar) : bar;
  }
}

class _WindowControls extends StatefulWidget {
  const _WindowControls();
  @override
  State<_WindowControls> createState() => _WindowControlsState();
}

/// OryvexVPN's own caption buttons. The native Windows title bar is hidden, so these replace
/// it: flush with the window edge, full bar height, hand-drawn hairline glyphs, a red close.
/// The maximise glyph follows the real window state, and everything dims while unfocused.
class _WindowControlsState extends State<_WindowControls> with WindowListener {
  bool _maximized = false;
  bool _focused = true;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_syncMaximized());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _syncMaximized() async {
    final value = await windowManager.isMaximized();
    if (mounted && value != _maximized) setState(() => _maximized = value);
  }

  @override
  void onWindowMaximize() => setState(() => _maximized = true);
  @override
  void onWindowUnmaximize() => setState(() => _maximized = false);
  @override
  void onWindowRestore() => unawaited(_syncMaximized());
  @override
  void onWindowFocus() => setState(() => _focused = true);
  @override
  void onWindowBlur() => setState(() => _focused = false);

  Future<void> _toggleMaximize() async {
    if (await windowManager.isMaximized()) {
      await windowManager.unmaximize();
    } else {
      await windowManager.maximize();
    }
    await _syncMaximized();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    duration: Ox.fast,
    opacity: _focused ? 1 : 0.55,
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      _CaptionButton(glyph: _Glyph.minimize, label: 'Minimize', onPressed: windowManager.minimize),
      _CaptionButton(
        glyph: _maximized ? _Glyph.restore : _Glyph.maximize,
        label: _maximized ? 'Restore down' : 'Maximize',
        onPressed: _toggleMaximize,
      ),
      // close() goes through setPreventClose, so the "Close OryvexVPN?" dialog still asks.
      _CaptionButton(glyph: _Glyph.close, label: 'Close', onPressed: windowManager.close, close: true),
    ]),
  );
}

enum _Glyph { minimize, maximize, restore, close }

class _CaptionButton extends StatefulWidget {
  const _CaptionButton({required this.glyph, required this.label, required this.onPressed, this.close = false});
  final _Glyph glyph;
  final String label;
  final VoidCallback onPressed;
  final bool close;

  @override
  State<_CaptionButton> createState() => _CaptionButtonState();
}

class _CaptionButtonState extends State<_CaptionButton> {
  static const _closeRed = Color(0xFFE81123); // the Windows close-button red
  bool _hover = false;
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    if (widget.close) {
      fill = _down ? const Color(0xFFF1707A) : (_hover ? _closeRed : Colors.transparent);
    } else {
      fill = _down ? Ox.text.withValues(alpha: 0.14) : (_hover ? Ox.text.withValues(alpha: 0.08) : Colors.transparent);
    }
    final ink = widget.close && (_hover || _down) ? Colors.white : Ox.text;
    return Semantics(
      button: true,
      label: widget.label,
      child: Tooltip(
        message: widget.label,
        waitDuration: const Duration(milliseconds: 600),
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() { _hover = false; _down = false; }),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapDown: (_) => setState(() => _down = true),
            onTapCancel: () => setState(() => _down = false),
            onTap: () {
              setState(() => _down = false);
              widget.onPressed();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: 46,
              height: Ox.navHeight,
              color: fill,
              alignment: Alignment.center,
              child: CustomPaint(size: const Size(10, 10), painter: _GlyphPainter(widget.glyph, ink)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline caption glyphs, drawn rather than taken from an icon font so they stay crisp at
/// every scale and match the 1 px weight of the Windows 11 caption.
class _GlyphPainter extends CustomPainter {
  const _GlyphPainter(this.glyph, this.color);
  final _Glyph glyph;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.05
      ..isAntiAlias = true;
    final w = size.width, h = size.height;
    switch (glyph) {
      case _Glyph.minimize:
        canvas.drawLine(Offset(0, h / 2), Offset(w, h / 2), p);
      case _Glyph.maximize:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.5, 0.5, w - 1, h - 1), const Radius.circular(1.5)), p);
      case _Glyph.restore:
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0.5, 2.5, w - 3, h - 3), const Radius.circular(1.2)), p);
        final back = Path()
          ..moveTo(2.5, 2.5)
          ..lineTo(2.5, 0.5)
          ..lineTo(w - 0.5, 0.5)
          ..lineTo(w - 0.5, h - 2.5)
          ..lineTo(w - 2.5, h - 2.5);
        canvas.drawPath(back, p);
      case _Glyph.close:
        canvas.drawLine(Offset.zero, Offset(w, h), p);
        canvas.drawLine(Offset(w, 0), Offset(0, h), p);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.glyph != glyph || old.color != color;
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
