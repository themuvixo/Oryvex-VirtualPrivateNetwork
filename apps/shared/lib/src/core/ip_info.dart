import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The public address the internet sees, and the country it belongs to.
class IpInfo {
  const IpInfo({required this.ip, required this.countryCode, required this.viaTunnel, required this.at});

  final String ip;
  final String countryCode;
  final bool viaTunnel;
  final DateTime at;

  String get country => countryName(countryCode);

  String get flag {
    final cc = countryCode;
    if (cc.length != 2) return '';
    final a = cc.codeUnitAt(0), b = cc.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '';
    return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
  }
}

/// Resolves the public egress IP over verified HTTPS. When [socksPort] is supplied, every
/// request is tunneled through that proxy and never falls back to the device's direct route.
/// Without it, the OS routing table is used, which includes a connected Windows SSTP adapter.
class IpLookup {
  IpLookup._();

  static const endpoints = <(String, String)>[
    ('www.cloudflare.com', '/cdn-cgi/trace'),
    ('ipapi.co', '/json/'),
  ];
  static const _ipPattern = r'^(?:\d{1,3}\.){3}\d{1,3}$|^[0-9a-fA-F:]+$';

  /// The Android app process bypasses its own VpnService, so core tunnels must use SOCKS.
  /// Windows SSTP is a system route and intentionally uses the direct socket path.
  static int? socksPortForRoute({
    required bool tunnelConnected,
    required String? activeProtocol,
    required int configuredSocksPort,
  }) => tunnelConnected && activeProtocol != 'sstp' ? configuredSocksPort : null;

