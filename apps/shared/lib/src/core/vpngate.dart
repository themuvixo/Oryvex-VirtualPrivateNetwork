import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'sstp_servers.dart';

/// The SSTP server list: the one bundled with the app, replaced by a fresh copy of
/// vpngate.net's own table whenever the page can be reached.
class VpnGateDirectory {
  VpnGateDirectory._();

  static const pageUrl = 'https://www.vpngate.net/en/';
  static const _cacheKey = 'oryvexcore.sstp.servers.v1';
  static const _cacheAtKey = 'oryvexcore.sstp.servers.at.v1';

  /// A refreshed list older than this is fetched again before SSTP dials.
  static const maxAge = Duration(hours: 6);

  /// The last saved list and when it was fetched, or the bundled list with no date.
  static Future<(List<SstpServer>, DateTime?)> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_cacheKey);
      final at = prefs.getInt(_cacheAtKey);
      if (raw != null) {
        final list = SstpServer.decodeList(raw);
        if (list.isNotEmpty) {
          return (list, at == null ? null : DateTime.fromMillisecondsSinceEpoch(at));
        }
      }
    } catch (_) {
      // A broken store falls back on the bundled list.
    }
    return (bundledSstpServers, null);
  }

  /// Fetches vpngate.net, keeps every server that offers MS-SSTP and saves the list.
  /// Throws when the page cannot be reached or lists none.
  static Future<List<SstpServer>> refresh({Duration timeout = const Duration(seconds: 15)}) async {
    final html = await _fetch(timeout);
    final servers = parse(html);
    if (servers.isEmpty) {
      throw const FormatException('vpngate.net listed no SSTP servers');
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_cacheKey, SstpServer.encodeList(servers));
      await prefs.setInt(_cacheAtKey, DateTime.now().millisecondsSinceEpoch);
    } catch (_) {}
    return servers;
  }

  static Future<String> _fetch(Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8)
      ..userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) OryvexVPN';
    try {
      final request = await client.getUrl(Uri.parse(pageUrl)).timeout(timeout);
      final response = await request.close().timeout(timeout);
      if (response.statusCode != 200) {
        throw HttpException('vpngate.net answered ${response.statusCode}');
      }
      return await response.transform(const Utf8Decoder(allowMalformed: true)).join().timeout(timeout * 2);
    } finally {
      client.close(force: true);
    }
  }

  static final _rowSplit = RegExp(r'<tr\b', caseSensitive: false);
  static final _cellSplit = RegExp(r'<td\b[^>]*>', caseSensitive: false);
  static final _sstp = RegExp(
    r'SSTP Hostname\s*:(?:\s|&nbsp;|<[^>]*>)*([A-Za-z0-9][A-Za-z0-9.\-]*\.[A-Za-z]{2,})(?::(\d{1,5}))?',
    caseSensitive: false,
  );
  static final _tag = RegExp(r'<[^>]*>');
  static final _space = RegExp(r'\s+');
  static final _ipv4 = RegExp(r'\b(\d{1,3}(?:\.\d{1,3}){3})\b');
  static final _mbps = RegExp(r'([\d.,]+)\s*Mbps', caseSensitive: false);
  static final _ping = RegExp(r'Ping:\s*(\d+)', caseSensitive: false);
  static final _number = RegExp(r'^[\d,]+$');
  static final _flag = RegExp(r'flags/([A-Za-z]{2})\.png', caseSensitive: false);

  static String _text(String html) =>
      html.replaceAll(_tag, ' ').replaceAll('&nbsp;', ' ').replaceAll('&amp;', '&').replaceAll(_space, ' ').trim();

  /// Reads the server table of vpngate.net/en/: one row per server, the MS-SSTP column naming
  /// the host to dial ("SSTP Hostname : vpn123.opengw.net:1443").
  static List<SstpServer> parse(String html) {
    final servers = <SstpServer>[];
    final seen = <String>{};
    for (final row in html.split(_rowSplit)) {
      final m = _sstp.firstMatch(row);
      if (m == null) continue;
      final host = m.group(1)!.toLowerCase();
      final port = int.tryParse(m.group(2) ?? '') ?? 443;
      if (port <= 0 || port > 65535) continue;
      final key = '$host:$port';
      if (!seen.add(key)) continue;

      final cells = row.split(_cellSplit).skip(1).map(_text).toList();
      final country = cells.isNotEmpty ? cells[0] : '';
      final ip = cells.length > 1 ? (_ipv4.firstMatch(cells[1])?.group(1) ?? '') : '';
      final quality = cells.length > 3 ? cells[3] : '';
      final mbps = double.tryParse((_mbps.firstMatch(quality)?.group(1) ?? '').replaceAll(',', '')) ?? 0;
      final ping = int.tryParse(_ping.firstMatch(quality)?.group(1) ?? '') ?? 0;
      var score = 0;
      if (cells.isNotEmpty) {
        final last = cells.last.trim();
        if (_number.hasMatch(last)) score = int.tryParse(last.replaceAll(',', '')) ?? 0;
      }
      servers.add(SstpServer(
        host: host,
        port: port,
        ip: ip,
        country: country.length > 40 ? country.substring(0, 40) : country,
        countryCode: (_flag.firstMatch(row)?.group(1)?.toUpperCase()) ?? countryCodeFor(country),
        mbps: mbps,
        ping: ping,
        score: score,
      ));
    }
    servers.sort((a, b) => b.score.compareTo(a.score));
    return servers;
  }

  /// The ISO code for the country names VPN Gate prints, for the ones it lists most.
  static String countryCodeFor(String name) {
    final n = name.toLowerCase();
    const known = <String, String>{
      'japan': 'JP',
      'korea republic of': 'KR',
      'korea': 'KR',
      'united states': 'US',
      'indonesia': 'ID',
      'thailand': 'TH',
      'viet nam': 'VN',
      'vietnam': 'VN',
      'russian federation': 'RU',
      'china': 'CN',
      'taiwan': 'TW',
      'hong kong': 'HK',
      'united kingdom': 'GB',
      'germany': 'DE',
      'france': 'FR',
      'netherlands': 'NL',
      'canada': 'CA',
      'australia': 'AU',
      'india': 'IN',
      'brazil': 'BR',
      'paraguay': 'PY',
      'philippines': 'PH',
      'singapore': 'SG',
      'malaysia': 'MY',
      'turkey': 'TR',
      'ukraine': 'UA',
      'poland': 'PL',
      'spain': 'ES',
      'italy': 'IT',
      'romania': 'RO',
      'iran (islamic republic of)': 'IR',
    };
    return known[n] ?? '';
  }
}
