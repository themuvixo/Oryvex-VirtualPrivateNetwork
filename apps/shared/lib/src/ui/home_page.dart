import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/args.dart';
import '../core/controller.dart';
import '../core/settings.dart';
import 'theme.dart';
import 'widgets/brand.dart';
import 'widgets/motion.dart';
import 'widgets/orb.dart';
import 'widgets/section.dart';
import 'widgets/sparkline.dart';
import 'widgets/steps_view.dart';

/// The Connect page, laid out like an apple.com product page: a small blue eyebrow, a huge
/// headline that says where you stand, one line of detail, the orb, one call to action. Below
/// the fold: live progress while connecting, a bento grid of live numbers, then the route.
class HomePage extends StatelessWidget {
  const HomePage({super.key, required this.controller, this.onOpenActivity, this.showHeader = true});

  final CoreController controller;
  final VoidCallback? onOpenActivity;

  /// The brand row at the top. Off when a top navigation bar already shows it.
  final bool showHeader;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final c = controller;
        final pad = MediaQuery.paddingOf(context);
        final width = MediaQuery.sizeOf(context).width;
        final compact = width < 640;
        final orbSize = (math.min(width, 560.0) * 0.64).clamp(210.0, 300.0);
        final busy = c.state == CoreState.starting ||
            c.state == CoreState.connecting ||
            c.state == CoreState.reconnecting;

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(20, pad.top + 10, 20, pad.bottom + 28),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: Ox.contentMax),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (showHeader)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: Row(
                        children: [
                          const OxMark(size: 28),
                          const SizedBox(width: 10),
                          const Flexible(child: OxWordmark(size: 21)),
                          const Spacer(),
                          StatusPill(state: c.state, vpnUp: c.vpnUp),
                        ],
                      ),
                    ),
                  _Hero(controller: c, orbSize: orbSize, compact: compact, onOpenActivity: onOpenActivity),
                  _Collapsible(
                    show: c.lastError != null,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 22),
                      child: _Banner(
                        icon: Icons.error_outline_rounded,
                        color: Ox.danger,
                        message: c.lastError ?? '',
                        onClose: c.dismissError,
                        action: onOpenActivity == null ? null : OxLink('Details', onTap: onOpenActivity),
                      ),
                    ),
                  ),
                  _Collapsible(
                    show: c.settingsDirty && c.isActive,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 14),
                      child: _Banner(
                        icon: Icons.tune_rounded,
                        color: Ox.warn,
                        message: 'Settings changed. Reconnect to use them.',
                        action: OxLink('Reconnect', onTap: c.canToggle ? c.reconnect : null),
                      ),
                    ),
                  ),
                  _Collapsible(
                    show: busy,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 26),
                      child: StepsView(plan: c.plan, stageSince: c.stageSince, onOpenActivity: onOpenActivity),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Reveal(delay: const Duration(milliseconds: 120), child: _Bento(controller: c)),
                  const SizedBox(height: 14),
                  Reveal(delay: const Duration(milliseconds: 220), child: _RouteAndMode(controller: c)),
                  const SizedBox(height: 18),
                  const OxCredit(),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Grows open / folds shut around [child] and cross-fades it.
class _Collapsible extends StatelessWidget {
  const _Collapsible({required this.show, required this.child});

