import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/services/ai_prompt.dart';

void main() {
  test('空资料使用默认提示词', () {
    final p = buildAiSystemPrompt(const AiProfile());
    expect(p, contains('AI 助手'));
    expect(p, isNot(contains('【参考知识】')));
  });

  test('人设注入 system prompt', () {
    final p = buildAiSystemPrompt(
        const AiProfile(persona: '你是林晓雨，说话温柔'));
    expect(p, contains('【角色设定】'));
    expect(p, contains('林晓雨'));
  });

  test('知识库按相关性检索注入', () {
    const profile = AiProfile(knowledge: [
      '用户喜欢篮球和游泳',
      '用户的生日是3月15日',
      '林晓雨养了一只猫',
    ]);
    final p = buildAiSystemPrompt(profile, userText: '我生日是什么时候');
    expect(p, contains('【参考知识】'));
    expect(p, contains('生日是3月15日'));
  });

  test('不相关条目不注入', () {
    const profile = AiProfile(knowledge: ['完全无关的天文知识xyz']);
    final p = buildAiSystemPrompt(profile, userText: '晚上吃什么');
    expect(p, isNot(contains('【参考知识】')));
  });

  test('聊天记录样本注入', () {
    const profile = AiProfile(chatLog: '林晓雨: 哈哈好的呀');
    final p = buildAiSystemPrompt(profile);
    expect(p, contains('【风格参考】'));
    expect(p, contains('哈哈好的呀'));
  });

  test('通话模式附加口语化约束', () {
    final p = buildAiSystemPrompt(const AiProfile(), inCall: true);
    expect(p, contains('口语化'));
  });
}
