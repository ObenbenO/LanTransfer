import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app/app_session.dart';
import 'services/windows_firewall_setup.dart';
import 'src/rust/frb_generated.dart';
import 'ui/home_page.dart';
import 'utils/desktop_chrome.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (isDesktopNative) {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: '内网传输工具',
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: false,
      ),
      () async {
        await windowManager.show();
        await windowManager.focus();
      },
    );
  }
  await RustLib.init();
  final session = AppSession();
  await session.bootstrap();
  runApp(XTransferApp(session: session));
}

class XTransferApp extends StatefulWidget {
  const XTransferApp({super.key, required this.session});

  final AppSession session;

  @override
  State<XTransferApp> createState() => _XTransferAppState();
}

class _XTransferAppState extends State<XTransferApp> {
  final GlobalKey<ScaffoldMessengerState> _messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowWindowsFirewallSetup(
        context,
        widget.session,
        messenger: _messengerKey.currentState,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: widget.session,
      child: MaterialApp(
        scaffoldMessengerKey: _messengerKey,
        title: '内网传输工具',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}
