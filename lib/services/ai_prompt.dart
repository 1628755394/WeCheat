import '../models/ai_profile.dart';

/// 组装发给 Ollama 的 system prompt：
/// 人设 > 知识条目 > 聊天记录样本（无法解析成对话时兜底放这里）
String buildAiSystemPrompt(
  AiProfile profile, {
  String userText = '',
  bool inCall = false,

  /// 聊天记录已解析成 few-shot 轮次插进消息历史时传 true，
  /// 避免同一份内容重复出现两次
  bool styleInHistory = false,
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

  // 知识库：条目少时全带上；多于 3 条时按字面重叠度取最相关的
  final hits = _retrieveKnowledge(profile.knowledge, userText);
  if (hits.isNotEmpty) {
    buf.write('\n\n【参考知识】\n');
    for (final h in hits) {
      buf.write('- ${_truncate(h, 300)}\n');
    }
  }

  // 聊天记录原文兜底：解析不出对话轮次时仍作为发言示例塞进 prompt
  if (profile.chatLog.isNotEmpty && !styleInHistory) {
    buf.write(
        '\n\n【说话风格示例】以下是该角色说过的话，请模仿其语气、用词和标点习惯：\n${_truncate(profile.chatLog, 1500)}');
  }

  return buf.toString();
}

/// 从聊天记录原文解析对话轮次：目标说话人→assistant，其他人→user。
/// 目标自动取除"我/Me"外发言最多的人（即要模仿的对象）。
/// 支持三种格式：
///   名字: 内容                    （单行）
///   名字 时间                     （下一行是内容）
///   名字 日期 时间                （PC 微信多选复制导出格式）
/// 返回空列表表示无法解析。
List<({String role, String content})> parseStyleTurns(String chatLog,
    {int max = 20}) {
  final lines = chatLog
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final inline = RegExp(r'^([^\s:：]{1,16})[:：]\s*(.+)$');
  // 名字 + [可选日期] + 时间，如 "张三 14:30" / "张三 2024-09-20 14:30:25"
  final head = RegExp(
      r'^([^\s:：]{1,16})\s+'
      r'(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+)?'
      r'\d{1,2}:\d{2}(:\d{2})?\s*$');

  final turns = <({String speaker, String content})>[];
  String? pendingSpeaker;
  for (final line in lines) {
    final m1 = inline.firstMatch(line);
    final m2 = head.firstMatch(line);
    if (m1 != null) {
      turns.add((speaker: m1.group(1)!, content: m1.group(2)!));
      pendingSpeaker = null;
    } else if (m2 != null) {
      pendingSpeaker = m2.group(1);
    } else if (pendingSpeaker != null) {
      turns.add((speaker: pendingSpeaker, content: line));
      pendingSpeaker = null;
    }
  }
  if (turns.isEmpty) return const [];

  // 目标说话人 = 除"我/Me"外发言最多的人
  final freq = <String, int>{};
  for (final t in turns) {
    if (t.speaker == '我' || t.speaker.toLowerCase() == 'me') continue;
    freq[t.speaker] = (freq[t.speaker] ?? 0) + 1;
  }
  if (freq.isEmpty) return const [];
  final target =
      freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

  return [
    for (final t in turns.reversed.take(max).toList().reversed)
      (role: t.speaker == target ? 'assistant' : 'user',
          content: t.content),
  ];
}

/// 知识库检索：≤3 条全返回；更多时按与用户提问的 bigram 重叠度取前 3
List<String> _retrieveKnowledge(List<String> entries, String query) {
  if (entries.isEmpty) return const [];
  if (entries.length <= 3 || query.trim().isEmpty) {
    return entries.take(3).toList();
  }
  final q = _bigrams(query);
  final scored = [
    for (final e in entries)
      (entry: e, score: _bigrams(e).intersection(q).length),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return [for (final s in scored.take(3)) s.entry];
}

Set<String> _bigrams(String s) {
  final t = s.replaceAll(RegExp(r'\s'), '');
  return {for (var i = 0; i < t.length - 1; i++) t.substring(i, i + 2)};
}

String _truncate(String s, int max) => s.length <= max ? s : s.substring(0, max);
