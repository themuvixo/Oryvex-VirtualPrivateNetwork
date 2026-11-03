/// Turns the core's raw failure text into one sentence a person can act on.
String friendlyError(String raw) {
  var msg = raw.trim();

  // `Error: Other("...")`, the shape Rust prints when main returns an error.
  final wrapped = RegExp(r'^Error:\s*\w+\("(.*)"\)\s*$', dotAll: true).firstMatch(msg);
  if (wrapped != null) {
    msg = wrapped.group(1)!.replaceAll(r'\"', '"').replaceAll(r'\n', ' ');
  } else if (msg.startsWith('Error: ')) {
    msg = msg.substring(7);
  }
  msg = msg.replaceFirst(RegExp(r'^\[[-!*+=]\]\s*'), '');
  final lower = msg.toLowerCase();

  final port = RegExp(r'cannot use \S*?:(\d+)').firstMatch(msg)?.group(1);
  if (lower.contains('already listens there') ||
      lower.contains('address already in use') ||
      lower.contains('os error 10048') ||
      lower.contains('os error 98')) {
    return port != null
        ? 'Port $port is busy. Another app is using it: close it, or pick another port in Settings.'
        : 'A local port is busy. Close the other app using it, or pick another port in Settings.';
  }
  if (lower.contains('excludedportrange') || (lower.contains('permission denied') && port != null)) {
    return 'Windows reserves port $port. Pick another port in Settings.';
  }
  if (lower.contains('no tor support')) {
    return 'This build has no Tor support. Turn the Tor option off in Settings.';
  }
  if (lower.contains('unknown option')) {
    final opt = RegExp(r"unknown option '([^']+)'").firstMatch(msg)?.group(1);
    return 'The core does not know the option ${opt ?? ''}. Check "Extra core arguments" in Settings.';
  }
  if (lower.contains('requires a value')) {
    return 'An option in "Extra core arguments" is missing its value.';
  }
  if (lower.contains('identity refused')) {
    return 'Cloudflare refused the saved identity. Connect again and a fresh one is registered.';
  }
  if (lower.contains('no clean endpoint') || lower.contains('scan deadline')) {
    return 'No gateway answered. Try another protocol, the Thorough scan, or HTTP/2.';
  }
  // Keep the first sentence only; the full text stays in Activity.
  final cut = msg.indexOf('\n');
  if (cut > 0) msg = msg.substring(0, cut);
  if (msg.length > 220) msg = '${msg.substring(0, 217)}...';
  return msg.isEmpty ? 'Something went wrong. See Activity for details.' : msg;
}
