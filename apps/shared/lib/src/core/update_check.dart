import 'dart:convert';
import 'dart:io';

/// GitHub repo that publishes releases, as "owner/name". Set this before shipping.
const String kReleasesRepo = 'OWNER/OryvexCore';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseUrl,
    required this.updateAvailable,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseUrl;
  final bool updateAvailable;
}

/// Checks the latest GitHub release. Returns null when the check fails (offline, rate limit, no release).
Future<UpdateInfo?> checkForUpdate(String currentVersion) async {
  final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
  try {
    final uri = Uri.https('api.github.com', '/repos/$kReleasesRepo/releases/latest');
    final request = await client.getUrl(uri).timeout(const Duration(seconds: 8));
    request.headers.set(HttpHeaders.acceptHeader, 'application/vnd.github+json');
    request.headers.set(HttpHeaders.userAgentHeader, 'OryvexVPN-update-check');
    final response = await request.close().timeout(const Duration(seconds: 8));
    if (response.statusCode != HttpStatus.ok) return null;
    final body = await response.transform(utf8.decoder).join();
    final json = jsonDecode(body) as Map<String, dynamic>;
    final tag = (json['tag_name'] as String?) ?? '';
    final url = (json['html_url'] as String?) ?? 'https://github.com/$kReleasesRepo/releases';
    final latest = tag.replaceFirst(RegExp(r'^[vV]'), '');
    if (latest.isEmpty) return null;
    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latest,
      releaseUrl: url,
      updateAvailable: _isNewer(latest, currentVersion),
    );
  } on Object {
    return null;
  } finally {
    client.close(force: true);
  }
}

/// Compares dotted numeric versions like 1.2.10 against 1.2.9. Non-numeric parts are ignored.
bool _isNewer(String latest, String current) {
  List<int> parts(String v) => v
      .split(RegExp(r'[-+]'))
      .first
      .split('.')
      .map((p) => int.tryParse(p) ?? 0)
      .toList();
  final a = parts(latest);
  final b = parts(current);
  for (var i = 0; i < 3; i++) {
    final x = i < a.length ? a[i] : 0;
    final y = i < b.length ? b[i] : 0;
    if (x != y) return x > y;
  }
  return false;
}
