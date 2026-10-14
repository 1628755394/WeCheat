import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' show FTheme;
import 'package:wecheat/features/mine/mine_page.dart';
import 'package:wecheat/models/contact.dart';
import 'package:wecheat/providers/user_provider.dart';
import 'package:wecheat/providers/contact_override_provider.dart';
import 'package:wecheat/core/theme.dart';

class _User extends CurrentUser {
  @override
  Contact build() => const Contact(id: 'me', name: '测试用户', wechatId: 'me');
}
class _Overrides extends ContactOverrides {
  @override
  Map<String, Contact> build() => {};
}

void main() {
  testWidgets('mine renders all remaining menus without stale indexes', (tester) async {
    for (final size in [const Size(1280, 800), const Size(320, 568)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(ProviderScope(overrides: [
        currentUserProvider.overrideWith(_User.new), contactOverridesProvider.overrideWith(_Overrides.new),
      ], child: MaterialApp(
        theme: buildAppTheme(),
        builder: (context, child) => FTheme(
          data: appForuiTheme,
          child: child ?? const SizedBox.shrink(),
        ),
        home: const MinePage(),
      )));
      expect(find.text('收藏'), findsOneWidget);
      expect(find.text('朋友圈'), findsOneWidget);
      expect(find.text('表情'), findsOneWidget);
      expect(find.text('设置'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox());
    await tester.binding.setSurfaceSize(null);
  });
}
