import 'package:flutter_test/flutter_test.dart';
import 'package:oryvex_shared/src/core/args.dart';
import 'package:oryvex_shared/src/core/log_line.dart';
import 'package:oryvex_shared/src/core/settings.dart';

void main() {
  test('default settings build a prompt-free command line', () {
    final args = buildCoreArgs(CoreSettings(), configPath: '/tmp/o.toml', android: true);
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

  test('extra args honour quotes', () {
    expect(splitArgs('--a "b c" \'d\''), ['--a', 'b c', 'd']);
  });

  test('env_logger lines parse', () {
    final l = LogLine.parse('[2026-10-29T18:00:00.123Z INFO  oryvexcore::socks] [+] socks5 server listening on 127.0.0.1:1819');
    expect(l.level, LogLevel.info);
    expect(l.message, '[+] socks5 server listening on 127.0.0.1:1819');
  });
}

