import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/features/contact/persona_polish_dialog.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/providers/chat_provider.dart';
import 'package:wecheat/services/llm_service.dart';
import 'package:wecheat/services/ollama_service.dart';
import 'package:wecheat/services/remote_llm_service.dart';

class _PolishLlm extends LlmService {
  _PolishLlm() : super(OllamaService(), RemoteLlmService());
  final output = StreamController<String>();
  AiProfile? selectedProfile;
  String? prompt;
  String? requirement;
  @override
  Stream<String> chat(
    AiProfile profile,
    List<({String role, String content})> history, {
    String? systemPrompt,
  }) {
    selectedProfile = profile;
    prompt = systemPrompt;
    requirement = history.single.content;
    return output.stream;
  }
}

void main() {
  testWidgets(
    'polish uses selected model and applies only reviewed editable draft',
    (tester) async {
      final llm = _PolishLlm();
      String? adopted;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [llmServiceProvider.overrideWithValue(llm)],
          child: MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: TextButton(
                  onPressed: () async => adopted = await showDialog<String>(
                    context: context,
                    builder: (_) => const PersonaPolishDialog(
                      name: '小雨',
                      persona: '温柔的医生',
                      profile: AiProfile(
                        provider: 'openai',
                        model: 'selected-model',
                        baseUrl: 'https://example.test',
                      ),
                    ),
                  ),
                  child: const Text('润色'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('润色'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '增加职业背景');
      await tester.tap(find.text('生成'));
      await tester.pump();
      expect(llm.selectedProfile!.model, 'selected-model');
      expect(llm.selectedProfile!.provider, 'openai');
      expect(llm.prompt, contains('温柔的医生'));
      expect(llm.requirement, '增加职业背景');
      llm.output.add('润色后的');
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.widgetWithText(FilledButton, '采用'))
            .onPressed,
        isNull,
      );
      llm.output.add('人设');
      await llm.output.close();
      await tester.pumpAndSettle();
      expect(adopted, isNull);
      await tester.enterText(find.byType(TextField).last, '我修改的草稿');
      await tester.tap(find.text('采用'));
      await tester.pumpAndSettle();
      expect(adopted, '我修改的草稿');
    },
  );

  testWidgets('stopping generation never adopts partial output', (
    tester,
  ) async {
    final llm = _PolishLlm();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [llmServiceProvider.overrideWithValue(llm)],
        child: const MaterialApp(
          home: PersonaPolishDialog(
            name: '小雨',
            persona: '',
            profile: AiProfile(),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '温柔的医生');
    await tester.tap(find.text('生成'));
    await tester.pump();
    llm.output.add('未完成');
    await tester.pump();
    await tester.tap(find.text('停止生成'));
    await tester.pump();
    expect(llm.output.hasListener, isFalse);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '采用'))
          .onPressed,
      isNull,
    );
    unawaited(llm.output.close());
    await tester.pumpWidget(const SizedBox());
  });
}
