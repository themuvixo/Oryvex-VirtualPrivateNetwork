import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oryvex_shared/src/core/args.dart';
import 'package:oryvex_shared/src/core/log_line.dart';
import 'package:oryvex_shared/src/core/settings.dart';
import 'package:oryvex_shared/src/core/ip_info.dart';
import 'package:oryvex_shared/src/core/sstp_servers.dart';
import 'package:oryvex_shared/src/core/vpngate.dart';
import 'package:oryvex_shared/src/ui/theme.dart';

void main() {
  test('default settings build a prompt-free command line', () {
    final args = buildCoreArgs(CoreSettings()..protocol = 'masque', configPath: '/tmp/o.toml', android: true);
    expect(args, containsAllInOrder(['--config', '/tmp/o.toml', '--bind', '127.0.0.1:1819']));
    expect(args, containsAll(['--protocol', 'masque', '--scan', 'balanced', '-4', '--h3']));
    expect(args, contains('--quick-reconnect'));
  });

  test('wireguard never gets a MASQUE carrier flag', () {
    final s = CoreSettings()..protocol = 'wg';
    final args = buildCoreArgs(s, configPath: 'x', android: false);
    expect(args, isNot(contains('--h3')));
    expect(args, isNot(contains('--h2')));
  });

  test('auto is the default and starts with WireGuard', () {
    expect(CoreSettings().protocol, 'auto');
    expect(Choices.autoOrder, ['wg', 'masque', 'mim', 'gool']);
    final args = buildCoreArgs(CoreSettings(), configPath: 'x', android: false);
    expect(args, containsAllInOrder(['--protocol', 'wg']));
  });

  test('settings saved with the old MASQUE default move to auto once', () {
    expect(CoreSettings.fromJson({'protocol': 'masque'}).protocol, 'auto');
    final kept = CoreSettings()..protocol = 'masque';
    expect(CoreSettings.fromJson(kept.toJson()).protocol, 'masque');
  });

  test('sstp is offered only where asked for', () {
    expect(Choices.protocolsFor(sstp: false).containsKey('sstp'), isFalse);
    expect(Choices.protocolsFor(sstp: true).containsKey('sstp'), isTrue);
  });

  test('dark mode is the default and old settings retain the default', () {
    expect(CoreSettings().darkTheme, isTrue);
    expect(CoreSettings.fromJson({'protocol': 'wg'}).darkTheme, isTrue);
    expect(CoreSettings.fromJson({'darkTheme': false}).darkTheme, isFalse);
    expect((CoreSettings()..darkTheme = false).toJson()['darkTheme'], isFalse);
  });

  test('theme choice survives a settings save/load round trip', () async {
    SharedPreferences.setMockInitialValues({});
    final settings = CoreSettings()..darkTheme = false;
    await settings.save();
    expect((await CoreSettings.load()).darkTheme, isFalse);
  });

  test('selected theme builds the matching full palette', () {
    final light = buildOxTheme(dark: false);
    expect(light.brightness, Brightness.light);
    expect(Ox.darkMode, isFalse);
    expect(Ox.canvas, const Color(0xFFF5F5F7));
    expect(Ox.text, const Color(0xFF1D1D1F));

    final dark = buildOxTheme(dark: true);
    expect(dark.brightness, Brightness.dark);
    expect(Ox.darkMode, isTrue);
    expect(Ox.canvas, const Color(0xFF0B0D12));
    expect(Ox.text, const Color(0xFFF4F6FA));
  });

  test('VPN Gate requires exact DNS hostname and preserves non-default port', () {
    expect(SstpServer.parseAddress('public-vpn-123.opengw.net')?.address, 'public-vpn-123.opengw.net');
    expect(SstpServer.parseAddress('vpn123.opengw.net:1443')?.address, 'vpn123.opengw.net:1443');
    expect(SstpServer.parseAddress('1.2.3.4'), isNull);
    expect(SstpServer.parseAddress('https://vpn123.opengw.net'), isNull);
    expect(SstpServer.parseAddress('vpn123.opengw.net:70000'), isNull);
  });

  test('VPN Gate table parsing keeps the DNS hostname and listed TCP port', () {
    const html = '<table><tr><td>Japan</td><td>219.100.37.1</td><td>metadata</td>'
        '<td>100 Mbps Ping: 20</td><td>1,234</td><td>SSTP Hostname : vpn123.opengw.net:1443</td>'
        '</tr></table>';
    final servers = VpnGateDirectory.parse(html);
    expect(servers, hasLength(1));
    expect(servers.single.address, 'vpn123.opengw.net:1443');
    expect(servers.single.ip, '219.100.37.1');
  });

  test('IP lookup uses the tunnel SOCKS route only for core tunnels', () {
    expect(IpLookup.socksPortForRoute(tunnelConnected: false, activeProtocol: null, configuredSocksPort: 1819), isNull);
    expect(IpLookup.socksPortForRoute(tunnelConnected: true, activeProtocol: 'wg', configuredSocksPort: 1819), 1819);
    expect(IpLookup.socksPortForRoute(tunnelConnected: true, activeProtocol: 'sstp', configuredSocksPort: 1819), isNull);
  });

  test('IP response parsing validates address and country code', () {
    expect(IpLookup.parseCloudflareTrace('ip=203.0.113.8\nloc=JP\n'), ('203.0.113.8', 'JP'));
    expect(IpLookup.parseCloudflareTrace('ip=not-an-ip\nloc=JP'), isNull);
    expect(IpLookup.parseIpApiJson('{"ip":"2001:db8::1","country_code":"gb"}'), ('2001:db8::1', 'GB'));
    expect(IpLookup.parseIpApiJson('{"ip":"bad","country_code":"GB"}'), isNull);
    expect(IpLookup.parseIpApiJson('{"ip":"203.0.113.8","country_code":"USA"}'), ('203.0.113.8', ''));
  });

  test('extra args honour quotes', () {
    expect(splitArgs('--a "b c" \'d\''), ['--a', 'b c', 'd']);
  });

  test('env_logger lines parse', () {
    final l = LogLine.parse('[2026-10-29T18:00:00.123Z INFO  oryvexcore::socks] [+] socks5 server listening on 127.0.0.1:1819');
    expect(l.level, LogLevel.info);
    expect(l.message, '[+] socks5 server listening on 127.0.0.1:1819');
  });
}

