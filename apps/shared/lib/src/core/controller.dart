import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'errors.dart';
import 'log_line.dart';
import 'ports.dart';
import 'settings.dart';
import 'steps.dart';
import 'win_proxy.dart';

enum CoreState { stopped, starting, connecting, connected, reconnecting, stopping }

extension CoreStateText on CoreState {
  /// The big headline on the Connect page.
  String get headline => switch (this) {
        CoreState.stopped => 'Not connected.',
        CoreState.starting => 'Getting ready.',
        CoreState.connecting => 'Finding a way out.',
        CoreState.connected => 'Connected.',
        CoreState.reconnecting => 'Reconnecting.',
        CoreState.stopping => 'Disconnecting.',
      };

  String get label => switch (this) {
        CoreState.stopped => 'Off',
        CoreState.starting => 'Starting',
        CoreState.connecting => 'Connecting',
        CoreState.connected => 'Connected',
        CoreState.reconnecting => 'Reconnecting',
        CoreState.stopping => 'Stopping',
      };

  bool get busy =>
      this == CoreState.starting ||
      this == CoreState.connecting ||
      this == CoreState.reconnecting ||
      this == CoreState.stopping;
}

/// The one place app state lives. Turns the core's log stream into state a person can read.
///
/// Every connection is a session with its own id. Events that belong to an older session are
/// dropped, starts and stops never overlap, and a new start waits until the previous core has
/// let go of its ports. That is what makes Connect / Disconnect / Connect work every time.
class CoreController extends ChangeNotifier {
  CoreController(this.backend) : plan = ConnectionPlan.of(CoreSettings(), android: backend.isAndroid);

  final CoreBackend backend;

  CoreSettings settings = CoreSettings();
  CoreState state = CoreState.stopped;
  ConnectionPlan plan;

  final List<LogLine> logs = <LogLine>[];
  static const maxLogs = 3000;

  /// Bumped on every change to [logs], so views can tell cheaply whether to rebuild.
  int logRevision = 0;

  String? edge;
  String up = '0 B';
  String down = '0 B';
  String? coreUptime;
  DateTime? connectedAt;
  String? lastError;
  bool vpnUp = false;
  bool settingsDirty = false;

  /// Download and upload rate in bytes per second, newest last, for the live graph.
  final List<double> downRate = <double>[];
  final List<double> upRate = <double>[];
  static const _rateSamples = 48;

  /// Bumped for every new rate sample (the graphs animate the newest point in).
  int rateTick = 0;

  /// When the stage the Connect page is showing began, for its "taking a while" hint.
  DateTime? stageSince;
  String? _stageId;
  double? _lastUpBytes;
  double? _lastDownBytes;
  DateTime? _lastStatsAt;

  StreamSubscription<BackendEvent>? _sub;
  Timer? _notifyTimer;
  int _run = 0;
  bool _busy = false;
  bool _cancelRequested = false;
  bool _disposed = false;

  static final _stats = RegExp(r'\[=\] up (.+?) down (.+?) uptime (.+)$');
  static final _edgePatterns = <RegExp>[
    RegExp(r'using cloudflare edge (\S+)'),
    RegExp(r'selected WireGuard endpoint (\S+)'),
    RegExp(r'using forced peer (\S+)'),
    RegExp(r'cached gateway (\S+) still works'),
    RegExp(r'gool ready: masque (\S+)'),
    RegExp(r'masque-in-masque ready: (\S+)'),
  ];

  bool get isActive => state != CoreState.stopped;

  /// hh:mm:ss since the tunnel came up, ticking locally between the core's stats lines.
  String get uptime {
    final at = connectedAt;
    if (at == null || state != CoreState.connected) return coreUptime ?? '—';
    final d = DateTime.now().difference(at);
    String two(int v) => v.toString().padLeft(2, '0');
    final days = d.inDays;
    final hms = '${two(d.inHours % 24)}:${two(d.inMinutes % 60)}:${two(d.inSeconds % 60)}';
    return days > 0 ? '${days}d $hms' : hms;
  }

  /// The power button may be pressed: never while a stop is being carried out.
  bool get canToggle => state != CoreState.stopping;

