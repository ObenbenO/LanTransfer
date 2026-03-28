import 'package:flutter_test/flutter_test.dart';
import 'package:flutterdemo2/app/app_session.dart';
import 'package:flutterdemo2/main.dart';
import 'package:flutterdemo2/src/rust/frb_generated.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async => await RustLib.init());
  testWidgets('Rust 初始化后主界面可渲染', (WidgetTester tester) async {
    final session = AppSession(skipWindowsFirewallPrompt: true);
    await session.bootstrap();
    await tester.pumpWidget(XTransferApp(session: session));
    await tester.pump();
    expect(find.text('X传输工具'), findsOneWidget);
  });
}
