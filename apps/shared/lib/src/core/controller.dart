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
import 'sstp.dart';
import 'sstp_servers.dart';
import 'steps.dart';
import 'vpngate.dart';
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

  // --- Auto ---------------------------------------------------------------------------------

  /// The protocol the running (or last) attempt uses. In Auto it changes as Auto moves on.
  String? activeProtocol;

  /// Which entry of [Choices.autoOrder] Auto is on.
  int autoIndex = 0;
  Timer? _attemptTimer;
  Timer? _verificationTimer;
  bool _switching = false;

  // --- SSTP (Windows and Android) -------------------------------------------------------------

  /// The VPN Gate servers SSTP can dial: the bundled list until a refresh replaces it.
  List<SstpServer> sstpServers = bundledSstpServers;

  /// When [sstpServers] was fetched from vpngate.net; null for the bundled list.
  DateTime? sstpUpdatedAt;
  bool sstpRefreshing = false;

  /// The server the current SSTP session is connected to.
  SstpServer? sstpConnected;
  Timer? _sstpPoll;
  int _sstpMisses = 0;
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

  /// Windows uses RasClient; Android uses the integrated MS-SSTP engine in OryvexVpnService.
  bool get supportsSstp => backend.isAndroid || SstpClient.supported;

  /// Auto is picking the protocol for this connection.
  bool get isAuto => settings.protocol == 'auto' && !settings.torOnly;

  bool get _sstpMode => settings.protocol == 'sstp' && !settings.torOnly && supportsSstp;

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
    if (settings.protocol == 'sstp' && !supportsSstp) settings.protocol = 'auto';
    plan = ConnectionPlan.of(settings, android: backend.isAndroid);
    if (supportsSstp) {
      final (servers, at) = await VpnGateDirectory.load();
      sstpServers = servers;
      sstpUpdatedAt = at;
      // An SSTP session the app can no longer see (it was closed while connected) is hung up,
      // so the switch and Windows never disagree.
      unawaited(SstpClient.disconnect());
    }
    if (Platform.isWindows) {
      // A crash while the system proxy pointed at us must not leave the user offline.
      WinProxy.restore();
    }
    _sub = backend.events.listen(_onEvent);
    final st = await backend.status();
    if (st.running) {
      // Android: the service kept the core running while the UI was closed. Pick it back up.
      _run = st.run;
      if (backend.isAndroid && settings.protocol == 'sstp') activeProtocol = 'sstp';
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
    final problem = _sstpMode ? null : settings.problem(android: backend.isAndroid);
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

    if (_sstpMode) {
      await _startSstp();
      return;
    }
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
    activeProtocol = settings.torOnly ? null : attempt.protocol;
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
          'Try the Thorough scan, HTTP/2${supportsSstp ? ', or SSTP' : ''}.';
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
    if (state == CoreState.stopped || state == CoreState.stopping) return;
    if (activeProtocol == 'sstp' && backend.isAndroid) {
      _cancelRequested = true;
      state = CoreState.stopping;
      _notify();
      await backend.stop();
      if (state == CoreState.stopping) _markStopped();
      unawaited(refreshIp());
      _notify();
      return;
    }
    if (activeProtocol == 'sstp') {
      // Hanging up also ends a dial that is still in progress.
      _cancelRequested = true;
      state = CoreState.stopping;
      _notify();
      _sstpPoll?.cancel();
      _sstpPoll = null;
      await SstpClient.disconnect();
      if (!_busy && state == CoreState.stopping) {
        _markStopped();
        _gui('[gui] sstp: disconnected');
        unawaited(refreshIp());
      }
      _notify();
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

  void _markStopped() {
    state = CoreState.stopped;
    vpnUp = false;
    connectedAt = null;
    activeProtocol = null;
    sstpConnected = null;
    _attemptTimer?.cancel();
    _attemptTimer = null;
    _verificationTimer?.cancel();
    _verificationTimer = null;
    _sstpPoll?.cancel();
    _sstpPoll = null;
    // The speed tiles fall back to zero instead of freezing on the last sample.
    downRate.clear();
    upRate.clear();
    rateTick++;
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
        if (activeProtocol == 'sstp' && backend.isAndroid) {
          final wasConnected = state == CoreState.connected;
          final wasStopping = state == CoreState.stopping;
          _markStopped();
          if (!wasStopping && lastError == null) {
            lastError = wasConnected
                ? 'The SSTP connection dropped. Connect again to choose a relay.'
                : 'SSTP could not connect. Open Activity for the failure reason.';
            if (wasConnected) _gui('[gui] sstp: connection dropped');
          }
          unawaited(refreshIp());
          break;
        }
        if (activeProtocol == 'sstp') break;
        if (isAuto && !_switching && state == CoreState.connecting) {
          // The attempt died before it connected: Auto moves on instead of stopping.
          unawaited(_failover(_run, code != null && code != 0 ? 'the core exited with code $code' : 'the core exited'));
          break;
        }
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
    if (plan.ingest(msg) && plan.ready &&
        (state == CoreState.connecting ||
            state == CoreState.reconnecting ||
            state == CoreState.starting)) {
      // The engine's "ready" line only proves the tunnel handshake. Keep the UI in
      // Connecting until an HTTPS request through the route returns HTTP 200.
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
    if (activeProtocol == 'sstp') await SstpClient.disconnect();
    await backend.shutdown();
  }

  // --- SSTP ---------------------------------------------------------------------------------

  /// The servers SSTP tries, in order: the chosen one first, then the best by VPN Gate's score
  /// that report some throughput.
  List<SstpServer> _sstpCandidates() {
    final ranked = List<SstpServer>.of(sstpServers)
      ..sort((a, b) {
        final live = (b.mbps > 0 ? 1 : 0).compareTo(a.mbps > 0 ? 1 : 0);
        return live != 0 ? live : b.score.compareTo(a.score);
      });
    final chosen = settings.sstpServer.trim();
    if (chosen.isEmpty) return ranked;
    final pick = ranked.where((x) => x.address == chosen).toList();
    if (pick.isEmpty) {
      // A server typed in by hand, or one a refresh no longer lists: try it first anyway.
      final parts = chosen.split(':');
      final manual = SstpServer.parseAddress(chosen);
      if (manual != null) pick.add(manual);
    }
    return [...pick, ...ranked.where((x) => x.address != chosen)];
  }

  /// Fetches a fresh server list from vpngate.net. With [quiet], failures are only logged.
  Future<bool> refreshSstpServers({bool quiet = false}) async {
    if (!supportsSstp || sstpRefreshing) return false;
    sstpRefreshing = true;
    _notify();
    try {
      final fresh = await VpnGateDirectory.refresh();
      sstpServers = fresh;
      sstpUpdatedAt = DateTime.now();
      _gui('[gui] sstp: list ready, ${fresh.length} servers from vpngate.net');
      return true;
    } catch (e) {
      _gui('[gui] sstp: could not refresh the server list ($e); using the saved one');
      if (!quiet) lastError = 'Could not reach vpngate.net to refresh the SSTP servers. The saved list still works.';
      return false;
    } finally {
      sstpRefreshing = false;
      _notify();
    }
  }

  Future<void> _startSstp() async {
    _busy = true;
    final run = math.max(DateTime.now().millisecondsSinceEpoch, _run + 1);
    _run = run;
    activeProtocol = 'sstp';
    edge = null;
    coreUptime = null;
    connectedAt = null;
    vpnUp = false;
    sstpConnected = null;
    _lastUpBytes = null;
    _lastDownBytes = null;
    _lastStatsAt = null;
    plan = ConnectionPlan.of(settings, android: backend.isAndroid)..begin();
    state = CoreState.starting;
    _notify();

    try {
      // Never fetch the directory during connect or retry. Use the bundled/cached list;
      // the Settings refresh action is the only network refresh path.
      _gui('[gui] sstp: list ready, ${sstpServers.length} saved servers (manual refresh only)');
      state = CoreState.connecting;
      _notify();

      const tries = 6;
      final candidates = _sstpCandidates().take(tries).toList();
      if (backend.isAndroid) {
        final server = candidates.isNotEmpty ? candidates.first : null;
        if (server == null || !server.isValid) {
          throw BackendException('No valid VPN Gate SSTP relay is available. Refresh the server list.');
        }
        settings.sstpServer = server.address;
        _gui('[gui] sstp: dialing ${server.address} (${server.country.isEmpty ? 'VPN Gate' : server.country})');
        await backend.start(settings.copy(), run);
        if (_cancelRequested || _run != run) return;
        sstpConnected = server;
        if (state != CoreState.connected) state = CoreState.connecting;
        _busy = false;
        _notify();
        return;
      }
      for (final server in candidates) {
        if (_cancelRequested || _run != run) break;
        _gui('[gui] sstp: dialing ${server.address} (${server.country.isEmpty ? 'VPN Gate' : server.country})');
        final error = await SstpClient.connect(server);
        if (_cancelRequested || _run != run) break;
        if (error == null) {
          sstpConnected = server;
          edge = server.address;
          plan.completeAll(readyDetail: server.label);
          _gui('[gui] sstp: tunnel established; checking HTTPS traffic');
          final verified = await _verifyAndMarkConnected(run, directRoute: true);
          if (!verified) {
            await SstpClient.disconnect();
            throw BackendException('SSTP connected, but the HTTPS traffic check did not return HTTP 200.');
          }
          if (_run == run && state == CoreState.connected) {
            _gui('[gui] sstp: connected to ${server.address}');
            _startSstpPoll(run);
          }
          return;
        }
        _gui('[gui] sstp: ${server.address} did not connect: $error');
      }
      if (_cancelRequested || _run != run) {
        await SstpClient.disconnect();
        _finishCancelled(run);
        return;
      }
      throw BackendException('None of the $tries best SSTP servers answered. '
          'Refresh the server list in Settings, or pick another server.');
    } on BackendException catch (e) {
      _failStart(run, e.message);
    } catch (e) {
      _failStart(run, friendlyError('$e'));
    } finally {
      _busy = false;
      _notify();
    }
  }

  /// Verify the tunnel with HTTPS before reporting Connected. Core routes use SOCKS;
  /// Windows SSTP uses the OS-routed adapter.
  Future<bool> _verifyAndMarkConnected(int run, {bool directRoute = false}) async {
    if (_verificationRun == run || _run != run || state == CoreState.stopped ||
        state == CoreState.stopping) return false;
    _verificationRun = run;
    _attemptTimer?.cancel();
    _attemptTimer = null;
    _gui('[gui] verify: testing HTTPS through the tunnel (HTTP 200 required)');
    try {
      // IpLookup tries two independently hosted HTTPS endpoints and accepts only 200 responses.
      // Core protocols go through the local SOCKS proxy; Windows SSTP uses its system route.
      final result = await IpLookup.lookup(
        socksPort: directRoute ? null : IpLookup.socksPortForRoute(
          tunnelConnected: true,
          activeProtocol: activeProtocol,
          configuredSocksPort: settings.socksPort,
        ),
        throughTunnel: true,
        timeout: const Duration(seconds: 8),
      );
      if (_run != run || state == CoreState.stopped || state == CoreState.stopping) return false;
      if (result == null) {
        lastError = 'Tunnel handshake succeeded, but the HTTPS traffic check got no HTTP 200 response. Still verifying, not marked connected.';
        _gui('[gui] verify: HTTPS check failed; connection is not marked connected');
        if (isAuto && _run == run) {
          unawaited(_failover(run, 'HTTPS verification did not return HTTP 200'));
        } else if (!directRoute && _run == run && state != CoreState.stopped && state != CoreState.stopping) {
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
      connectedAt ??= DateTime.now();
      ipInfo = result;
      lastError = null;
      _attemptTimer?.cancel();
      _attemptTimer = null;
      _gui('[gui] verify: HTTPS returned 200 via ${result.ip}');
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

  void _startSstpPoll(int run) {
    _sstpPoll?.cancel();
    _sstpMisses = 0;
    var polling = false;
    _sstpPoll = Timer.periodic(const Duration(seconds: 2), (_) async {
      if (polling || _run != run || state != CoreState.connected) return;
      polling = true;
      try {
        final counters = await SstpClient.counters();
        if (_run != run || state != CoreState.connected) return;
        if (counters == null) {
          _sstpMisses++;
          if (_sstpMisses >= 3 && !await SstpClient.isConnected()) {
            if (_run != run || state != CoreState.connected) return;
            _markStopped();
            lastError = 'The SSTP connection dropped. Connect again to pick another server.';
            _gui('[gui] sstp: the connection dropped');
            unawaited(refreshIp());
            _notify();
          }
          return;
        }
        _sstpMisses = 0;
        down = _formatBytes(counters.down);
        up = _formatBytes(counters.up);
        _sampleBytes(counters.up.toDouble(), counters.down.toDouble(), DateTime.now());
        _notify();
      } finally {
        polling = false;
      }
    });
  }

  static String _formatBytes(int bytes) {
    const units = ['B', 'KiB', 'MiB', 'GiB', 'TiB'];
    var v = bytes.toDouble();
    var u = 0;
    while (v >= 1024 && u < units.length - 1) {
      v /= 1024;
      u++;
    }
    return u == 0 ? '$bytes B' : '${v.toStringAsFixed(1)} ${units[u]}';
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
        activeProtocol: activeProtocol,
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
    _sub?.cancel();
    _notifyTimer?.cancel();
    super.dispose();
  }
}
