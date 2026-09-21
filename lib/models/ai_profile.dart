/// AI 助手资料：角色人设 + 知识库条目 + 聊天记录样本（风格模仿）
/// 存 Hive，key 为会话 id
class AiProfile {
  /// 人设描述：名字、身份、性格、说话风格等
  final String persona;

  /// 知识库条目（本地简单检索，取相关条目注入 prompt）
  final List<String> knowledge;

  /// 聊天记录原文样本：AI 会模仿其中人物的语气
  final String chatLog;

  const AiProfile({
    this.persona = '',
    this.knowledge = const [],
    this.chatLog = '',
  });

  Map<String, dynamic> toMap() => {
        'persona': persona,
        'knowledge': knowledge,
        'chatLog': chatLog,
      };

  factory AiProfile.fromMap(Map map) => AiProfile(
        persona: (map['persona'] as String?) ?? '',
        knowledge:
            (map['knowledge'] as List?)?.cast<String>() ?? const [],
        chatLog: (map['chatLog'] as String?) ?? '',
      );

  AiProfile copyWith({
    String? persona,
    List<String>? knowledge,
    String? chatLog,
  }) =>
      AiProfile(
        persona: persona ?? this.persona,
        knowledge: knowledge ?? this.knowledge,
        chatLog: chatLog ?? this.chatLog,
      );
}