  final bool show;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: Ox.medium,
      curve: Ox.easeOut,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: Ox.medium,
        switchInCurve: Ox.easeOut,
        switchOutCurve: Ox.easeIn,
        transitionBuilder: (child, a) => FadeTransition(
          opacity: a,
          child: SlideTransition(
            position: Tween<Offset>(begin: const Offset(0, -0.04), end: Offset.zero).animate(a),
            child: child,
          ),
        ),
        child: show ? KeyedSubtree(key: const ValueKey('on'), child: child) : const SizedBox(key: ValueKey('off'), width: double.infinity),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.controller, required this.orbSize, required this.compact, this.onOpenActivity});

  final CoreController controller;
  final double orbSize;
  final bool compact;
  final VoidCallback? onOpenActivity;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final step = c.plan.current;
    final route = s.torOnly
        ? 'Tor only'
        : '${Choices.protocolLong(s.protocol)}${usesMasqueCarrier(s.protocol) ? ' over ${Choices.transports[s.transport]}' : ''}';

    final (String eyebrow, Color eyebrowColor) = switch (c.state) {
      CoreState.stopped => ('Private by design', Ox.blue),
      CoreState.starting => ('Getting ready', Ox.blue),
      CoreState.connecting => (step?.title ?? 'Connecting', Ox.blue),
      CoreState.connected => (c.vpnUp ? 'Protected · every app' : 'Protected', Ox.blue),
      CoreState.reconnecting => ('Hold on', Ox.warn),
      CoreState.stopping => ('One moment', Ox.secondary),
    };

    final String sub = switch (c.state) {
      CoreState.connected => c.edge != null ? 'via ${c.edge}  ·  $route' : route,
      CoreState.connecting || CoreState.reconnecting => step?.detail ?? route,
      CoreState.starting => 'Checking your ports',
      CoreState.stopping => 'Closing the tunnel',
      CoreState.stopped => '$route  ·  ${Choices.scans[s.scan]} scan',
    };

    return Column(
      children: [
        const SizedBox(height: 6),
        BlurSwitcher(
          child: Text(eyebrow,
              key: ValueKey<String>('e$eyebrow'), textAlign: TextAlign.center, style: Ox.eyebrow(color: eyebrowColor)),
        ),
        const SizedBox(height: 6),
        BlurSwitcher(
          child: Text(
            c.state.headline,
            key: ValueKey<CoreState>(c.state),
            textAlign: TextAlign.center,
            style: Ox.headline(compact ? 44 : 64),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 24,
          child: BlurSwitcher(
            duration: const Duration(milliseconds: 380),
            child: Text(
              sub,
              key: ValueKey<String>(sub),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Ox.body(17, color: Ox.secondary),
            ),
          ),
        ),
        const SizedBox(height: 22),
        ConnectOrb(
          state: c.state,
          progress: c.plan.progress,
          size: orbSize,
          onTap: c.canToggle ? c.toggle : null,
        ),
        const SizedBox(height: 20),
        _Cta(state: c.state, onTap: c.canToggle ? c.toggle : null),
        if (onOpenActivity != null) ...[
          const SizedBox(height: 14),
          OxLink('View activity', onTap: onOpenActivity),
        ],
      ],
    );
  }
}

/// The pill call to action under the orb: filled blue to connect, quiet grey to stop.
class _Cta extends StatelessWidget {
  const _Cta({required this.state, required this.onTap});

  final CoreState state;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final primary = state == CoreState.stopped;
    final label = switch (state) {
      CoreState.stopped => 'Connect',
      CoreState.connected => 'Disconnect',
      CoreState.stopping => 'Disconnecting',
      _ => 'Cancel',
    };
    return Center(
      child: Pressable(
        onTap: onTap,
        semanticLabel: label,
        borderRadius: BorderRadius.circular(99),
        child: AnimatedContainer(
          duration: Ox.medium,
          curve: Ox.easeInOut,
          constraints: const BoxConstraints(minWidth: 190),
          height: 50,
          padding: const EdgeInsets.symmetric(horizontal: 28),
          decoration: BoxDecoration(
            color: primary ? Ox.blueCta : Ox.tileHi,
            borderRadius: BorderRadius.circular(99),
          ),
          alignment: Alignment.center,
          child: BlurSwitcher(
            duration: const Duration(milliseconds: 360),
            child: Text(
              label,
              key: ValueKey<String>(label),
              style: Ox.body(17,
                  weight: FontWeight.w600, color: state == CoreState.stopping ? Ox.secondary : Colors.white),
            ),
          ),
        ),
      ),
    );
  }
}

