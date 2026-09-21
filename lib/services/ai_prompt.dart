import '../models/ai_profile.dart';

/// 组装发给 Ollama 的 system prompt：
/// 人设 > 检索到的知识条目 > 聊天记录风格样本
String buildAiSystemPrompt(
  AiProfile profile, {
  String userText = '',
  bool inCall = false,
}) {
  final buf = StringBuffer();

  // 角色卡
  if (profile.persona.isEmpty) {
    buf.write('你是 WeCheat 内置的 AI 助手，说话简洁自然，像在微信里和朋友聊天。');
  } else {
    buf.write('【角色设定】\n${profile.persona}\n请始终以该角色的身份、性格、语气回复，不要跳出角色。');
  }

  // 通话场景附加约束
  if (inCall) {
    buf.write('\n\n当前是语音通话场景：回复要口语化、简短（一两句话），像打电话一样自然，不要用列表和 Markdown。');
  }

  // 知识库：按与用户提问的字面重叠度检索相关条目（本地简单检索）
  final hits = _retrieveKnowledge(profile.knowledge, userText);
  if (hits.isNotEmpty) {
    buf.write('\n\n【参考知识】\n');
    for (final h in hits) {
      buf.write('- ${_truncate(h, 300)}\n');
    }
  }

  // 聊天记录风格模仿
  if (profile.chatLog.isNotEmpty) {
    buf.write(
        '\n\n【风格参考】以下是该角色的真实聊天记录，请模仿其说话语气、用词和标点习惯：\n${_truncate(profile.chatLog, 600)}');
  }

  return buf.toString();
}

/// 检索与提问最相关的知识条目（中文按 bigram 重叠计分），最多 3 条
List<String> _retrieveKnowledge(List<String> entries, String query) {
  if (entries.isEmpty) return const [];
  if (query.trim().isEmpty) {
    return entries.take(1).toList();
  }
  final q = _bigrams(query);
  final scored = [
    for (final e in entries)
      (entry: e, score: _bigrams(e).intersection(q).length),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return [
    for (final s in scored.where((s) => s.score > 0).take(3)) s.entry,
  ];
}

Set<String> _bigrams(String s) {
  final t = s.replaceAll(RegExp(r'\s'), '');
  return {for (var i = 0; i < t.length - 1; i++) t.substring(i, i + 2)};
}

String _truncate(String s, int max) => s.length <= max ? s : s.substring(0, max);
