// 基础冒烟测试 — 仅保证应用入口可加载
import 'package:flutter_test/flutter_test.dart';

import 'package:flutter_download_manager/app.dart';

void main() {
  testWidgets('应用可以构造', (WidgetTester tester) async {
    await tester.pumpWidget(const DownloadManagerApp());
    expect(find.byType(DownloadManagerApp), findsOneWidget);
  });
}
