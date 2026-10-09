import 'dart:convert';

import '../models/ai_profile.dart';

class WritingDraft {
  final String persona;
  final String greeting;
  final String chatLog;
  final List<String> rules;

  const WritingDraft({
    required this.persona,
    required this.greeting,
    required this.chatLog,
    required this.rules,
  });

  factory WritingDraft.fromProfile(AiProfile profile) => WritingDraft(
    persona: profile.persona,
    greeting: profile.greeting,
    chatLog: profile.chatLog,
    rules: profile.customRules,
  );

  Map<String, dynamic> toMap() => {
    'persona': persona,
    'greeting': greeting,
    'chatLog': chatLog,
    'rules': rules,
  };

  factory WritingDraft.fromMap(Map map) => WritingDraft(
    persona: map['persona'] is String ? map['persona'] as String : '',
    greeting: map['greeting'] is String ? map['greeting'] as String : '',
    chatLog: map['chatLog'] is String ? map['chatLog'] as String : '',
    rules: map['rules'] is List
        ? (map['rules'] as List)
              .whereType<String>()
              .map((rule) => rule.trim())
              .where((rule) => rule.isNotEmpty)
              .toList()
        : const [],
  );

  bool get isEmpty =>
      persona.isEmpty && greeting.isEmpty && chatLog.isEmpty && rules.isEmpty;
}

({String reply, WritingDraft draft}) parseWritingReply(
  String raw,
  WritingDraft previous,
) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    throw const FormatException('创作助手未返回可导入的内容，请再试一次');
  }
  final decoded = jsonDecode(raw.substring(start, end + 1));
  if (decoded is! Map || decoded['reply'] is! String) {
    throw const FormatException('创作助手返回格式不完整，请再试一次');
  }
  final merged = {...previous.toMap(), ...decoded};
  return (
    reply: (decoded['reply'] as String).trim(),
    draft: WritingDraft.fromMap(merged),
  );
}

String writingAssistantPrompt(WritingDraft draft) =>
    '''
你是微信 AI 角色的创作助手。与用户自然讨论角色设定、开场白、对话样本和每轮回复规则。
根据用户本轮要求更新草稿；用户未要求修改的字段保持原样。不要把真实聊天事实编造为角色资料。
对话样本 chatLog 用“我：...\\n角色：...”的多轮格式；rules 每项是可执行的一条规则。
每次只返回一个 JSON 对象，不要 Markdown 或额外文字。字段固定为：
{"reply":"给用户的简短自然回复","persona":"完整人设","greeting":"开场白","chatLog":"完整对话样本","rules":["规则1"]}
四项草稿字段每次都必须给出完整更新结果。用户可以要求清空某项，此时返回空字符串或空数组。
当前草稿：${jsonEncode(draft.toMap())}
''';
