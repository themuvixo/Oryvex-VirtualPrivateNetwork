import 'dart:convert';

/// One VPN Gate relay that speaks MS-SSTP. VPN Gate (vpngate.net, University of Tsukuba) lists
/// volunteer servers that all take the username "vpn" and the password "vpn".
class SstpServer {
  const SstpServer({
    required this.host,
    this.port = 443,
    this.ip = '',
    this.country = '',
    this.countryCode = '',
    this.mbps = 0,
    this.ping = 0,
    this.score = 0,
  });

  final String host;
  final int port;
  final String ip;
  final String country;
  final String countryCode;
  final double mbps;
  final int ping;
  final int score;

  /// What Windows dials: the DDNS name (its TLS certificate is issued for it), plus the port
  /// when it is not 443.
  String get address => port == 443 ? host : '$host:$port';

  static final _hostPattern = RegExp(
    r'^(?=.{1,253}$)(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+opengw\.net$',
    caseSensitive: false,
  );

  bool get isValid => _hostPattern.hasMatch(host) && port > 0 && port <= 65535;

  /// Parses VPN Gate's required DNS hostname and optional non-default port. Numeric IPs,
  /// schemes, credentials, and non-VPN-Gate hosts are intentionally rejected.
  static SstpServer? parseAddress(String address) {
    final match = RegExp(r'^([^:/?#@\s]+)(?::(\d{1,5}))?$').firstMatch(address.trim());
    if (match == null || !_hostPattern.hasMatch(match.group(1)!)) return null;
    final port = int.tryParse(match.group(2) ?? '') ?? 443;
    if (port < 1 || port > 65535) return null;
    return SstpServer(host: match.group(1)!.toLowerCase(), port: port);
  }

  /// "Japan · public-vpn-153.opengw.net"
  String get label => country.isEmpty ? host : '$country · $host';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'ip': ip,
        'country': country,
        'cc': countryCode,
        'mbps': mbps,
        'ping': ping,
        'score': score,
      };

  static SstpServer? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final host = raw['host'];
    if (host is! String || !_hostPattern.hasMatch(host)) return null;
    final port = raw['port'];
    final mbps = raw['mbps'];
    final ping = raw['ping'];
    final score = raw['score'];
    final server = SstpServer(
      host: host.toLowerCase(),
      port: port is int && port > 0 && port < 65536 ? port : 443,
      ip: raw['ip'] is String ? raw['ip'] as String : '',
      country: raw['country'] is String ? raw['country'] as String : '',
      countryCode: raw['cc'] is String ? raw['cc'] as String : '',
      mbps: mbps is num ? mbps.toDouble() : 0,
      ping: ping is int ? ping : 0,
      score: score is int ? score : 0,
    );
    return server.isValid ? server : null;
  }

  static String encodeList(List<SstpServer> servers) => jsonEncode([for (final s in servers) s.toJson()]);

  static List<SstpServer> decodeList(String raw) {
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      final out = <SstpServer>[];
      for (final e in list) {
        final server = SstpServer.fromJson(e);
        if (server != null) out.add(server);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }
}