/// The small frosted status capsule: a dot that breathes while working, and a word.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.state, required this.vpnUp, this.dense = false, this.showLabel = true});

  final CoreState state;
  final bool vpnUp;
  final bool dense;

  /// Off on narrow bars: the dot alone still tells the state, by colour and pulse.
  final bool showLabel;

  @override
  Widget build(BuildContext context) {
    final on = state == CoreState.connected;
    final text = on ? (vpnUp ? 'VPN on' : 'Online') : (state.busy ? state.label : 'Off');
    final color = on ? Ox.blue : (state == CoreState.reconnecting ? Ox.warn : (state.busy ? Ox.blueSoft : Ox.tertiary));
    return AnimatedContainer(
      duration: Ox.medium,
      curve: Ox.easeInOut,
      padding: EdgeInsets.symmetric(horizontal: dense ? 10 : 12, vertical: dense ? 5 : 7),
      decoration: BoxDecoration(
        color: on ? Ox.blue.withValues(alpha: 0.16) : Ox.tile,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _PulseDot(color: color, pulsing: state.busy),
          if (showLabel) ...[
            const SizedBox(width: 7),
            AnimatedSize(
              duration: Ox.medium,
              curve: Ox.easeOut,
              child: Text(text, style: Ox.body(dense ? 13 : 14, weight: FontWeight.w600, color: on ? Ox.text : Ox.secondary)),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseDot extends StatefulWidget {
  const _PulseDot({required this.color, required this.pulsing});

  final Color color;
  final bool pulsing;

  @override
  State<_PulseDot> createState() => _PulseDotState();
}

class _PulseDotState extends State<_PulseDot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _c.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant _PulseDot old) {
    super.didUpdateWidget(old);
    if (widget.pulsing && !_c.isAnimating) {
      _c.repeat(reverse: true);
    } else if (!widget.pulsing && _c.isAnimating) {
      _c.animateTo(0, duration: Ox.fast);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final v = Curves.easeInOut.transform(_c.value);
        return TweenAnimationBuilder<Color?>(
          tween: ColorTween(end: widget.color),
          duration: Ox.medium,
          builder: (context, color, _) => Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(color: (color ?? widget.color).withValues(alpha: 0.55 * v), blurRadius: 8, spreadRadius: 1.5 * v),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.icon, required this.color, required this.message, this.onClose, this.action});

  final IconData icon;
  final Color color;
  final String message;
  final VoidCallback? onClose;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: Color.alphaBlend(color.withValues(alpha: 0.10), Ox.tile),
        borderRadius: BorderRadius.circular(Ox.radiusGroup),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, color: color, size: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(message, maxLines: 5, overflow: TextOverflow.ellipsis, style: Ox.body(15)),
                if (action != null) Padding(padding: const EdgeInsets.only(top: 6), child: action),
              ],
            ),
          ),
          if (onClose != null)
            IconButton(
              tooltip: 'Dismiss',
              visualDensity: VisualDensity.compact,
              onPressed: onClose,
              icon: const Icon(Icons.close_rounded, size: 18, color: Ox.secondary),
            ),
        ],
      ),
    );
  }
}

/// The live numbers, as an apple.com bento grid: two speed tiles with graphs, session time and
/// the gateway in use. Four across when there is room, two otherwise.
class _Bento extends StatelessWidget {
  const _Bento({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final on = c.state == CoreState.connected;
    return LayoutBuilder(
      builder: (context, box) {
        const gap = 12.0;
        final cols = box.maxWidth >= 720 ? 4 : 2;
        final w = (box.maxWidth - gap * (cols - 1)) / cols;
        final tiles = <Widget>[
          _MetricTile(
            icon: Icons.south_rounded,
            label: 'Download',
            value: CoreController.formatRate(c.downNow),
            foot: '${c.down} total',
            graph: Sparkline(samples: c.downRate, tick: c.rateTick, color: Ox.blue),
          ),
          _MetricTile(
            icon: Icons.north_rounded,
            label: 'Upload',
            value: CoreController.formatRate(c.upNow),
            foot: '${c.up} total',
            graph: Sparkline(samples: c.upRate, tick: c.rateTick, color: Ox.blueSoft),
          ),
          Ticking(
            enabled: on,
            builder: (context) => _MetricTile(
              icon: Icons.schedule_rounded,
              label: 'Session',
              value: on ? c.uptime : '00:00:00',
              mono: true,
              foot: on ? 'Tunnel up' : 'Starts when you connect',
            ),
          ),
          _MetricTile(
            icon: Icons.hub_outlined,
            label: 'Gateway',
            value: c.edge ?? '—',
            mono: true,
            foot: c.settings.torOnly ? 'Tor' : Choices.protocolLong(c.settings.protocol),
          ),
        ];
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [for (final t in tiles) SizedBox(width: w, height: 168, child: t)],
        );
      },
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.foot,
    this.graph,
    this.mono = false,
  });

  final IconData icon;
  final String label;
  final String value;
  final String foot;
  final Widget? graph;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return OxTile(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: Ox.blue),
              const SizedBox(width: 6),
              Expanded(child: Text(label, maxLines: 1, style: Ox.body(14, color: Ox.secondary, weight: FontWeight.w500))),
            ],
          ),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: AnimatedSwitcher(
              duration: Ox.fast,
              child: Text(
                value,
                key: ValueKey<String>(value),
                maxLines: 1,
                style: mono
                    ? Ox.code(22, weight: FontWeight.w600, height: 1.2)
                    : Ox.headline(26, weight: FontWeight.w700),
              ),
            ),
          ),
          const Spacer(),
          if (graph != null) graph!,
          if (graph != null) const SizedBox(height: 6),
          Text(foot, maxLines: 1, overflow: TextOverflow.ellipsis, style: Ox.body(13, color: Ox.tertiary)),
        ],
      ),
    );
  }
}

