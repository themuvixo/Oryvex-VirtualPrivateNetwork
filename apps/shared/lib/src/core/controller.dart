import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'backend.dart';
import 'errors.dart';
import 'ip_info.dart';
import 'log_line.dart';
import 'ports.dart';
import 'settings.dart';
import 'steps.dart';
import 'tor_exits.dart';
import 'win_proxy.dart';
import 'win_startup.dart';

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

  // --- Auto ---------------------------------------------------------------------------------

  /// The protocol the running (or last) attempt uses. In Auto it changes as Auto moves on.
  String? activeProtocol;

  /// Which entry of [Choices.autoOrder] Auto is on.
  int autoIndex = 0;
  Timer? _attemptTimer;
  Timer? _verificationTimer;
  bool _switching = false;

  // --- Auto reconnect -------------------------------------------------------------------------

  Timer? _reconnectTimer;
  int _reconnectTries = 0;
  static const _maxReconnectTries = 5;

  /// Waiting to bring a dropped connection back (shown on the Connect page).
  bool get reconnectPending => _reconnectTimer != null;

  // --- Tor exits (Windows and Android) --------------------------------------------------------

  /// The countries Tor can leave from: the bundled list until the core reports the directory it
  /// fetched through Tor, which is then saved for the next start.
  TorExitDirectory torExits = TorExitDirectory.bundled();

  /// The exit the running Tor proxy settled on: 'auto' or a lowercase country code.
  String? torExitInUse;

  /// How long the chosen exit took to answer, when the core measured it.
  int? torExitMs;
  int? _verificationRun;

  // --- Public address -------------------------------------------------------------------------

  /// The address and country the internet sees right now (null until the first lookup).
  IpInfo? ipInfo;
  bool ipLoading = false;
  int _ipSeq = 0;

  // "[=] up 1.2 MiB down 8.4 MiB uptime 00:03:02 bytes 1258291 8808038". Cores before 2.5
  // print no exact byte counts; the rounded totals are used then.
  static final _stats = RegExp(
      r'\[=\] up (.+?) down (.+?) uptime ((?:\d+d )?\d+:\d{2}:\d{2})(?: bytes (\d+) (\d+))?\s*$');
  static final _edgePatterns = <RegExp>[
    RegExp(r'using cloudflare edge (\S+)'),
    RegExp(r'selected WireGuard endpoint (\S+)'),
    RegExp(r'using forced peer (\S+)'),
    RegExp(r'cached gateway (\S+) still works'),
    RegExp(r'gool ready: masque (\S+)'),
    RegExp(r'masque-in-masque ready: (\S+)'),
  ];

  bool get isActive => state != CoreState.stopped;

  /// Auto is picking the protocol for this connection.
  bool get isAuto => settings.protocol == 'auto';

  /// Tor is in play: as the whole route, or as the extra exit carried by the tunnel.
  bool get usesTor => settings.torOnly || settings.chain == 'tor';

  /// The protocol to show: the one in use, or the one that will be tried first.
  String get routeProtocol => activeProtocol ?? (isAuto ? Choices.autoOrder.first : settings.protocol);

  /// "2 of 4" while Auto is working through its list.
  String? get autoStepLabel =>
      isAuto && activeProtocol != null && state != CoreState.stopped
          ? '${autoIndex + 1} of ${Choices.autoOrder.length}'
          : null;

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
    torExits = await TorExitDirectory.load();
    if (Platform.isWindows) {
      // A crash while the system proxy pointed at us must not leave the user offline.
      WinProxy.restore();
      // The installer may have added (or the user removed) the sign-in entry: trust Windows.
      final atStartup = WinStartup.isEnabled();
      if (atStartup != settings.launchAtStartup) {
        settings.launchAtStartup = atStartup;
        await settings.save();
      }
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
    unawaited(refreshIp());
    if (settings.autoConnect && state == CoreState.stopped) {
      _gui('[gui] connect on launch is on: connecting');
      unawaited(start());
    }
  }

  Future<void> toggle() async {
    switch (state) {
      case CoreState.stopped:
        if (_cancelReconnect()) {
          // The power button while a reconnect waits means "stop trying".
          _gui('[gui] auto reconnect cancelled');
          _notify();
          return;
        }
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

    _cancelRequested = false;
    lastError = null;
    up = '0 B';
    down = '0 B';
    settingsDirty = false;
    downRate.clear();
    upRate.clear();
    rateTick++;
    autoIndex = 0;
    torExitInUse = null;
    torExitMs = null;

    if (isAuto) {
      _gui('[gui] auto: will try ${Choices.autoOrder.map(Choices.protocolLong).join(', then ')}');
    }
    await _launch();
  }

  /// The settings one attempt runs with: Auto's current protocol in place of "auto".
  CoreSettings _attemptSettings() {
    final s = settings.copy();
    if (isAuto) s.protocol = Choices.autoOrder[autoIndex];
    return s;
  }

  /// Starts one core session with [_attemptSettings].
  Future<void> _launch() async {
    _busy = true;
    final run = math.max(DateTime.now().millisecondsSinceEpoch, _run + 1);
    _run = run;
    final attempt = _attemptSettings();
    activeProtocol = attempt.protocol;
    edge = null;
    coreUptime = null;
    connectedAt = null;
    vpnUp = false;
    _lastUpBytes = null;
    _lastDownBytes = null;
    _lastStatsAt = null;
    plan = ConnectionPlan.of(attempt, android: backend.isAndroid)..begin();
    state = CoreState.starting;
    _notify();

    try {
      // An earlier core may still be letting go of its ports: give it a moment, then say so.
      final busy = await waitForPorts(
        attempt.portsInUse(android: backend.isAndroid),
        shareLan: attempt.shareLan,
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
      if (isAuto) {
        _gui('[gui] auto: trying ${Choices.protocolLong(attempt.protocol)} '
            '(${autoIndex + 1} of ${Choices.autoOrder.length})');
      }
      await backend.start(attempt, run);
      if (_run != run) return;
      if (_cancelRequested) {
        await backend.stop();
        _finishCancelled(run);
        return;
      }
      if (state == CoreState.starting) state = CoreState.connecting;
      _armAttempt(run);
    } on BackendException catch (e) {
      _failStart(run, e.message);
    } catch (e) {
      _failStart(run, friendlyError('$e'));
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Gives an Auto attempt its time to come up; past it, Auto moves on to the next protocol.
  void _armAttempt(int run) {
    _attemptTimer?.cancel();
    _attemptTimer = null;
    if (!isAuto || state == CoreState.connected) return;
    final secs = Choices.autoTimeout(activeProtocol ?? Choices.autoOrder.first, settings.scan);
    _attemptTimer = Timer(Duration(seconds: secs), () {
      _attemptTimer = null;
      if (_run != run) return;
      if (state == CoreState.connecting) {
        unawaited(_failover(run, 'nothing after $secs s'));
      }
    });
  }

  /// Auto: drops the attempt of [run] and starts the next protocol, or gives up after Gool.
  Future<void> _failover(int run, String why) async {
    if (_run != run || _switching || !isAuto || _cancelRequested) return;
    if (state == CoreState.stopping || state == CoreState.stopped || state == CoreState.connected) return;
    _switching = true;
    _attemptTimer?.cancel();
    _attemptTimer = null;
    final from = Choices.protocolLong(activeProtocol ?? '');
    final last = autoIndex + 1 >= Choices.autoOrder.length;
    // Whatever the dropped session still says no longer counts.
    _run = run + 1;
    state = last ? CoreState.stopping : CoreState.starting;
    _notify();
    try {
      await backend.stop();
    } catch (_) {}
    _switching = false;

    if (last) {
      _markStopped();
      lastError = 'Auto tried WireGuard, MASQUE, MASQUE² and Gool, and none of them connected. '
          'Try the Thorough scan, HTTP/2, or the Tor route.';
      _gui('[gui] auto: $from did not connect either ($why); giving up');
      _notify();
      unawaited(refreshIp());
      return;
    }
    if (_cancelRequested) {
      _cancelRequested = false;
      _markStopped();
      _gui('[gui] cancelled');
      _notify();
      return;
    }
    autoIndex++;
    lastError = null;
    _gui('[gui] auto: $from did not connect ($why), moving on to '
        '${Choices.protocolLong(Choices.autoOrder[autoIndex])}');
    await _launch();
  }

  void _failStart(int run, String message) {
    if (_run != run) return;
    _markStopped();
    lastError = message;
    _gui('[gui] could not connect: $message');
  }

  void _finishCancelled(int run) {
    if (_run != run) return;
    _markStopped();
    _cancelRequested = false;
    _gui('[gui] cancelled');
    unawaited(refreshIp());
  }

  Future<void> stop() async {
    final hadPendingReconnect = _cancelReconnect();
    if (state == CoreState.stopped || state == CoreState.stopping) {
      if (hadPendingReconnect) {
        _gui('[gui] auto reconnect cancelled');
        _notify();
      }
      return;
    }
    if (state == CoreState.starting) {
      // start() (or an Auto switch) is still in flight; it sees this and winds down on its own.
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
    unawaited(refreshIp());
  }

  /// Cancels a scheduled auto reconnect. Returns whether one was pending.
  bool _cancelReconnect() {
    final pending = _reconnectTimer != null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    return pending;
  }

  /// The tunnel dropped by itself after it had been connected: try again, a few times.
  void _scheduleReconnect() {
    if (!settings.autoReconnect || _disposed || _reconnectTimer != null) return;
    if (_reconnectTries >= _maxReconnectTries) {
      _gui('[gui] auto reconnect: gave up after $_maxReconnectTries tries');
      return;
    }
    _reconnectTries++;
    final wait = Duration(seconds: 2 * _reconnectTries + 1);
    _gui('[gui] auto reconnect: try $_reconnectTries of $_maxReconnectTries in ${wait.inSeconds} s');
    _reconnectTimer = Timer(wait, () {
      _reconnectTimer = null;
      if (_disposed || state != CoreState.stopped) return;
      unawaited(start());
    });
  }

  void _markStopped() {
    state = CoreState.stopped;
    vpnUp = false;
    connectedAt = null;
    activeProtocol = null;
    torExitInUse = null;
    torExitMs = null;
    _attemptTimer?.cancel();
    _attemptTimer = null;
    _verificationTimer?.cancel();
    _verificationTimer = null;
    // The speed tiles fall back to zero instead of freezing on the last sample.
    downRate.clear();
    upRate.clear();
    rateTick++;
    plan.reset();
  }

  Future<void> updateSettings(void Function(CoreSettings s) edit) async {
    final startupBefore = (settings.launchAtStartup, settings.startInTray);
    edit(settings);
    if (Platform.isWindows && (settings.launchAtStartup, settings.startInTray) != startupBefore) {
      if (!WinStartup.apply(enabled: settings.launchAtStartup, inTray: settings.startInTray)) {
        lastError = 'Windows did not accept the sign-in setting. Try again, or run the installer.';
        settings.launchAtStartup = WinStartup.isEnabled();
      }
    }
    if (!settings.autoReconnect) _cancelReconnect();
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
        if (isAuto && !_switching && state == CoreState.connecting) {
          // The attempt died before it connected: Auto moves on instead of stopping.
          unawaited(_failover(_run, code != null && code != 0 ? 'the core exited with code $code' : 'the core exited'));
          break;
        }
        final wasStopping = state == CoreState.stopping;
        final wasUp = state == CoreState.connected || state == CoreState.reconnecting;
        _markStopped();
        if (!wasStopping && lastError == null) {
          lastError = code != null && code != 0
              ? 'The core stopped (exit code $code). Open Activity to see why.'
              : 'The core stopped unexpectedly. Open Activity to see why.';
        }
        if (!wasStopping && wasUp) _scheduleReconnect();
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

    // The core's exit directory: one machine-readable line, kept out of Activity.
    final directory = TorExitDirectory.fromLogLine(line.message);
    if (directory != null) {
      torExits = directory;
      if (directory.source != 'bundled') unawaited(directory.save());
      _scheduleNotify();
      return;
    }
    final exit = TorExitDirectory.exitInUse(line.message);
    if (exit != null) {
      torExitInUse = exit.$1;
      torExitMs = exit.$2;
    }
    if (logs.isNotEmpty && logs.last.sameAs(line)) {
      logs.last.repeat++;
    } else {
      logs.add(line);
      if (logs.length > maxLogs) logs.removeRange(0, logs.length - maxLogs);
    }
    logRevision++;

    final msg = line.message;
    if (plan.ingest(msg) && plan.ready &&
        (state == CoreState.connecting ||
            state == CoreState.reconnecting ||
            state == CoreState.starting)) {
      // The engine's "ready" line only proves the tunnel handshake. Keep the UI in
      // Connecting until a valid HTTPS response is received through the route.
      unawaited(_verifyAndMarkConnected(_run));
    }
    if (isAuto && state == CoreState.connecting && !_switching) {
      final lower = msg.toLowerCase();
      if (lower.contains('no clean endpoint') || lower.contains('scan deadline')) {
        unawaited(_failover(_run, 'no gateway answered'));
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
      final exactUp = double.tryParse(s.group(4) ?? '');
      final exactDown = double.tryParse(s.group(5) ?? '');
      // The core's own timestamp, not when the line got here: pipes deliver lines in bursts.
      _sampleBytes(exactUp ?? parseBytes(up), exactDown ?? parseBytes(down), line.time);
    }
    for (final p in _edgePatterns) {
      final m = p.firstMatch(msg);
      if (m != null) {
        edge = m.group(1);
        break;
      }
    }
    if (line.level == LogLevel.error &&
        state != CoreState.connected &&
        state != CoreState.stopping &&
        !isAuto) {
      // In Auto an attempt's errors are Auto's business: it moves on, and says so if all fail.
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

  void _sampleBytes(double? u, double? d, DateTime now) {
    if (u == null || d == null) return;
    final lastAt = _lastStatsAt;
    if (lastAt != null && _lastUpBytes != null && _lastDownBytes != null) {
      final dt = now.difference(lastAt).inMilliseconds / 1000.0;
      if (dt < 0.2) return; // Same second (a replayed backlog): wait for a real interval.
      {
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

  /// Verify the tunnel with HTTPS through the core's SOCKS5 proxy before reporting Connected.
  Future<bool> _verifyAndMarkConnected(int run) async {
    if (_verificationRun == run || _run != run || state == CoreState.stopped ||
        state == CoreState.stopping) return false;
    _verificationRun = run;
    _attemptTimer?.cancel();
    _attemptTimer = null;
    _gui('[gui] verify: checking HTTPS traffic through the tunnel');
    try {
      // Route health is independent of public-IP metadata: an unavailable lookup provider
      // must not make a working tunnel look broken. All probes use the local SOCKS route.
      final verified = await IpLookup.verifyConnectivity(
        socksPort: settings.socksPort,
        timeout: Duration(seconds: usesTor ? 20 : 12),
      );
      if (_run != run || state == CoreState.stopped || state == CoreState.stopping) return false;
      if (!verified) {
        lastError = 'No valid HTTPS response through the tunnel yet. Still checking, not marked connected.';
        _gui('[gui] verify: HTTPS check failed; connection is not marked connected');
        if (isAuto && _run == run) {
          unawaited(_failover(run, 'HTTPS verification did not receive a valid response'));
        } else if (_run == run && state != CoreState.stopped && state != CoreState.stopping) {
          _verificationTimer?.cancel();
          _verificationTimer = Timer(const Duration(seconds: 5), () {
            _verificationTimer = null;
            unawaited(_verifyAndMarkConnected(run));
          });
        }
        return false;
      }
      final first = connectedAt == null;
      state = CoreState.connected;
      _reconnectTries = 0;
      connectedAt ??= DateTime.now();
      if (ipInfo?.viaTunnel != true) ipInfo = null;
      lastError = null;
      _attemptTimer?.cancel();
      _attemptTimer = null;
      _gui('[gui] verify: HTTPS traffic confirmed through the tunnel');
      // Public-IP metadata is helpful, but should never delay or block connection state.
      unawaited(refreshIp());
      if (first && isAuto && activeProtocol != null) {
        _gui('[gui] auto: connected with ${Choices.protocolLong(activeProtocol!)}');
      }
      _verificationTimer?.cancel();
      _verificationTimer = null;
      _notify();
      return true;
    } finally {
      if (_verificationRun == run) _verificationRun = null;
      _notify();
    }
  }

  // --- Public address -------------------------------------------------------------------------

  /// Looks up the address and country the internet sees. Through the core's SOCKS5 port while
  /// a core tunnel is up (the app itself bypasses its own VPN), directly otherwise.
  Future<void> refreshIp() async {
    if (_disposed) return;
    final seq = ++_ipSeq;
    ipLoading = true;
    _notify();
    final viaTunnel = state == CoreState.connected;
    final info = await IpLookup.lookup(
      socksPort: IpLookup.socksPortForRoute(
        tunnelConnected: viaTunnel,
        configuredSocksPort: settings.socksPort,
      ),
      throughTunnel: viaTunnel,
    );
    if (_disposed || seq != _ipSeq) return;
    ipLoading = false;
    if (info != null) {
      ipInfo = info;
      _gui('[gui] ip: ${info.viaTunnel ? "tunnel" : "direct"} egress is ${info.ip}${info.countryCode.isEmpty ? "" : " (${info.countryCode})"}');
    } else {
      // Keep a previous successful value; a transient lookup failure must not erase it.
      _gui('[gui] ip: HTTPS lookup failed or timed out; keeping the last successful result');
    }
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    _cancelReconnect();
    _sub?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
