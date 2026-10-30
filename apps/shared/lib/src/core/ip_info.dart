import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The public address the internet sees, and the country it belongs to.
class IpInfo {
  const IpInfo({required this.ip, required this.countryCode, required this.viaTunnel, required this.at});

  final String ip;

  /// ISO 3166-1 alpha-2, upper case. Empty when the lookup could not tell.
  final String countryCode;

  /// True when the lookup went out through the tunnel (so this is the VPN's exit).
  final bool viaTunnel;
  final DateTime at;

  String get country => countryName(countryCode);

  /// The flag emoji for [countryCode] ("🇯🇵"), or an empty string.
  String get flag {
    final cc = countryCode;
    if (cc.length != 2) return '';
    final a = cc.codeUnitAt(0), b = cc.codeUnitAt(1);
    if (a < 65 || a > 90 || b < 65 || b > 90) return '';
    return String.fromCharCodes([0x1F1E6 + a - 65, 0x1F1E6 + b - 65]);
  }
}

/// Asks who we look like to the outside: Cloudflare's trace page first ("ip=…", "loc=JP"), and
/// ip-api.com if Cloudflare does not answer. Plain HTTP over a raw socket, so it can go out
/// through the core's own SOCKS5 port: the app itself is left out of its Android VPN, and on
/// desktop the core is a proxy, so a direct request would show the real address.
class IpLookup {
  IpLookup._();

  static const _cloudflare = <String>['1.1.1.1', '1.0.0.1'];

  static Future<IpInfo?> lookup({int? socksPort, Duration timeout = const Duration(seconds: 10)}) async {
    for (final host in _cloudflare) {
      try {
        final body = await _get(host, '/cdn-cgi/trace', socksPort).timeout(timeout);
        final ip = RegExp(r'^ip=(\S+)\s*$', multiLine: true).firstMatch(body)?.group(1);
        final loc = RegExp(r'^loc=([A-Za-z]{2})\s*$', multiLine: true).firstMatch(body)?.group(1);
        if (ip != null && ip.isNotEmpty) {
          return IpInfo(ip: ip, countryCode: (loc ?? '').toUpperCase(), viaTunnel: socksPort != null, at: DateTime.now());
        }
      } catch (_) {}
    }
    try {
      final body = await _get('ip-api.com', '/line/?fields=query,countryCode', socksPort).timeout(timeout);
      final lines = body.split(RegExp(r'\r?\n')).map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
      if (lines.isNotEmpty && RegExp(r'^[0-9a-fA-F:.]+$').hasMatch(lines.first)) {
        final cc = lines.length > 1 && lines[1].length == 2 ? lines[1].toUpperCase() : '';
        return IpInfo(ip: lines.first, countryCode: cc, viaTunnel: socksPort != null, at: DateTime.now());
      }
    } catch (_) {}
    return null;
  }

  /// GET http://[host][path] and return the body. HTTP/1.0, so the answer is never chunked.
  static Future<String> _get(String host, String path, int? socksPort) async {
    final Socket socket;
    if (socksPort == null) {
      socket = await Socket.connect(host, 80, timeout: const Duration(seconds: 6));
    } else {
      socket = await Socket.connect(InternetAddress.loopbackIPv4, socksPort, timeout: const Duration(seconds: 4));
    }
    final reader = _Reader(socket);
    try {
      if (socksPort != null) await _socksConnect(socket, reader, host, 80);
      socket.add(ascii.encode('GET $path HTTP/1.0\r\n'
          'Host: $host\r\n'
          'User-Agent: OryvexVPN\r\n'
          'Accept: */*\r\n'
          'Connection: close\r\n\r\n'));
      await socket.flush();
      final raw = utf8.decode(await reader.rest(), allowMalformed: true);
      final split = raw.indexOf('\r\n\r\n');
      if (!raw.startsWith('HTTP/') || split < 0) throw const FormatException('not an HTTP answer');
      final status = raw.substring(0, raw.indexOf('\r\n'));
      if (!status.contains(' 200')) throw FormatException(status);
      return raw.substring(split + 4);
    } finally {
      await reader.cancel();
      socket.destroy();
    }
  }

  /// SOCKS5, no authentication, CONNECT [host]:[port] by name or address.
  static Future<void> _socksConnect(Socket socket, _Reader reader, String host, int port) async {
    socket.add(const [5, 1, 0]);
    await socket.flush();
    final hello = await reader.take(2);
    if (hello[0] != 5 || hello[1] != 0) throw const SocketException('SOCKS5 refused the greeting');

    final ip = InternetAddress.tryParse(host);
    final request = <int>[5, 1, 0];
    if (ip != null && ip.type == InternetAddressType.IPv4) {
      request
        ..add(1)
        ..addAll(ip.rawAddress);
    } else {
      final name = ascii.encode(host);
      request
        ..add(3)
        ..add(name.length)
        ..addAll(name);
    }
    request
      ..add((port >> 8) & 0xff)
      ..add(port & 0xff);
    socket.add(request);
    await socket.flush();

    final head = await reader.take(4);
    if (head[0] != 5 || head[1] != 0) throw SocketException('SOCKS5 CONNECT failed (${head[1]})');
    switch (head[3]) {
      case 1:
        await reader.take(4 + 2);
      case 4:
        await reader.take(16 + 2);
      case 3:
        await reader.take((await reader.take(1))[0] + 2);
      default:
        throw const SocketException('SOCKS5 sent an unknown address type');
    }
  }
}

/// Reads a socket in pieces: the SOCKS5 handshake a few bytes at a time, then the rest.
class _Reader {
  _Reader(Socket socket) {
    _sub = socket.listen(
      (data) {
        _buf.addAll(data);
        _wake();
      },
      onError: (Object _) {
        _done = true;
        _wake();
      },
      onDone: () {
        _done = true;
        _wake();
      },
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
    if (w == null) return;
    if (_done || _buf.length >= _want) {
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
