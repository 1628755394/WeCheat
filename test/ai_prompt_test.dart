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

  test('知识库条目少时全部注入（保证用户导入内容能被读到）', () {
    const profile = AiProfile(knowledge: ['完全无关的天文知识xyz']);
    final p = buildAiSystemPrompt(profile, userText: '晚上吃什么');
    expect(p, contains('【参考知识】'));
    expect(p, contains('天文知识'));
  });

  test('聊天记录无法解析时作为发言示例注入', () {
    const profile = AiProfile(chatLog: '哈哈好的呀');
    final p = buildAiSystemPrompt(profile);
    expect(p, contains('【说话风格示例】'));
    expect(p, contains('哈哈好的呀'));
  });

  test('聊天记录已解析成轮次时不重复注入', () {
    const profile = AiProfile(chatLog: '林晓雨: 哈哈好的呀');
    final p = buildAiSystemPrompt(profile, styleInHistory: true);
    expect(p, isNot(contains('【说话风格示例】')));
  });

  test('单行格式聊天记录解析成 few-shot 轮次', () {
    final turns = parseStyleTurns('我: 晚上吃啥\n林晓雨: 吃火锅呀\n我: 行\n林晓雨: 那就楼下那家');
    expect(turns.length, 4);
    // 林晓雨发言最多 → assistant；我 → user
    expect(turns[0].role, 'user');
    expect(turns[1].role, 'assistant');
    expect(turns[1].content, '吃火锅呀');
    expect(turns[3].role, 'assistant');
  });

  test('微信导出格式（名字 时间 换行 内容）解析', () {
    final turns = parseStyleTurns('林晓雨 14:20\n晚上一起吃饭吗\n我 14:21\n好啊去哪');
    expect(turns.length, 2);
    expect(turns[0].role, 'assistant');
    expect(turns[0].content, '晚上一起吃饭吗');
    expect(turns[1].role, 'user');
  });

  test('PC 微信多选复制格式（名字 日期 时间）解析', () {
    final turns = parseStyleTurns(
        '星仔  2024-09-20 14:30:25\n卧槽今天又加班\n我  2024-09-20 14:31:02\n辛苦了啊');
    expect(turns.length, 2);
    expect(turns[0].role, 'assistant');
    expect(turns[0].content, '卧槽今天又加班');
    expect(turns[1].role, 'user');
    expect(turns[1].content, '辛苦了啊');
  });

  test('空/无法解析的聊天记录返回空', () {
    expect(parseStyleTurns(''), isEmpty);
    expect(parseStyleTurns('没有说话人标记的随便一段文字'), isEmpty);
  });

  test('通话模式附加口语化约束', () {
    final p = buildAiSystemPrompt(const AiProfile(), inCall: true);
    expect(p, contains('口语化'));
  });
}
