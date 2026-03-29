import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutterdemo2/app/app_session.dart';
import 'package:flutterdemo2/main.dart';
import 'package:flutterdemo2/ui/home_page.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('首页 UI 可构建（不加载 Bonsoir）', (WidgetTester tester) async {
    final session = AppSession(dryRunForTest: true);
    await session.bootstrap();
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: session,
        child: const MaterialApp(home: HomePage()),
      ),
    );
    await tester.pump();

    expect(find.text('内网传输工具'), findsOneWidget);
    expect(find.textContaining('Rust API 烟测'), findsNothing);
  });

  testWidgets('XTransferApp 与 dryRun Session', (WidgetTester tester) async {
    final session = AppSession(dryRunForTest: true);
    await session.bootstrap();
    await tester.pumpWidget(XTransferApp(session: session));
    await tester.pump();
    expect(find.text('内网传输工具'), findsOneWidget);
  });
}
