import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/services/ai_prompt.dart';
import 'package:wecheat/services/repetition_policy.dart';

void main() {
  test('explicit say and repeat requests override repetition guard', () {
    for (final input in [
      '再说一遍',
      '你就说我爱你',
      '说一句晚安',
      '跟我说：你好',
      '重复一下刚才的话',
      'repeat that please',
    ]) {
      expect(userRequestsExactSpeech(input), isTrue, reason: input);
      expect(
        buildAiSystemPrompt(const AiProfile(), userText: input),
        contains('本轮明确复述请求'),
      );
    }
    for (final input in [
      '你为什么不说话',
      '不要重复刚才的话',
      '我今天有点难过',
      '继续讲你的故事',
      '不许再说一遍',
    ]) {
      expect(userRequestsExactSpeech(input), isFalse, reason: input);
    }
  });
}