  Future<void> init() async {
    settings = await CoreSettings.load();
    plan = ConnectionPlan.of(settings, android: backend.isAndroid);
    if (Platform.isWindows) {
      // A crash while the system proxy pointed at us must not leave the user offline.
      WinProxy.restore();
    }
    _sub = backend.events.listen(_onEvent);
    final st = await backend.status();
    if (st.running) {
      // Android: the service kept the core running while the UI was closed. Pick it back up.
      _run = st.run;
      state = CoreState.connecting;
      vpnUp = st.vpnUp;
      plan.begin();
      for (final l in st.lines) {
        _ingest(l);
      }
      plan.vpn(vpnUp);
    }
    _notify();
  }

  Future<void> toggle() async {
    switch (state) {
      case CoreState.stopped:
        await start();
      case CoreState.stopping:
        break;
      default:
        await stop();
    }
  }

  Future<void> start() async {
    if (state != CoreState.stopped || _busy) return;
    final problem = settings.problem(android: backend.isAndroid);
    if (problem != null) {
      lastError = problem;
      _notify();
      return;
    }

    _busy = true;
    _cancelRequested = false;
    final run = DateTime.now().millisecondsSinceEpoch;
    _run = run;
    lastError = null;
    edge = null;
    up = '0 B';
    down = '0 B';
    coreUptime = null;
    connectedAt = null;
    vpnUp = false;
    settingsDirty = false;
    downRate.clear();
    upRate.clear();
    rateTick++;
    _lastUpBytes = null;
    _lastDownBytes = null;
    _lastStatsAt = null;
    plan = ConnectionPlan.of(settings, android: backend.isAndroid)..begin();
    state = CoreState.starting;
    _notify();

    try {
      // An earlier core may still be letting go of its ports: give it a moment, then say so.
      final busy = await waitForPorts(
        settings.portsInUse(android: backend.isAndroid),
        shareLan: settings.shareLan,
      );
      if (_cancelRequested) {
        _finishCancelled(run);
        return;
      }
      if (busy.isNotEmpty) {
        throw BackendException(
            '${busy.join(' and ')} ${busy.length == 1 ? 'is' : 'are'} already in use by another app. '
            'Close it, or pick another port in Settings.');
      }
      await backend.start(settings.copy(), run);
      if (_run != run) return;
      if (_cancelRequested) {
        await backend.stop();
        _finishCancelled(run);
        return;
      }
      if (state == CoreState.starting) state = CoreState.connecting;
    } on BackendException catch (e) {
      _failStart(run, e.message);
    } catch (e) {
      _failStart(run, friendlyError('$e'));
    } finally {
      _busy = false;
      _notify();
    }
  }

  void _failStart(int run, String message) {
    if (_run != run) return;
    lastError = message;
    state = CoreState.stopped;
    plan.reset();
    _gui('[gui] could not connect: $message');
  }

  void _finishCancelled(int run) {
    if (_run != run) return;
    state = CoreState.stopped;
    plan.reset();
    _gui('[gui] cancelled');
  }

  Future<void> stop() async {
    if (state == CoreState.stopped || state == CoreState.stopping) return;
    if (state == CoreState.starting) {
      // start() is still in flight; it sees this and winds down on its own.
      _cancelRequested = true;
      state = CoreState.stopping;
      _notify();
      return;
    }
    final run = _run;
    state = CoreState.stopping;
    _notify();
    try {
      await backend.stop();
    } catch (_) {}
    if (_run == run && state == CoreState.stopping) _markStopped();
    _notify();
  }

  void _markStopped() {
    state = CoreState.stopped;
    vpnUp = false;
    connectedAt = null;
    plan.reset();
  }

  Future<void> updateSettings(void Function(CoreSettings s) edit) async {
    edit(settings);
    if (isActive) settingsDirty = true;
    if (!isActive) plan = ConnectionPlan.of(settings, android: backend.isAndroid);
    _notify();
    await settings.save();
  }

  /// Disconnects, then connects again with the current settings.
  Future<void> reconnect() async {
    await stop();
    await start();
  }

  void dismissError() {
    lastError = null;
    _notify();
  }

  void clearLogs() {
    logs.clear();
    logRevision++;
    _notify();
  }

  String exportLogs() => logs.map((l) => l.toString()).join('\n');

  void _onEvent(BackendEvent e) {
    // Late events of a session that is already over (or not ours) change nothing.
    if (e.run != 0 && _run != 0 && e.run != _run) return;
    switch (e) {
      case LineEvent(:final line):
        _ingest(line);
      case ExitEvent(:final code):
        if (state == CoreState.stopped) break;
        final wasStopping = state == CoreState.stopping;
        _markStopped();
        if (!wasStopping && lastError == null) {
          lastError = code != null && code != 0
              ? 'The core stopped (exit code $code). Open Activity to see why.'
              : 'The core stopped unexpectedly. Open Activity to see why.';
        }
      case VpnEvent(:final up, :final error):
        vpnUp = up;
        plan.vpn(up);
        if (error != null) lastError = error;
    }
    _scheduleNotify();
  }

