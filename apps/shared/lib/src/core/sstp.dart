import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'sstp_servers.dart';

/// Byte counters of the SSTP adapter: what came in (download) and went out (upload).
class SstpCounters {
  const SstpCounters(this.down, this.up);
  final int down;
  final int up;
}

/// Dials VPN Gate's SSTP servers with Windows' own client: a per-user VPN entry made with
/// Add-VpnConnection (no admin rights needed), then `rasdial` to connect and hang up. Windows
/// routes every app through it while it is up.
class SstpClient {
  SstpClient._();

  /// The VPN entry the app owns. It shows up under Windows Settings › VPN as well.
  static const entryName = 'OryvexVPN SSTP';

  /// The VPN Gate account every server takes.
  static const user = 'vpn';
  static const password = 'vpn';

  static bool get supported => Platform.isWindows;

  /// Connects to [server]. Returns null once Windows reports the entry connected, or the reason
  /// it did not connect.
  static Future<String?> connect(SstpServer server, {Duration timeout = const Duration(seconds: 35)}) async {
    if (!supported) return 'SSTP needs Windows.';
    await disconnect();

    final address = server.address.replaceAll("'", '');
    final name = entryName.replaceAll("'", "''");
    final script = [
      r"$ErrorActionPreference = 'Stop'",
      "Remove-VpnConnection -Name '$name' -Force -ErrorAction SilentlyContinue",
      "Add-VpnConnection -Name '$name' -ServerAddress '$address' -TunnelType Sstp "
          '-EncryptionLevel Optional -AuthenticationMethod MSChapv2 -RememberCredential -Force',
      "Write-Output 'ORYVEX-OK'",
    ].join('; ');
    final String made;
    try {
      made = await _run(
        'powershell.exe',
        ['-NoLogo', '-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-Command', script],
        const Duration(seconds: 25),
      );
    } on TimeoutException {
      return 'Windows took too long to create the VPN entry.';
    } on ProcessException catch (e) {
      return 'Could not run PowerShell: ${e.message}';
    }
    if (!made.contains('ORYVEX-OK')) {
      return _lastLine(made, fallback: 'Windows could not create the SSTP entry.');
    }

    String dialed;
    try {
      dialed = await _run('rasdial', [entryName, user, password], timeout);
    } on TimeoutException {
      await disconnect();
      return 'No answer within ${timeout.inSeconds} s.';
    } on ProcessException catch (e) {
      return 'Could not run rasdial: ${e.message}';
    }
    if (await isConnected()) return null;
    await disconnect();
    return _lastLine(dialed, fallback: 'The server did not accept the connection.');
  }

  /// Hangs up, if connected. Never throws.
  static Future<void> disconnect() async {
    if (!supported) return;
    try {
      await _run('rasdial', [entryName, '/disconnect'], const Duration(seconds: 12));
    } catch (_) {}
  }

  /// Whether Windows lists the app's entry among the connected ones.
  static Future<bool> isConnected() async {
    if (!supported) return false;
    try {
      final out = await _run('rasdial', const [], const Duration(seconds: 8));
      return out.split(RegExp(r'\r?\n')).any((l) => l.trim() == entryName);
    } catch (_) {
      return false;
    }
  }

  static final _subinterface = RegExp(r'^\s*\d+\s+\d+\s+(\d+)\s+(\d+)\s+(.+?)\s*$');

  /// The adapter's byte counters from `netsh interface ipv4 show subinterfaces`, or null.
  static Future<SstpCounters?> counters() async {
    if (!supported) return null;
    try {
      final out = await _run('netsh', const ['interface', 'ipv4', 'show', 'subinterfaces'], const Duration(seconds: 6));
      for (final line in out.split(RegExp(r'\r?\n'))) {
        final m = _subinterface.firstMatch(line);
        if (m != null && m.group(3) == entryName) {
          return SstpCounters(int.parse(m.group(1)!), int.parse(m.group(2)!));
        }
      }
    } catch (_) {}
    return null;
  }

  static String _lastLine(String out, {required String fallback}) {
    final lines = out
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty && !l.startsWith('+') && !l.startsWith('At line'))
        .toList();
    if (lines.isEmpty) return fallback;
    final error = lines.lastWhere((l) => RegExp(r'\b\d{3,4}\b').hasMatch(l), orElse: () => lines.last);
    return error.length > 200 ? '${error.substring(0, 197)}...' : error;
  }

  /// Runs a console tool without flashing a console window (a GUI app's child would get one),
  /// and returns everything it printed. Detached processes have no exit code, so callers read
  /// the output, or ask Windows for the result afterwards.
  static Future<String> _run(String exe, List<String> args, Duration timeout) async {
    final proc = await Process.start(exe, args, mode: ProcessStartMode.detachedWithStdio);
    unawaited(proc.stdin.close().catchError((Object _) {}));
    final out = StringBuffer();
    final done = Future.wait<void>([
      proc.stdout.transform(const Utf8Decoder(allowMalformed: true)).forEach(out.write),
      proc.stderr.transform(const Utf8Decoder(allowMalformed: true)).forEach(out.write),
    ]);
    try {
      await done.timeout(timeout);
    } on TimeoutException {
      try {
        Process.killPid(proc.pid);
      } catch (_) {}
      rethrow;
    }
    return out.toString();
  }
}
