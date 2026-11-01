import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Every choice the GUI makes for the core. Each field maps onto CLI flags in `args.dart`.
class CoreSettings {
  CoreSettings();

  /// auto | wg | masque | mim | gool | tor.
  ///
  /// auto tries WireGuard, then MASQUE, then MASQUE², then Gool, and keeps the first one that
  /// connects. tor skips the tunnel: the proxy (and on Android the device VPN) is plain Tor.
  String protocol = 'auto';

  /// Where Tor leaves from, for the Tor route and for "Tor via tunnel": auto (Tor picks by
  /// bandwidth), fastest (the core measures the best-served countries) or a lowercase country
  /// code such as de.
  String torExit = 'auto';

  /// Fail instead of leaving from another country when the chosen exit country does not answer.
  bool torExitStrict = false;

  /// h3 | h2. Only the MASQUE carriers (masque, gool, mim) read it.
  String transport = 'h3';

  /// turbo | balanced | thorough | verified | ironclad
  String scan = 'balanced';

  /// auto (core default) | off | light | firewall | balanced | gfw | aggressive
  String noize = 'auto';

  /// v4 | v6 | both
  String ip = 'v4';

  int socksPort = 1819;
  bool shareLan = false;

  bool httpProxy = false;
  int httpPort = 1820;

  bool fragment = false;
  bool quickReconnect = true;

  /// off | tor (Tor through the tunnel) | psiphon (desktop). Plain Tor is the `tor` protocol.
  String chain = 'off';

  /// Where the extra Tor proxy listens with chain == tor. Kept clear of the HTTP port.
  int torPort = 1822;

  /// Where the extra Psiphon proxy listens with chain == psiphon.
  int psiphonPort = 1821;

  String dns = '';
  String exitLoc = '';
  String peer = '';

  /// Dark appearance is the first-launch default.
  bool darkTheme = true;

  /// Android: route the whole phone through the core with a VpnService.
  bool vpnMode = true;

  /// Android: answer DNS inside the VPN with mapped addresses (no UDP needed for lookups).
  bool fakeDns = true;

  /// Android: also tunnel IPv6 in VPN mode.
  bool vpnIpv6 = true;

  /// Windows: point the system (WinINet) proxy at the core's HTTP proxy while connected.
  bool systemProxy = false;

  bool verbose = false;
  String extraArgs = '';

  static const _key = 'oryvexcore.settings.v1';

  /// Bumped when the default protocol changed. Settings saved before 2 kept MASQUE only because
  /// it used to be the default, so they move to Auto once. 3 removed SSTP and made Tor a route.
  static const _protocolVersion = 3;

  /// No tunnel: the main proxy is plain Tor.
  bool get torOnly => protocol == 'tor';

