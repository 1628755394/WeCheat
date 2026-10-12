import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/core/theme.dart';
import 'package:wecheat/core/widgets/wechat_dialog.dart';
import 'package:wecheat/features/common/model_picker.dart';
import 'package:wecheat/providers/chat_provider.dart';
import 'package:wecheat/services/ollama_service.dart';
import 'package:wecheat/services/cc_switch_base.dart';

class _UnavailableOllama extends OllamaService {
  @override
  Future<List<String>> listModels() async => throw Exception('offline');
}

class _RefreshingOllama extends OllamaService {
  int scans = 0;
  @override
  Future<List<String>> listModels() async =>
      scans++ == 0 ? ['qwen3:4b'] : ['qwen3:4b', 'qwen3:8b'];
}

void main() {
  testWidgets('refresh button rescans Ollama and cc-switch models', (
    tester,
  ) async {
    final ollama = _RefreshingOllama();
    var providerScans = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ollamaServiceProvider.overrideWithValue(ollama),
          ccProvidersLoaderProvider.overrideWithValue(() async {
            providerScans++;
            return [
              CcProvider(
                id: 'cc',
                name: '测试渠道',
                appType: 'claude',
                baseUrl: 'https://example.invalid',
                apiKey: 'secret',
                model: 'claude-sonnet',
                models: const ['claude-sonnet', 'claude-opus'],
              ),
            ];
          }),
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
    expect(find.text('qwen3:4b'), findsOneWidget);
    expect(find.text('claude-opus'), findsOneWidget);
    await tester.tap(find.text('检索本地和 cc-switch 模型'));
    await tester.pumpAndSettle();
    expect(find.text('qwen3:8b'), findsWidgets);
    expect(providerScans, 2);
    expect(tester.takeException(), isNull);
  });
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
      await tester.pumpAndSettle();
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