  static Future<IpInfo?> lookup({
    int? socksPort,
    bool throughTunnel = false,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    for (var i = 0; i < endpoints.length; i++) {
      final (host, path) = endpoints[i];
      try {
        final body = await _get(host, path, socksPort).timeout(timeout);
        final parsed = i == 0 ? parseCloudflareTrace(body) : parseIpApiJson(body);
        if (parsed != null) {
          return IpInfo(ip: parsed.$1, countryCode: parsed.$2, viaTunnel: throughTunnel, at: DateTime.now());
        }
      } catch (_) {
        // A failed endpoint is harmless; try the next verified HTTPS provider.
      }
    }
    return null;
  }

  /// Parses Cloudflare's `ip=...` / `loc=XX` trace format.
  static (String, String)? parseCloudflareTrace(String body) {
    final ip = RegExp(r'^ip=(\S+)\s*$', multiLine: true).firstMatch(body)?.group(1);
    final loc = RegExp(r'^loc=([A-Za-z]{2})\s*$', multiLine: true).firstMatch(body)?.group(1);
    if (ip == null || !RegExp(_ipPattern).hasMatch(ip) || !_validIp(ip)) return null;
    return (ip, (loc ?? '').toUpperCase());
  }

  /// Parses the public JSON response from ipapi.co.
  static (String, String)? parseIpApiJson(String body) {
    try {
      final json = jsonDecode(body);
      if (json is! Map) return null;
      final ip = json['ip'];
      final code = json['country_code'];
      if (ip is! String || !RegExp(_ipPattern).hasMatch(ip) || !_validIp(ip)) return null;
      return (ip, code is String && RegExp(r'^[A-Za-z]{2}$').hasMatch(code) ? code.toUpperCase() : '');
    } on FormatException {
      return null;
    }
  }

  static bool _validIp(String value) {
    final parsed = InternetAddress.tryParse(value);
    return parsed != null && (parsed.type == InternetAddressType.IPv4 || parsed.type == InternetAddressType.IPv6);
  }

  static Future<String> _get(String host, String path, int? socksPort) async {
    Socket? raw;
    SecureSocket? tls;
    _Reader? proxyReader;
    try {
      if (socksPort == null) {
        tls = await SecureSocket.connect(host, 443, timeout: const Duration(seconds: 6), supportedProtocols: const ['http/1.1']);
      } else {
        raw = await Socket.connect(InternetAddress.loopbackIPv4, socksPort, timeout: const Duration(seconds: 4));
        proxyReader = _Reader(raw);
        await _socksConnect(raw, proxyReader, host, 443).timeout(const Duration(seconds: 5));
        await proxyReader.cancel();
        proxyReader = null;
        // host is deliberately the DNS name: TLS chain and hostname validation remain enabled.
        tls = await SecureSocket.secure(raw, host: host, supportedProtocols: const ['http/1.1']).timeout(const Duration(seconds: 6));
      }
      tls.write('GET $path HTTP/1.1\r\n'
          'Host: $host\r\n'
          'User-Agent: OryvexVPN/1.0\r\n'
          'Accept: application/json, text/plain\r\n'
          'Accept-Encoding: identity\r\n'
          'Connection: close\r\n\r\n');
      await tls.flush();
      final responseReader = _Reader(tls);
      late final List<int> responseBytes;
      try {
        responseBytes = await responseReader.rest().timeout(const Duration(seconds: 6));
      } finally {
        await responseReader.cancel();
      }
      final response = utf8.decode(responseBytes, allowMalformed: true);
      final split = response.indexOf('\r\n\r\n');
      if (split < 0) throw const FormatException('HTTPS response has no header boundary');
      final status = response.substring(0, response.indexOf('\r\n'));
      if (!RegExp(r'^HTTP/1\.[01] 200(?:\s|$)').hasMatch(status)) throw HttpException(status);
      final headers = response.substring(response.indexOf('\r\n') + 2, split).toLowerCase();
      var body = response.substring(split + 4);
      if (headers.contains('transfer-encoding: chunked')) body = _unchunk(body);
      return body;
    } finally {
      await proxyReader?.cancel();
      tls?.destroy();
      raw?.destroy();
    }
  }

  static String _unchunk(String body) {
    final out = StringBuffer();
    var offset = 0;
    while (offset < body.length) {
      final end = body.indexOf('\r\n', offset);
      if (end < 0) throw const FormatException('malformed chunk header');
      final size = int.tryParse(body.substring(offset, end).split(';').first.trim(), radix: 16);
      if (size == null || size < 0) throw const FormatException('malformed chunk size');
      if (size == 0) return out.toString();
      final from = end + 2;
      final to = from + size;
      if (to + 2 > body.length || body.substring(to, to + 2) != '\r\n') {
        throw const FormatException('truncated chunk');
      }
      out.write(body.substring(from, to));
      offset = to + 2;
    }
    throw const FormatException('chunk terminator is missing');
  }

  static Future<void> _socksConnect(Socket socket, _Reader reader, String host, int port) async {
    socket.add(const [5, 1, 0]);
    await socket.flush();
    final hello = await reader.take(2);
    if (hello[0] != 5 || hello[1] != 0) throw const SocketException('SOCKS5 refused the greeting');

    final ip = InternetAddress.tryParse(host);
    final request = <int>[5, 1, 0];
    if (ip != null && ip.type == InternetAddressType.IPv4) {
      request..add(1)..addAll(ip.rawAddress);
    } else {
      final name = ascii.encode(host);
      request..add(3)..add(name.length)..addAll(name);
    }
    request..add((port >> 8) & 0xff)..add(port & 0xff);
    socket.add(request);
    await socket.flush();

    final head = await reader.take(4);
    if (head[0] != 5 || head[1] != 0) throw SocketException('SOCKS5 CONNECT failed (${head[1]})');
    switch (head[3]) {
      case 1:
        await reader.take(6);
      case 4:
        await reader.take(18);
      case 3:
        await reader.take((await reader.take(1))[0] + 2);
      default:
        throw const SocketException('SOCKS5 sent an unknown address type');
    }
  }
}

class _Reader {
  _Reader(Socket socket) {
    _sub = socket.listen(
      (data) { _buf.addAll(data); _wake(); },
      onError: (Object _) { _done = true; _wake(); },
      onDone: () { _done = true; _wake(); },
      cancelOnError: true,
    );
  }

