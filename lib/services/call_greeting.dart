import 'dart:math';

import '../models/ai_profile.dart';

String buildCallGreetingPrompt(
  AiProfile profile,
  List<({String role, String content})> history, {
  Random? random,
}) {
  const approaches = [
    '轻松问候，问问对方现在在做什么',
    '用符合性格的小玩笑迎接对方',
    '承接最近聊天中的话题，亲切地打招呼',
    '表达见到对方的心情，再问一个简单的问题',
    '注意当前时段，自然地关心对方',
  ];
  final approach = approaches[(random ?? Random()).nextInt(approaches.length)];
  final recent = history
      .where((turn) => turn.role == 'assistant')
      .map((turn) => turn.content)
      .toList()
      .reversed
      .take(3)
      .join('\n');
  return '视频或语音电话刚接通。请按你的人设、关系和最近聊天，写一句新的通话开场白。'
      '这次可以$approach。只输出自然说出口的话，1 到 2 句，先打招呼。'
      '不要照搬预设开场白，不要复用最近说过的句子，不要输出括号动作或解释提示。'
      '${profile.greeting.isEmpty ? '' : '\n以下仅作为语气参考：${profile.greeting}'}'
      '${recent.isEmpty ? '' : '\n避免重复这些最近发言：\n$recent'}';
}
