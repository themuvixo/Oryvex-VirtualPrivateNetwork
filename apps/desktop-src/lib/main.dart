import 'package:flutter/widgets.dart';
import 'package:oryvex_shared/oryvex_shared.dart';
import 'package:window_manager/window_manager.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  // The native Windows caption is replaced by OryvexVPN's own title bar (see _TopNav in
  // oryvex_shared). Applying the style through waitUntilReadyToShow makes it stick before the
  // first visible frame, so the default grey Windows bar never appears.
  const options = WindowOptions(
    title: 'OryvexVPN',
    size: Size(480, 860),
    minimumSize: Size(420, 600),
    titleBarStyle: TitleBarStyle.hidden,
    windowButtonVisibility: false,
    backgroundColor: Color(0xFF0B0D12),
  );
  await windowManager.waitUntilReadyToShow(options, () async {
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
    await windowManager.setPreventClose(true);
    await windowManager.setResizable(true);
    await windowManager.show();
    await windowManager.focus();
  });
  await runOryvex(DesktopBackend());
}