  late final StreamSubscription<List<int>> _sub;
  final List<int> _buf = <int>[];
  bool _done = false;
  int _want = 0;
  Completer<void>? _waiter;

  void _wake() {
    final w = _waiter;
    if (w != null && (_done || _buf.length >= _want)) {
      _waiter = null;
      w.complete();
    }
  }

  Future<List<int>> take(int n) async {
    while (_buf.length < n && !_done) {
      _want = n;
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
    if (_buf.length < n) throw const SocketException('the connection closed early');
    final out = _buf.sublist(0, n);
    _buf.removeRange(0, n);
    return out;
  }

  Future<List<int>> rest() async {
    while (!_done) {
      _want = 1 << 30;
      final w = Completer<void>();
      _waiter = w;
      await w.future;
    }
    final out = List<int>.of(_buf);
    _buf.clear();
    return out;
  }

  Future<void> cancel() => _sub.cancel();
}

/// The English name of an ISO 3166-1 alpha-2 code, or the code itself when it is not listed.
String countryName(String code) => _countries[code.toUpperCase()] ?? code.toUpperCase();

const _countries = <String, String>{
  'AD': 'Andorra',
  'AE': 'United Arab Emirates',
  'AF': 'Afghanistan',
  'AG': 'Antigua and Barbuda',
  'AL': 'Albania',
  'AM': 'Armenia',
  'AO': 'Angola',
  'AR': 'Argentina',
  'AT': 'Austria',
  'AU': 'Australia',
  'AZ': 'Azerbaijan',
  'BA': 'Bosnia and Herzegovina',
  'BB': 'Barbados',
  'BD': 'Bangladesh',
  'BE': 'Belgium',
  'BF': 'Burkina Faso',
  'BG': 'Bulgaria',
  'BH': 'Bahrain',
  'BI': 'Burundi',
  'BJ': 'Benin',
  'BN': 'Brunei',
  'BO': 'Bolivia',
  'BR': 'Brazil',
  'BS': 'Bahamas',
  'BT': 'Bhutan',
  'BW': 'Botswana',
  'BY': 'Belarus',
  'BZ': 'Belize',
  'CA': 'Canada',
  'CD': 'DR Congo',
  'CF': 'Central African Republic',
  'CG': 'Congo',
  'CH': 'Switzerland',
  'CI': 'Côte d\'Ivoire',
  'CL': 'Chile',
  'CM': 'Cameroon',
  'CN': 'China',
  'CO': 'Colombia',
  'CR': 'Costa Rica',
  'CU': 'Cuba',
  'CV': 'Cape Verde',
  'CY': 'Cyprus',
  'CZ': 'Czechia',
  'DE': 'Germany',
  'DJ': 'Djibouti',
  'DK': 'Denmark',
  'DM': 'Dominica',
  'DO': 'Dominican Republic',
  'DZ': 'Algeria',
  'EC': 'Ecuador',
  'EE': 'Estonia',
  'EG': 'Egypt',
  'ER': 'Eritrea',
  'ES': 'Spain',
  'ET': 'Ethiopia',
  'FI': 'Finland',
  'FJ': 'Fiji',
  'FR': 'France',
  'GA': 'Gabon',
  'GB': 'United Kingdom',
  'GD': 'Grenada',
  'GE': 'Georgia',
  'GH': 'Ghana',
  'GM': 'Gambia',
  'GN': 'Guinea',
  'GQ': 'Equatorial Guinea',
  'GR': 'Greece',
  'GT': 'Guatemala',
  'GW': 'Guinea-Bissau',
  'GY': 'Guyana',
  'HK': 'Hong Kong',
  'HN': 'Honduras',
  'HR': 'Croatia',
  'HT': 'Haiti',
  'HU': 'Hungary',
  'ID': 'Indonesia',
  'IE': 'Ireland',
  'IL': 'Israel',
  'IN': 'India',
  'IQ': 'Iraq',
  'IR': 'Iran',
  'IS': 'Iceland',
  'IT': 'Italy',
  'JM': 'Jamaica',
  'JO': 'Jordan',
  'JP': 'Japan',
  'KE': 'Kenya',
  'KG': 'Kyrgyzstan',
  'KH': 'Cambodia',
  'KM': 'Comoros',
  'KN': 'Saint Kitts and Nevis',
  'KP': 'North Korea',
  'KR': 'South Korea',
  'KW': 'Kuwait',
  'KZ': 'Kazakhstan',
  'LA': 'Laos',
  'LB': 'Lebanon',
  'LC': 'Saint Lucia',
  'LI': 'Liechtenstein',
  'LK': 'Sri Lanka',
  'LR': 'Liberia',
  'LS': 'Lesotho',
  'LT': 'Lithuania',
  'LU': 'Luxembourg',
  'LV': 'Latvia',
  'LY': 'Libya',
  'MA': 'Morocco',
  'MC': 'Monaco',
  'MD': 'Moldova',
  'ME': 'Montenegro',
  'MG': 'Madagascar',
  'MK': 'North Macedonia',
  'ML': 'Mali',
  'MM': 'Myanmar',
  'MN': 'Mongolia',
  'MO': 'Macao',
  'MR': 'Mauritania',
  'MT': 'Malta',
  'MU': 'Mauritius',
  'MV': 'Maldives',
  'MW': 'Malawi',
  'MX': 'Mexico',
  'MY': 'Malaysia',
  'MZ': 'Mozambique',
  'NA': 'Namibia',
  'NE': 'Niger',
  'NG': 'Nigeria',
  'NI': 'Nicaragua',
  'NL': 'Netherlands',
  'NO': 'Norway',
  'NP': 'Nepal',
  'NZ': 'New Zealand',
  'OM': 'Oman',
  'PA': 'Panama',
  'PE': 'Peru',
  'PG': 'Papua New Guinea',
  'PH': 'Philippines',
  'PK': 'Pakistan',
  'PL': 'Poland',
  'PR': 'Puerto Rico',
  'PS': 'Palestine',
  'PT': 'Portugal',
  'PY': 'Paraguay',
  'QA': 'Qatar',
  'RO': 'Romania',
  'RS': 'Serbia',
  'RU': 'Russia',
  'RW': 'Rwanda',
  'SA': 'Saudi Arabia',
  'SB': 'Solomon Islands',
  'SC': 'Seychelles',
  'SD': 'Sudan',
  'SE': 'Sweden',
  'SG': 'Singapore',
  'SI': 'Slovenia',
  'SK': 'Slovakia',
  'SL': 'Sierra Leone',
  'SM': 'San Marino',
  'SN': 'Senegal',
  'SO': 'Somalia',
  'SR': 'Suriname',
  'SS': 'South Sudan',
  'SV': 'El Salvador',
  'SY': 'Syria',
  'SZ': 'Eswatini',
  'TD': 'Chad',
  'TG': 'Togo',
  'TH': 'Thailand',
  'TJ': 'Tajikistan',
  'TL': 'Timor-Leste',
  'TM': 'Turkmenistan',
  'TN': 'Tunisia',
  'TR': 'Türkiye',
  'TT': 'Trinidad and Tobago',
  'TW': 'Taiwan',
  'TZ': 'Tanzania',
  'UA': 'Ukraine',
  'UG': 'Uganda',
  'US': 'United States',
  'UY': 'Uruguay',
  'UZ': 'Uzbekistan',
  'VE': 'Venezuela',
  'VN': 'Vietnam',
  'YE': 'Yemen',
  'ZA': 'South Africa',
  'ZM': 'Zambia',
  'ZW': 'Zimbabwe',
};
