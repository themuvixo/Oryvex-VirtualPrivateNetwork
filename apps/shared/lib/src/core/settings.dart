import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Every choice the GUI makes for the core. Each field maps onto CLI flags in `args.dart`.
class CoreSettings {
  CoreSettings();

  /// auto | wg | masque | mim | gool | sstp.
  ///
  /// auto tries WireGuard, then MASQUE, then MASQUE², then Gool, and keeps the first one that
  /// connects. sstp (Windows) dials a VPN Gate server with Windows' own SSTP client.
  String protocol = 'auto';

  /// The VPN Gate server SSTP dials (its address, host or host:port). Empty: the best one.
  String sstpServer = '';

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

  /// off | tor (Tor through the tunnel) | tor-only (no tunnel, plain Tor) | psiphon (desktop)
  String chain = 'off';

  /// Where the extra Tor proxy listens with chain == tor. Kept clear of the HTTP port.
  int torPort = 1822;

  /// Where the extra Psiphon proxy listens with chain == psiphon.
  int psiphonPort = 1821;

  String dns = '';
  String exitLoc = '';
  String peer = '';

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
  /// it used to be the default, so they move to Auto once.
  static const _protocolVersion = 2;

  bool get torOnly => chain == 'tor-only';

  Map<String, dynamic> toJson() => {
        'protocol': protocol,
        'protocolVersion': _protocolVersion,
        'sstpServer': sstpServer,
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

    s.protocol = str('protocol', s.protocol, Choices.protocols);
    if (j['protocolVersion'] != _protocolVersion && s.protocol == 'masque') s.protocol = 'auto';
    s.sstpServer = str('sstpServer', s.sstpServer);
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

    if (j['chain'] is String && Choices.chains.containsKey(j['chain'])) {
      s.chain = j['chain'] as String;
    } else {
      // Settings saved by 2.4.0 kept Tor and Psiphon apart; fold them into one choice.
      final tor = j['tor'];
      final psiphon = j['psiphon'];
      if (tor == 'only') {
        s.chain = 'tor-only';
      } else if (tor == 'chain') {
        s.chain = 'tor';
      } else if (psiphon == 'chain') {
        s.chain = 'psiphon';
      }
    }

    s.dns = str('dns', s.dns);
    s.exitLoc = str('exitLoc', s.exitLoc);
    s.peer = str('peer', s.peer);
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
    if (chain == 'tor') ports['Tor'] = torPort;
    if (chain == 'psiphon' && !android) ports['Psiphon'] = psiphonPort;
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
    'sstp': 'SSTP',
  };

  /// The protocols this platform offers: SSTP needs Windows' built-in SSTP client.
  static Map<String, String> protocolsFor({required bool sstp}) =>
      sstp ? protocols : {for (final e in protocols.entries) if (e.key != 'sstp') e.key: e.value};

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
    'sstp': 'A free VPN Gate server over Windows\' built-in SSTP. Changes your country, covers every app.',
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
    'tor-only': 'Tor only',
    'psiphon': 'Psiphon via tunnel',
  };

  static const chainHints = <String, String>{
    'off': 'Traffic leaves through the tunnel.',
    'tor': 'Adds a second proxy that exits through Tor, carried inside the tunnel.',
    'tor-only': 'No tunnel at all: the main proxy is plain Tor (TCP only).',
    'psiphon': 'Adds a second proxy that exits through Psiphon, carried inside the tunnel.',
  };

  static String protocolLong(String p) => switch (p) {
        'auto' => 'Auto',
        'sstp' => 'SSTP · VPN Gate',
        'masque' => 'MASQUE',
        'wg' => 'WireGuard',
        'gool' => 'WireGuard in MASQUE',
        'mim' => 'MASQUE in MASQUE',
        _ => p,
      };
}