  /// Tor's exit choice is in play for this configuration.
  bool get usesTorExit => torOnly || chain == 'tor';

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'protocolVersion': _protocolVersion,
        'torExit': torExit,
        'torExitStrict': torExitStrict,
        'transport': transport,
        'scan': scan,
        'noize': noize,
        'ip': ip,
        'socksPort': socksPort,
        'shareLan': shareLan,
        'httpProxy': httpProxy,
        'httpPort': httpPort,
        'fragment': fragment,
        'quickReconnect': quickReconnect,
        'chain': chain,
        'torPort': torPort,
        'psiphonPort': psiphonPort,
        'dns': dns,
        'exitLoc': exitLoc,
        'peer': peer,
        'darkTheme': darkTheme,
        'vpnMode': vpnMode,
        'fakeDns': fakeDns,
        'vpnIpv6': vpnIpv6,
        'systemProxy': systemProxy,
        'verbose': verbose,
        'extraArgs': extraArgs,
      };

  static CoreSettings fromJson(Map<String, dynamic> j) {
    final s = CoreSettings();
    String str(String k, String d, [Map<String, String>? allowed]) {
      final v = j[k];
      if (v is! String) return d;
      if (allowed != null && !allowed.containsKey(v)) return d;
      return v;
    }

    bool flag(String k, bool d) => j[k] is bool ? j[k] as bool : d;
    int port(String k, int d) {
      final v = j[k];
      return v is int && v > 0 && v < 65536 ? v : d;
    }

    // Unknown protocols (SSTP, removed in 3) fall back on Auto through the allowed list.
    s.protocol = str('protocol', s.protocol, Choices.protocols);
    final version = j['protocolVersion'];
    if ((version is! int || version < 2) && s.protocol == 'masque') s.protocol = 'auto';
    final exit = j['torExit'];
    if (exit is String && Choices.isTorExit(exit)) s.torExit = exit;
    s.torExitStrict = flag('torExitStrict', s.torExitStrict);
    s.transport = str('transport', s.transport, Choices.transports);
    s.scan = str('scan', s.scan, Choices.scans);
    s.noize = str('noize', s.noize, Choices.noizes);
    s.ip = str('ip', s.ip, Choices.ips);
    s.socksPort = port('socksPort', s.socksPort);
    s.shareLan = flag('shareLan', s.shareLan);
    s.httpProxy = flag('httpProxy', s.httpProxy);
    s.httpPort = port('httpPort', s.httpPort);
    s.fragment = flag('fragment', s.fragment);
    s.quickReconnect = flag('quickReconnect', s.quickReconnect);
    s.torPort = port('torPort', s.torPort);
    s.psiphonPort = port('psiphonPort', s.psiphonPort);

    final chain = j['chain'];
    if (chain == 'tor-only') {
      // Before 3, plain Tor was an "extra exit"; it is a route of its own now.
      s.protocol = 'tor';
    } else if (chain is String && Choices.chains.containsKey(chain)) {
      s.chain = chain;
    } else {
      // Settings saved by 2.4.0 kept Tor and Psiphon apart; fold them into one choice.
      final tor = j['tor'];
      final psiphon = j['psiphon'];
      if (tor == 'only') {
        s.protocol = 'tor';
      } else if (tor == 'chain') {
        s.chain = 'tor';
      } else if (psiphon == 'chain') {
        s.chain = 'psiphon';
      }
    }

    s.dns = str('dns', s.dns);
    s.exitLoc = str('exitLoc', s.exitLoc);
    s.peer = str('peer', s.peer);
    s.darkTheme = flag('darkTheme', s.darkTheme);
    s.vpnMode = flag('vpnMode', s.vpnMode);
    s.fakeDns = flag('fakeDns', s.fakeDns);
    s.vpnIpv6 = flag('vpnIpv6', s.vpnIpv6);
    s.systemProxy = flag('systemProxy', s.systemProxy);
    s.verbose = flag('verbose', s.verbose);
    s.extraArgs = str('extraArgs', s.extraArgs);
    return s;
  }

  CoreSettings copy() => fromJson(toJson());

  /// Every local port this configuration will bind, with what it is for.
  Map<String, int> portsInUse({required bool android}) {
    final ports = <String, int>{'SOCKS5': socksPort};
    if (httpProxy || (!android && systemProxy)) ports['HTTP'] = httpPort;
    if (!torOnly && chain == 'tor') ports['Tor'] = torPort;
    if (!torOnly && chain == 'psiphon' && !android) ports['Psiphon'] = psiphonPort;
    return ports;
  }

  /// A human-readable reason this configuration cannot start, or null when it can.
  String? problem({required bool android}) {
    final seen = <int, String>{};
    for (final e in portsInUse(android: android).entries) {
      final other = seen[e.value];
      if (other != null) {
        return 'The $other and ${e.key} proxies both want port ${e.value}. Give each its own port in Settings.';
      }
      seen[e.value] = e.key;
    }
    final p = peer.trim();
    if (p.isNotEmpty && !RegExp(r'^(\[[0-9a-fA-F:.]+\]|[0-9a-zA-Z.\-:]+):\d{1,5}$').hasMatch(p)) {
      return 'The forced peer must look like ip:port, for example 162.159.198.1:443.';
    }
    return null;
  }

  static Future<CoreSettings> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_key);
      if (raw == null) return CoreSettings();
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) return fromJson(decoded);
    } catch (_) {
      // A broken store must never keep the app from opening.
    }
    return CoreSettings();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_key, jsonEncode(toJson()));
    } catch (_) {}
  }
}

/// Labels for the choices, kept beside the values so the UI and the CLI never drift apart.
class Choices {
  Choices._();