/// Every MS-SSTP server VPN Gate listed when this build was made (vpngate.net/en/, 2026-10-30),
/// best VPN Gate score first. The app refreshes this list from the same page when it can
/// (see vpngate.dart); these are what it falls back on when the page is out of reach.
const bundledSstpServers = <SstpServer>[
  SstpServer(host: 'public-vpn-153.opengw.net', port: 443, ip: '219.100.37.109', country: 'Japan', countryCode: 'JP', mbps: 209.54, ping: 16, score: 1742546),
  SstpServer(host: 'public-vpn-114.opengw.net', port: 443, ip: '219.100.37.60', country: 'Japan', countryCode: 'JP', mbps: 147.71, ping: 8, score: 1626542),
  SstpServer(host: 'public-vpn-146.opengw.net', port: 443, ip: '219.100.37.94', country: 'Japan', countryCode: 'JP', mbps: 159.08, ping: 21, score: 1605006),
  SstpServer(host: 'public-vpn-165.opengw.net', port: 443, ip: '219.100.37.127', country: 'Japan', countryCode: 'JP', mbps: 160.89, ping: 22, score: 1569137),
  SstpServer(host: 'public-vpn-122.opengw.net', port: 443, ip: '219.100.37.62', country: 'Japan', countryCode: 'JP', mbps: 189.96, ping: 25, score: 1567988),
  SstpServer(host: 'public-vpn-148.opengw.net', port: 443, ip: '219.100.37.107', country: 'Japan', countryCode: 'JP', mbps: 145.68, ping: 26, score: 1551314),
  SstpServer(host: 'vpn250920860.opengw.net', port: 1895, ip: '210.198.250.157', country: 'Japan', countryCode: 'JP', mbps: 524.27, ping: 19, score: 1522522),
  SstpServer(host: 'public-vpn-151.opengw.net', port: 443, ip: '219.100.37.120', country: 'Japan', countryCode: 'JP', mbps: 124.42, ping: 24, score: 1401310),
  SstpServer(host: 'public-vpn-255.opengw.net', port: 443, ip: '219.100.37.224', country: 'Japan', countryCode: 'JP', mbps: 163.23, ping: 21, score: 1318159),
  SstpServer(host: 'vpn208466209.opengw.net', port: 1712, ip: '27.126.5.202', country: 'Korea Republic of', countryCode: 'KR', mbps: 23.02, ping: 39, score: 1300714),
  SstpServer(host: 'vpn991682963.opengw.net', port: 1556, ip: '118.130.207.150', country: 'Korea Republic of', countryCode: 'KR', mbps: 92.98, ping: 42, score: 1283120),
  SstpServer(host: 'public-vpn-118.opengw.net', port: 443, ip: '219.100.37.87', country: 'Japan', countryCode: 'JP', mbps: 140.07, ping: 22, score: 1230393),
  SstpServer(host: 'vpn179734162.opengw.net', port: 1441, ip: '124.18.175.178', country: 'Japan', countryCode: 'JP', mbps: 716.58, ping: 183, score: 1128220),
  SstpServer(host: 'vpn436828976.opengw.net', port: 995, ip: '121.137.117.124', country: 'Korea Republic of', countryCode: 'KR', mbps: 378.75, ping: 31, score: 1075634),
  SstpServer(host: 'public-vpn-37.opengw.net', port: 443, ip: '219.100.37.1', country: 'Japan', countryCode: 'JP', mbps: 523.70, ping: 9, score: 1056568),
  SstpServer(host: 'public-vpn-130.opengw.net', port: 443, ip: '219.100.37.90', country: 'Japan', countryCode: 'JP', mbps: 134.96, ping: 8, score: 1039224),
  SstpServer(host: 'vpn414350235.opengw.net', port: 1446, ip: '14.56.110.143', country: 'Korea Republic of', countryCode: 'KR', mbps: 80.15, ping: 35, score: 1022134),
  SstpServer(host: 'vpn507121601.opengw.net', port: 1616, ip: '14.33.15.202', country: 'Korea Republic of', countryCode: 'KR', mbps: 303.14, ping: 30, score: 950664),
  SstpServer(host: 'vpn745412775.opengw.net', port: 1955, ip: '47.141.165.251', country: 'United States', countryCode: 'US', mbps: 0.00, ping: 8, score: 942283),
  SstpServer(host: 'vpn785303392.opengw.net', port: 995, ip: '169.212.17.216', country: 'Korea Republic of', countryCode: 'KR', mbps: 7.36, ping: 28, score: 910773),
  SstpServer(host: 'vpn968701927.opengw.net', port: 1447, ip: '126.39.31.131', country: 'Japan', countryCode: 'JP', mbps: 589.93, ping: 10, score: 898668),
  SstpServer(host: 'vpn475174238.opengw.net', port: 1610, ip: '111.169.20.100', country: 'Japan', countryCode: 'JP', mbps: 127.77, ping: 7, score: 895554),
  SstpServer(host: 'vpn881746724.opengw.net', port: 995, ip: '36.65.57.228', country: 'Indonesia', countryCode: 'ID', mbps: 252.76, ping: 16, score: 890394),
  SstpServer(host: 'vpn980675302.opengw.net', port: 1765, ip: '106.173.177.181', country: 'Japan', countryCode: 'JP', mbps: 353.17, ping: 9, score: 886848),
  SstpServer(host: 'vpn421743167.opengw.net', port: 995, ip: '221.156.184.248', country: 'Korea Republic of', countryCode: 'KR', mbps: 404.45, ping: 29, score: 854300),
  SstpServer(host: 'laud.opengw.net', port: 443, ip: '115.179.206.241', country: 'Japan', countryCode: 'JP', mbps: 84.01, ping: 12, score: 788616),
  SstpServer(host: 'vpn899632141.opengw.net', port: 1803, ip: '118.106.240.20', country: 'Japan', countryCode: 'JP', mbps: 294.01, ping: 14, score: 780461),
  SstpServer(host: 'vpn303071146.opengw.net', port: 1684, ip: '116.121.173.112', country: 'Korea Republic of', countryCode: 'KR', mbps: 89.83, ping: 34, score: 778000),
  SstpServer(host: 'vpn451071809.opengw.net', port: 1940, ip: '180.196.98.244', country: 'Japan', countryCode: 'JP', mbps: 683.30, ping: 8, score: 761366),
  SstpServer(host: 'vpn570192271.opengw.net', port: 1745, ip: '218.159.1.213', country: 'Korea Republic of', countryCode: 'KR', mbps: 47.95, ping: 32, score: 732905),
  SstpServer(host: 'vpn840274812.opengw.net', port: 1272, ip: '126.65.246.148', country: 'Japan', countryCode: 'JP', mbps: 87.95, ping: 19, score: 718641),
  SstpServer(host: 'vpn137183472.opengw.net', port: 1730, ip: '121.130.89.23', country: 'Korea Republic of', countryCode: 'KR', mbps: 69.46, ping: 33, score: 711659),
  SstpServer(host: 'vpn743284148.opengw.net', port: 1201, ip: '124.211.146.144', country: 'Japan', countryCode: 'JP', mbps: 32.73, ping: 9, score: 702598),
];
