import 'package:flutter/widgets.dart';
import 'package:oryvex_shared/oryvex_shared.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await runOryvex(DesktopBackend());
}
