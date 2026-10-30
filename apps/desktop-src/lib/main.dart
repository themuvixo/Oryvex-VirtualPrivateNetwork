import 'package:flutter/widgets.dart';
import 'package:oryvex_shared/oryvex_shared.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden);
  await windowManager.setPreventClose(true);
  await windowManager.setResizable(true);
  await windowManager.setMinimumSize(const Size(420, 600));
  await runOryvex(DesktopBackend());
}
