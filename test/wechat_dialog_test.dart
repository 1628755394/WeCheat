import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/core/theme.dart';
import 'package:wecheat/core/widgets/wechat_dialog.dart';

void main() {
  testWidgets('confirmation actions match WeChat order and remain accessible', (
    tester,
  ) async {
    for (final size in [
      const Size(1280, 800),
      const Size(320, 568),
      const Size(568, 320),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                child: const Text('打开'),
                onPressed: () => showDialog(
                  context: context,
                  builder: (context) => WeChatDialog(
                    title: const Text('删除“公众号”？'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          '删除',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
      expect(
        tester.getRect(find.text('删除')).left,
        lessThan(tester.getRect(find.text('取消')).left),
      );
      expect(
        tester
            .getSize(
              find
                  .descendant(
                    of: find.byType(Dialog),
                    matching: find.byType(Material),
                  )
                  .first,
            )
            .width,
        lessThanOrEqualTo(420),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }
    await tester.binding.setSurfaceSize(null);
  });

  testWidgets('long forms stay scrollable above keyboard', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pumpWidget(
      MaterialApp(
        theme: buildAppTheme(),
        home: MediaQuery(
          data: const MediaQueryData(
            size: Size(320, 568),
            viewInsets: EdgeInsets.only(bottom: 250),
          ),
          child: Scaffold(
            body: WeChatDialog(
              title: const Text('配置角色'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var index = 0; index < 10; index++)
                    TextField(
                      decoration: InputDecoration(labelText: '字段 $index'),
                    ),
                ],
              ),
              actions: [
                TextButton(onPressed: () {}, child: const Text('取消')),
                FilledButton(onPressed: () {}, child: const Text('保存')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('保存'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
