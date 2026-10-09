import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/services/ai_prompt.dart';
import 'package:wecheat/services/writing_draft.dart';

void main() {
  test('old profiles default to text replies and no custom rules', () {
    final profile = AiProfile.fromMap({'persona': '旧角色'});
    expect(profile.autoVoiceMessages, isFalse);
    expect(profile.customRules, isEmpty);

    final restored = AiProfile.fromMap(
      profile
          .copyWith(autoVoiceMessages: true, customRules: ['每次先回应问题'])
          .toMap(),
    );
    expect(restored.autoVoiceMessages, isTrue);
    expect(restored.customRules, ['每次先回应问题']);
    expect(buildAiSystemPrompt(restored), contains('每次先回应问题'));
  });

  test(
    'writing reply parses complete draft and preserves unchanged fields',
    () {
      const previous = WritingDraft(
        persona: '旧人设',
        greeting: '你好',
        chatLog: '我：早\n角色：早',
        rules: ['简短回复'],
      );
      final parsed = parseWritingReply(
        '```json\n{"reply":"改好了","persona":"新人设",'
        '"greeting":"你好","chatLog":"我：早\\n角色：早",'
        '"rules":["简短回复","不要复读"]}\n```',
        previous,
      );
      expect(parsed.reply, '改好了');
      expect(parsed.draft.persona, '新人设');
      expect(parsed.draft.chatLog, previous.chatLog);
      expect(parsed.draft.rules, ['简短回复', '不要复读']);
    },
  );

  test('invalid draft cannot be imported as assistant prose', () {
    expect(
      () => parseWritingReply(
        '我已经写好啦',
        WritingDraft.fromProfile(const AiProfile()),
      ),
      throwsFormatException,
    );
  });
}