  void _gui(String text) => _ingest(text);

  void _ingest(String raw) {
    if (raw.trim().isEmpty) return;
    final line = LogLine.parse(raw);
    if (logs.isNotEmpty && logs.last.sameAs(line)) {
      logs.last.repeat++;
    } else {
      logs.add(line);
      if (logs.length > maxLogs) logs.removeRange(0, logs.length - maxLogs);
    }
    logRevision++;

    final msg = line.message;
    if (plan.ingest(msg)) {
      if (plan.ready &&
          (state == CoreState.connecting ||
              state == CoreState.reconnecting ||
              state == CoreState.starting)) {
        state = CoreState.connected;
        connectedAt ??= DateTime.now();
        lastError = null;
      }
    }
    if (msg.contains('reconnecting') && state == CoreState.connected) {
      state = CoreState.reconnecting;
    }

    final s = _stats.firstMatch(msg);
    if (s != null) {
      up = s.group(1)!;
      down = s.group(2)!;
      coreUptime = s.group(3)!.trim();
      _sampleRates(up, down);
    }
    for (final p in _edgePatterns) {
      final m = p.firstMatch(msg);
      if (m != null) {
        edge = m.group(1);
        break;
      }
    }
    if (line.level == LogLevel.error && state != CoreState.connected && state != CoreState.stopping) {
      lastError = friendlyError(msg);
    }
    _scheduleNotify();
  }

  static double? parseBytes(String text) {
    final m = RegExp(r'^([0-9.]+)\s*([KMGT]?i?B)$').firstMatch(text.trim());
    if (m == null) return null;
    final v = double.tryParse(m.group(1)!) ?? 0;
    const mult = {'B': 1, 'KiB': 1024, 'MiB': 1048576, 'GiB': 1073741824, 'TiB': 1099511627776};
    final unit = m.group(2)!.replaceAll('i', '').replaceAll('B', '');
    final key = unit.isEmpty ? 'B' : '${unit}iB';
    return v * (mult[key] ?? 1);
  }

  void _sampleRates(String upText, String downText) {
    final u = parseBytes(upText);
    final d = parseBytes(downText);
    final now = DateTime.now();
    if (u == null || d == null) return;
    final lastAt = _lastStatsAt;
    if (lastAt != null && _lastUpBytes != null && _lastDownBytes != null) {
      final dt = now.difference(lastAt).inMilliseconds / 1000.0;
      if (dt > 0.2) {
        double rate(double now, double before) => now >= before ? (now - before) / dt : 0;
        downRate.add(rate(d, _lastDownBytes!));
        upRate.add(rate(u, _lastUpBytes!));
        rateTick++;
        if (downRate.length > _rateSamples) downRate.removeAt(0);
        if (upRate.length > _rateSamples) upRate.removeAt(0);
      }
    }
    _lastUpBytes = u;
    _lastDownBytes = d;
    _lastStatsAt = now;
  }

  void _notify() {
    if (_disposed) return;
    final busy = state == CoreState.starting || state == CoreState.connecting || state == CoreState.reconnecting;
    final id = busy ? plan.current?.id : null;
    if (id != _stageId) {
      _stageId = id;
      stageSince = id == null ? null : DateTime.now();
    }
    notifyListeners();
  }

  /// Current download / upload speed in bytes per second (the newest sample).
  double get downNow => downRate.isEmpty ? 0 : downRate.last;
  double get upNow => upRate.isEmpty ? 0 : upRate.last;

  /// "1.4 MB/s", "820 KB/s", "0 B/s".
  static String formatRate(double bytesPerSecond) {
    const units = ['B/s', 'KB/s', 'MB/s', 'GB/s'];
    var v = bytesPerSecond < 0 ? 0.0 : bytesPerSecond;
    var u = 0;
    while (v >= 1000 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    final text = u == 0 || v >= 100 ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
    return '$text ${units[u]}';
  }

  void _scheduleNotify() {
    // Batch bursts of log lines: cheap phones stay smooth even with verbose logs.
    _notifyTimer ??= Timer(const Duration(milliseconds: 100), () {
      _notifyTimer = null;
      _notify();
    });
  }

  Future<void> shutdown() async {
    await backend.shutdown();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
