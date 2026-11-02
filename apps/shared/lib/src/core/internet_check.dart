import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Returns true only when at least one HTTPS internet probe can be reached.
/// A connected Wi-Fi/mobile interface alone does not guarantee internet access.
Future<bool> hasInternetAccess() async {
  final results = await Future.wait<bool>([
    _probe(Uri.https('connectivitycheck.gstatic.com', '/generate_204'), HttpStatus.noContent),
    _probe(Uri.https('www.cloudflare.com', '/cdn-cgi/trace'), HttpStatus.ok),
  ]);
  return results.any((reachable) => reachable);
}

Future<bool> _probe(Uri uri, int expectedStatus) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 3);
  try {
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 4));
    request.followRedirects = false;
    request.headers.set(HttpHeaders.cacheControlHeader, 'no-cache');
    final response = await request.close().timeout(const Duration(seconds: 4));
    final body = await response.transform(utf8.decoder).join().timeout(const Duration(seconds: 2));
    if (expectedStatus == HttpStatus.noContent) {
      return response.statusCode == HttpStatus.noContent;
    }
    // A captive portal can return HTTP 200 for any URL. Require Cloudflare's expected trace
    // fields so a sign-in splash page is not mistaken for working internet access.
    return response.statusCode == HttpStatus.ok &&
        body.contains(RegExp(r'^ip=', multiLine: true)) &&
        body.contains(RegExp(r'^loc=', multiLine: true));
  } on Object {
    return false;
  } finally {
    client.close(force: true);
  }
}
