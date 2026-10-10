import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/core/theme.dart';
import 'package:wecheat/core/widgets/wechat_dialog.dart';
import 'package:wecheat/features/common/model_picker.dart';
import 'package:wecheat/providers/chat_provider.dart';
import 'package:wecheat/services/ollama_service.dart';

class _UnavailableOllama extends OllamaService {
  @override
  Future<List<String>> listModels() async => throw Exception('offline');
}

void main() {
  testWidgets(
    'model picker opens and allows manual configuration while local service is offline',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            ollamaServiceProvider.overrideWithValue(_UnavailableOllama()),
            ccProvidersLoaderProvider.overrideWithValue(
              () async => throw Exception('unavailable'),
            ),
          ],
          child: MaterialApp(
            theme: buildAppTheme(),
            home: Consumer(
              builder: (context, ref, _) => Scaffold(
                body: TextButton(
                  onPressed: () =>
                      showModelPicker(context, ref, const ModelChoice()),
                  child: const Text('模型'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('模型'));
      await tester.pumpAndSettle();
      expect(find.text('选择模型'), findsOneWidget);
      expect(find.textContaining('无法获取模型列表'), findsOneWidget);
      expect(find.textContaining('服务商配置读取失败'), findsOneWidget);
      await tester.ensureVisible(find.text('手动填写 Base URL + 密钥'));
      await tester.tap(find.text('手动填写 Base URL + 密钥'));
      await tester.pumpAndSettle();
      expect(find.byType(WeChatDialog), findsOneWidget);
      expect(find.text('Base URL'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
