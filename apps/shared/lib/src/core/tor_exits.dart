import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'ip_info.dart';

/// One country Tor can leave from, as the core's exit directory lists it.
class TorExitCountry {
  const TorExitCountry({
    required this.code,
    required this.name,
    this.relays = 0,
    this.bandwidth = 0,
    this.probability = 0,
  });

  /// Lowercase ISO 3166-1 alpha-2.
  final String code;
  final String name;

  /// Running exit relays there (0 when unknown, for the bundled list).
  final int relays;

  /// Their advertised bandwidth together, in bytes per second.
  final int bandwidth;

  /// The share of exit traffic Tor would send there by itself, 0..1.
  final double probability;

  String get flag => flagOf(code);

  /// "412 exits · 18.4 Gbit/s", or "" when the bundled list has no numbers.
  String get detail {
    if (relays <= 0) return '';
    final rate = bandwidth > 0 ? ' · ${formatBandwidth(bandwidth)}' : '';
    return '$relays exit${relays == 1 ? '' : 's'}$rate';
  }

  static TorExitCountry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final cc = raw['cc'];
    if (cc is! String || !isCountryCode(cc.toLowerCase())) return null;
    final code = cc.toLowerCase();
    final name = raw['name'];
    int number(Object? v) => v is num ? v.toInt() : 0;
    final p = raw['probability'];
    return TorExitCountry(
      code: code,
      name: name is String && name.trim().isNotEmpty ? name.trim() : countryName(code),
      relays: number(raw['relays']),
      bandwidth: number(raw['bandwidth']),
      probability: p is num ? p.toDouble() : 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'cc': code,
        'name': name,
        'relays': relays,
        'bandwidth': bandwidth,
        'probability': probability,
      };
}

bool isCountryCode(String s) => RegExp(r'^[a-z]{2}$').hasMatch(s);

/// The regional-indicator flag for a two-letter code, or "" when it is not one.
String flagOf(String code) {
  final cc = code.toUpperCase();
  if (cc.length != 2) return '';
  final a = cc.codeUnitAt(0), b = cc.codeUnitAt(1);
  if (a < 65 || a > 90 || b < 65 || b > 90) return '';
  return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
}

/// Bytes per second, as people read link speeds: "940 Mbit/s", "18.4 Gbit/s".
String formatBandwidth(int bytesPerSecond) {
  final bits = bytesPerSecond * 8.0;
  if (bits >= 1e9) return '${(bits / 1e9).toStringAsFixed(1)} Gbit/s';
  if (bits >= 1e6) return '${(bits / 1e6).toStringAsFixed(0)} Mbit/s';
  return '${(bits / 1e3).toStringAsFixed(0)} kbit/s';
}

/// Every country Tor can leave from, best served first.
///
/// The core fetches it from Onionoo *through Tor* (torproject.org is filtered on many networks,
/// so it is never asked over the plain connection), prints it as one `[=] tor-exits {...}` line,
/// and the app keeps the last one it saw. Before that, a bundled list of long-standing exit
/// countries stands in.
class TorExitDirectory {
  const TorExitDirectory({required this.updated, required this.source, required this.countries});

  /// When the core fetched it; null for the bundled list.
  final DateTime? updated;

  /// `onionoo` or `bundled`.
  final String source;
  final List<TorExitCountry> countries;

  static const _cacheKey = 'oryvexcore.tor.exits.v1';
  static const _marker = '[=] tor-exits ';

  bool get isBundled => source == 'bundled';

  int get totalRelays => countries.fold(0, (sum, c) => sum + c.relays);

  TorExitCountry? find(String code) {
    for (final c in countries) {
      if (c.code == code) return c;
    }
    return null;
  }

  String nameOf(String code) => find(code)?.name ?? countryName(code);

  factory TorExitDirectory.bundled() => TorExitDirectory(
        updated: null,
        source: 'bundled',
        countries: [
          for (final cc in bundledTorExitCodes) TorExitCountry(code: cc, name: countryName(cc)),
        ],
      );

  static TorExitDirectory? decode(String raw) {
    try {
      final j = jsonDecode(raw);
      if (j is! Map) return null;
      final list = j['countries'];
      if (list is! List) return null;
      final countries = <TorExitCountry>[];
      final seen = <String>{};
      for (final e in list) {
        final c = TorExitCountry.fromJson(e);
        if (c != null && seen.add(c.code)) countries.add(c);
      }
      if (countries.isEmpty) return null;
      final at = j['updated'];
      final source = j['source'];
      return TorExitDirectory(
        updated: at is num && at > 0 ? DateTime.fromMillisecondsSinceEpoch(at.toInt() * 1000) : null,
        source: source is String && source.isNotEmpty ? source : 'onionoo',
        countries: countries,
      );
    } catch (_) {
      return null;
    }
  }

  String encode() => jsonEncode({
        'updated': updated == null ? 0 : updated!.millisecondsSinceEpoch ~/ 1000,
        'source': source,
        'countries': [for (final c in countries) c.toJson()],
      });

  /// The directory a core log message carries, or null when it carries none.
  static TorExitDirectory? fromLogLine(String message) {
    final at = message.indexOf(_marker);
    if (at < 0) return null;
    return decode(message.substring(at + _marker.length).trim());
  }

  static final _using = RegExp(r'tor exit: using (auto|[a-z]{2})\b(?:.*?(\d+) ms)?', caseSensitive: false);

  /// The exit the core settled on, from its "tor exit: using de (Germany), ... 842 ms" line:
  /// the code ('auto' or lowercase ISO) and the milliseconds it took, when measured.
  static (String, int?)? exitInUse(String message) {
    final m = _using.firstMatch(message);
    if (m == null) return null;
    return (m.group(1)!.toLowerCase(), int.tryParse(m.group(2) ?? ''));
  }

  static Future<TorExitDirectory> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      if (raw != null) {
        final d = decode(raw);
        if (d != null) return d;
      }
    } catch (_) {
      // A broken store falls back on the bundled list.
    }
    return TorExitDirectory.bundled();
  }

  Future<void> save() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, encode());
    } catch (_) {}
  }
}

/// Countries that have hosted many Tor exits for years, best served first. Same order as the
/// core's bundled list (oryvexcore/src/tor_exits.rs).
const bundledTorExitCodes = <String>[
  'de', 'nl', 'us', 'fr', 'se', 'ch', 'fi', 'ro', 'at', 'lu', 'no', 'gb', 'ca', 'pl', 'cz', 'is',
  'md', 'bg', 'dk', 'es', 'it', 'lt', 'lv', 'ee', 'ua', 'hu', 'sg', 'jp', 'hk', 'au', 'br', 'in',
];
