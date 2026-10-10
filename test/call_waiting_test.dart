import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/features/call/call_waiting_view.dart';
import 'package:wecheat/models/contact.dart';
import 'package:wecheat/providers/contact_override_provider.dart';

void main() {
  testWidgets(
    'invitation stays readable on desktop and mobile with reduced effects',
    (tester) async {
      for (final size in [
        const Size(1280, 800),
        const Size(320, 568),
        const Size(390, 844),
      ]) {
        await tester.binding.setSurfaceSize(size);
        for (final animate in [true, false]) {
          await tester.pumpWidget(
            ProviderScope(
              overrides: [
                contactOverridesProvider.overrideWith(() => _Overrides()),
              ],
              child: MaterialApp(
                home: Scaffold(
                  body: CallWaitingView(
                    contact: const Contact(
                      id: 'test',
                      name: '宝青坊主',
                      avatarAsset: 'assets/avatars/baoqingfangzhu.png',
                    ),
                    name: '宝青坊主',
                    isVideo: true,
                    animationsEnabled: animate,
                    reducedEffects: false,
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 400));
          expect(find.text('等待对方接受视频通话邀请'), findsOneWidget);
          expect(find.text('宝青坊主'), findsOneWidget);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.binding.setSurfaceSize(null);
    },
  );
}

class _Overrides extends ContactOverrides {
  @override
  Map<String, Contact> build() => {};
}
