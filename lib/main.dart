import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app/app_session.dart';
import 'services/windows_firewall_setup.dart';
import 'src/rust/frb_generated.dart';
import 'ui/home_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
        title: 'X传输工具',
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
          useMaterial3: true,
        ),
        home: const HomePage(),
      ),
    );
  }
}
