import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:oryvex_shared/src/core/args.dart';
import 'package:oryvex_shared/src/core/log_line.dart';
import 'package:oryvex_shared/src/core/settings.dart';
import 'package:oryvex_shared/src/core/ip_info.dart';
import 'package:oryvex_shared/src/core/steps.dart';
import 'package:oryvex_shared/src/core/tor_exits.dart';
import 'package:oryvex_shared/src/core/win_startup.dart';
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

  test('SSTP is gone: old SSTP settings move to Auto', () {
    expect(Choices.protocols.containsKey('sstp'), isFalse);
    final s = CoreSettings.fromJson({'protocol': 'sstp', 'protocolVersion': 2, 'sstpServer': 'x.opengw.net'});
    expect(s.protocol, 'auto');
    expect(s.toJson().containsKey('sstpServer'), isFalse);
  });

  test('Tor is a route of its own, and the old "Tor only" exit becomes it', () {
    expect(Choices.protocols['tor'], 'Tor');
    expect((CoreSettings()..protocol = 'tor').torOnly, isTrue);
    final old = CoreSettings.fromJson({'protocol': 'wg', 'protocolVersion': 2, 'chain': 'tor-only'});
    expect(old.protocol, 'tor');
    expect(old.chain, 'off');
    expect(CoreSettings.fromJson({'tor': 'only'}).protocol, 'tor');
  });

  test('the Tor route asks for no tunnel and passes the exit choice', () {
    final auto = buildCoreArgs(CoreSettings()..protocol = 'tor', configPath: 'x', android: true);
    expect(auto, contains('--tor-only'));
    expect(auto, isNot(contains('--protocol')));
    expect(auto, isNot(contains('--tor-exit')));

    final fastest = buildCoreArgs(CoreSettings()
      ..protocol = 'tor'
      ..torExit = 'fastest', configPath: 'x', android: false);
    expect(fastest, containsAllInOrder(['--tor-exit', 'fastest']));

    final strict = buildCoreArgs(CoreSettings()
      ..protocol = 'wg'
      ..chain = 'tor'
      ..torExit = 'de'
      ..torExitStrict = true, configPath: 'x', android: false);
    expect(strict, containsAllInOrder(['--tor', '--tor-bind']));
    expect(strict, containsAllInOrder(['--tor-exit', 'de', '--tor-exit-strict']));

    // Without Tor in play the exit choice is not passed.
    final none = buildCoreArgs(CoreSettings()
      ..protocol = 'wg'
      ..torExit = 'de', configPath: 'x', android: false);
    expect(none, isNot(contains('--tor-exit')));
  });

  test('tor exit choices are validated on load', () {
    expect(CoreSettings.fromJson({'torExit': 'nl'}).torExit, 'nl');
    expect(CoreSettings.fromJson({'torExit': 'fastest'}).torExit, 'fastest');
    expect(CoreSettings.fromJson({'torExit': 'Germany'}).torExit, 'auto');
    expect(Choices.torExitMode('de'), 'country');
    expect(Choices.torExitMode('auto'), 'auto');
  });

  test('the core\'s exit directory line is read', () {
    const line = '[=] tor-exits {"updated":1793000000,"source":"onionoo","countries":['
        '{"cc":"de","name":"Germany","relays":412,"bandwidth":2300000000,"probability":0.31},'
        '{"cc":"nl","name":"Netherlands","relays":190,"bandwidth":900000000,"probability":0.12},'
        '{"cc":"XX1","name":"broken"}]}';
    final dir = TorExitDirectory.fromLogLine(line);
    expect(dir, isNotNull);
    expect(dir!.source, 'onionoo');
    expect(dir.countries.map((c) => c.code), ['de', 'nl']);
    expect(dir.totalRelays, 602);
    expect(dir.countries.first.detail, '412 exits · 18.4 Gbit/s');
    expect(TorExitDirectory.decode(dir.encode())!.countries.length, 2);
    expect(TorExitDirectory.fromLogLine('[+] tor is ready'), isNull);
  });

  test('the bundled exit list stands in before the first fetch', () {
    final dir = TorExitDirectory.bundled();
    expect(dir.isBundled, isTrue);
    expect(dir.countries.length, bundledTorExitCodes.length);
    expect(dir.countries.every((c) => isCountryCode(c.code)), isTrue);
    expect(dir.nameOf('de'), 'Germany');
  });

  test('the exit the core settled on is read', () {
    expect(TorExitDirectory.exitInUse('[+] tor exit: using de (Germany), the fastest at 842 ms'), ('de', 842));
    expect(TorExitDirectory.exitInUse('[+] tor exit: using auto (tor picks a fast exit, weighted by bandwidth)'),
        ('auto', null));
    expect(TorExitDirectory.exitInUse('[*] tor exit: trying DE (Germany)'), isNull);
  });

  test('the Tor route shows a Tor exit stage that the core closes', () {
    final s = CoreSettings()
      ..protocol = 'tor'
      ..torExit = 'fastest';
    final plan = ConnectionPlan.of(s, android: false)..begin();
    expect(plan.steps.map((x) => x.id), ['start', 'tor', 'exit', 'ready']);
    plan.ingest('[*] bootstrapping tor with no tunnel underneath it');
    plan.ingest('[+] tor is ready; 127.0.0.1:1819 leaves through tor');
    plan.ingest('[*] tor exit: trying NL (Netherlands)');
    expect(plan.steps[2].detail, 'Trying NL');
    plan.ingest('[+] tor exit: using nl (Netherlands), the fastest at 610 ms');
    expect(plan.steps[2].status, StepStatus.done);
    expect(plan.steps[2].detail, 'NL · 610 ms');
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
    expect(Ox.canvas, const Color(0xFF06080C));
    expect(Ox.text, const Color(0xFFF4F6FA));
  });

  test('IP lookup goes through the SOCKS route only while connected', () {
    expect(IpLookup.socksPortForRoute(tunnelConnected: false, configuredSocksPort: 1819), isNull);
    expect(IpLookup.socksPortForRoute(tunnelConnected: true, configuredSocksPort: 1819), 1819);
  });

  test('connection verification accepts valid HTTPS probe responses, not portal pages', () {
    expect(IpLookup.acceptsConnectivityResponse('www.cloudflare.com', 200, 'ip=203.0.113.8\nloc=JP\n'), isTrue);
    expect(IpLookup.acceptsConnectivityResponse('connectivitycheck.gstatic.com', 204, ''), isTrue);
    expect(IpLookup.acceptsConnectivityResponse('ipapi.co', 200, '{"ip":"203.0.113.8","country_code":"GB"}'), isTrue);
    expect(IpLookup.acceptsConnectivityResponse('www.cloudflare.com', 200, '<html>sign in</html>'), isFalse);
    expect(IpLookup.acceptsConnectivityResponse('connectivitycheck.gstatic.com', 200, ''), isFalse);
    expect(IpLookup.acceptsConnectivityResponse('unknown.example', 200, 'ok'), isFalse);
  });

  test('IP response parsing validates address and country code', () {
    expect(IpLookup.parseCloudflareTrace('ip=203.0.113.8\nloc=JP\n'), ('203.0.113.8', 'JP'));
    expect(IpLookup.parseCloudflareTrace('ip=not-an-ip\nloc=JP'), isNull);
    expect(IpLookup.parseIpApiJson('{"ip":"2001:db8::1","country_code":"gb"}'), ('2001:db8::1', 'GB'));
    expect(IpLookup.parseIpApiJson('{"ip":"bad","country_code":"GB"}'), isNull);
    expect(IpLookup.parseIpApiJson('{"ip":"203.0.113.8","country_code":"USA"}'), ('203.0.113.8', ''));
  });

  test('app behaviour options round-trip and validate', () {
    final d = CoreSettings();
    expect(d.autoConnect, isFalse);
    expect(d.autoReconnect, isTrue);
    expect(d.launchAtStartup, isFalse);
    expect(d.startInTray, isTrue);
    expect(d.closeAction, 'ask');
    final s = CoreSettings()
      ..autoConnect = true
      ..autoReconnect = false
      ..launchAtStartup = true
      ..startInTray = false
      ..closeAction = 'tray';
    final back = CoreSettings.fromJson(s.toJson());
    expect(back.autoConnect, isTrue);
    expect(back.autoReconnect, isFalse);
    expect(back.launchAtStartup, isTrue);
    expect(back.startInTray, isFalse);
    expect(back.closeAction, 'tray');
    expect(CoreSettings.fromJson({'closeAction': 'explode'}).closeAction, 'ask');
  });

  test('sign-in command quotes the exe and adds the tray flag', () {
    const exe = r'C:\Program Files\OryvexVPN\OryvexVPN.exe';
    expect(WinStartup.commandFor(exe, inTray: true), '"$exe" --background');
    expect(WinStartup.commandFor(exe, inTray: false), '"$exe"');
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