  static const protocols = <String, String>{
    'auto': 'Auto',
    'wg': 'WireGuard',
    'masque': 'MASQUE',
    'mim': 'MASQUE²',
    'gool': 'Gool',
    'tor': 'Tor',
  };

  /// `auto`, `fastest` or a lowercase two-letter country code.
  static bool isTorExit(String v) => v == 'auto' || v == 'fastest' || RegExp(r'^[a-z]{2}$').hasMatch(v);

  /// The three ways to pick a Tor exit, for the segmented control.
  static const torExitModes = <String, String>{'auto': 'Auto', 'fastest': 'Fastest', 'country': 'Country'};

  static const torExitHints = <String, String>{
    'auto': 'Tor picks an exit itself, weighted by bandwidth, as Tor Browser does.',
    'fastest': 'Measures exits in the best-served countries on every connect and keeps the quickest.',
    'country': 'Leaves from the country you pick. Tor reads where each relay is from its own GeoIP table.',
  };

  /// Which segment [torExit] belongs to.
  static String torExitMode(String torExit) =>
      torExit == 'auto' || torExit == 'fastest' ? torExit : 'country';

  /// What Auto tries, in order. The first one that connects wins.
  static const autoOrder = <String>['wg', 'masque', 'mim', 'gool'];

  /// How long Auto gives [protocol] to come up before it moves on, in seconds. The deep scans
  /// sweep whole ranges, so they get twice as long.
  static int autoTimeout(String protocol, String scan) {
    final base = switch (protocol) {
      'wg' => 30,
      'masque' => 40,
      'mim' => 50,
      _ => 60,
    };
    final deep = scan == 'thorough' || scan == 'ironclad';
    return deep ? base * 2 : base;
  }

  static const protocolHints = <String, String>{
    'auto': 'Tries WireGuard, then MASQUE, then MASQUE², then Gool, and keeps the first that connects.',
    'masque': 'An HTTP/3 or HTTP/2 tunnel that looks like ordinary HTTPS.',
    'wg': 'Classic WireGuard. Fastest where UDP gets through.',
    'gool': 'WireGuard carried inside MASQUE, for a different exit address.',
    'mim': 'MASQUE carried inside MASQUE, for a different exit address.',
    'tor': 'No tunnel: straight into Tor, with bridges when Tor is blocked. Pick the exit below.',
  };

  static const transports = <String, String>{'h3': 'HTTP/3', 'h2': 'HTTP/2'};

  static const transportHints = <String, String>{
    'h3': 'QUIC over UDP. Fast, and the default.',
    'h2': 'Rides TCP. Try it where QUIC or UDP is blocked.',
  };

  static const scans = <String, String>{
    'turbo': 'Turbo',
    'balanced': 'Balanced',
    'thorough': 'Thorough',
    'verified': 'Verified',
    'ironclad': 'Ironclad',
  };

  static const scanHints = <String, String>{
    'turbo': 'Takes the first gateway that answers.',
    'balanced': 'Collects a few and keeps the fastest.',
    'thorough': 'Sweeps whole ranges, for when everything looks blocked.',
    'verified': 'Only dials gateways measured to work.',
    'ironclad': 'Proves each gateway with a real request before trusting it.',
  };

  static const noizes = <String, String>{
    'auto': 'Auto',
    'off': 'Off',
    'light': 'Light',
    'firewall': 'Firewall',
    'balanced': 'Balanced',
    'gfw': 'GFW',
    'aggressive': 'Aggressive',
  };

  static const ips = <String, String>{'v4': 'IPv4', 'v6': 'IPv6', 'both': 'Both'};

  static const chains = <String, String>{
    'off': 'Off',
    'tor': 'Tor via tunnel',
    'psiphon': 'Psiphon via tunnel',
  };

  static const chainHints = <String, String>{
    'off': 'Traffic leaves through the tunnel.',
    'tor': 'Adds a second proxy that exits through Tor, carried inside the tunnel.',
    'psiphon': 'Adds a second proxy that exits through Psiphon, carried inside the tunnel.',
  };

  static String protocolLong(String p) => switch (p) {
        'auto' => 'Auto',
        'tor' => 'Tor',
        'masque' => 'MASQUE',
        'wg' => 'WireGuard',
        'gool' => 'WireGuard in MASQUE',
        'mim' => 'MASQUE in MASQUE',
        _ => p,
      };
}