/// Route, mode and local proxy. Side by side on wide windows, stacked on phones.
class _RouteAndMode extends StatelessWidget {
  const _RouteAndMode({required this.controller});

  final CoreController controller;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    final s = c.settings;
    final route = OxTile(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Route', style: Ox.headline(22, weight: FontWeight.w600)),
          const SizedBox(height: 14),
          if (s.torOnly)
            Text('Tor only is on: the tunnel is skipped. Change it under Settings › Extra exit.',
                style: Ox.body(15, color: Ox.secondary))
          else ...[
            Segmented(
              options: Choices.protocols,
              value: s.protocol,
              onChanged: (v) => c.updateSettings((x) => x.protocol = v),
            ),
            const SizedBox(height: 10),
            _Hint(Choices.protocolHints[s.protocol] ?? ''),
            if (usesMasqueCarrier(s.protocol)) ...[
              const SizedBox(height: 18),
              Text('Carrier', style: Ox.body(15, weight: FontWeight.w500)),
              const SizedBox(height: 10),
              Segmented(
                options: Choices.transports,
                value: s.transport,
                onChanged: (v) => c.updateSettings((x) => x.transport = v),
              ),
            ],
            const SizedBox(height: 18),
            Text('Scan', style: Ox.body(15, weight: FontWeight.w500)),
            const SizedBox(height: 10),
            ChoicePills(
              options: Choices.scans,
              value: s.scan,
              onChanged: (v) => c.updateSettings((x) => x.scan = v),
            ),
            const SizedBox(height: 10),
            _Hint(Choices.scanHints[s.scan] ?? ''),
          ],
        ],
      ),
    );

    final host = s.shareLan ? '0.0.0.0' : '127.0.0.1';
    final showHttp = s.httpProxy || (c.backend.supportsSystemProxy && s.systemProxy);
    final mode = OxTile(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text('Mode', style: Ox.headline(22, weight: FontWeight.w600)),
          ),
          const SizedBox(height: 6),
          if (c.backend.supportsVpn)
            SwitchRow(
              title: 'Whole-device VPN',
              subtitle: s.vpnMode ? 'Every app goes through $kAppName' : 'Proxy only: point apps at the address below',
              value: s.vpnMode,
              onChanged: (v) => c.updateSettings((x) => x.vpnMode = v),
            ),
          if (c.backend.supportsSystemProxy)
            SwitchRow(
              title: 'Windows system proxy',
              subtitle: 'Browsers and most apps follow it while connected',
              value: s.systemProxy,
              onChanged: (v) => c.updateSettings((x) => x.systemProxy = v),
            ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            child: Text('Local proxy', style: Ox.body(15, weight: FontWeight.w500, color: Ox.secondary)),
          ),
          const SizedBox(height: 4),
          _AddressRow(label: 'SOCKS5', address: '$host:${s.socksPort}'),
          if (showHttp) _AddressRow(label: 'HTTP', address: '$host:${s.httpPort}'),
          if (s.chain == 'tor' && !s.torOnly) _AddressRow(label: 'Tor', address: '$host:${s.torPort}'),
          if (s.chain == 'psiphon' && c.backend.supportsPsiphon)
            _AddressRow(label: 'Psiphon', address: '$host:${s.psiphonPort}'),
        ],
      ),
    );

    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth >= 720) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: route),
              const SizedBox(width: 12),
              Expanded(flex: 2, child: mode),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [route, const SizedBox(height: 12), mode],
        );
      },
    );
  }
}

class _Hint extends StatelessWidget {
  const _Hint(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: Ox.medium,
      switchInCurve: Ox.easeOut,
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.topLeft,
        children: [...previous, if (current != null) current],
      ),
      child: Text(text, key: ValueKey<String>(text), style: Ox.body(14, color: Ox.secondary)),
    );
  }
}

class _AddressRow extends StatelessWidget {
  const _AddressRow({required this.label, required this.address});

  final String label;
  final String address;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 2, 4, 2),
      child: Row(
        children: [
          SizedBox(width: 72, child: Text(label, style: Ox.body(15, color: Ox.secondary))),
          Expanded(child: SelectableText(address, maxLines: 1, style: Ox.code(15, weight: FontWeight.w500))),
          IconButton(
            tooltip: 'Copy',
            icon: const Icon(Icons.copy_rounded, size: 18, color: Ox.blue),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: address));
              ScaffoldMessenger.maybeOf(context)
                  ?.showSnackBar(SnackBar(content: Text('$label address copied'), duration: const Duration(seconds: 2)));
            },
          ),
        ],
      ),
    );
  }
}
