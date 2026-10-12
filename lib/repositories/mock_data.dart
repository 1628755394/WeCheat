import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/moment.dart';
import 'ai_characters.dart';

/// Mock 数据源：当前用户 + 内置 AI 助手；AI 角色见 ai_characters.dart
abstract final class MockData {
  /// 当前登录用户（我）
  static const me = Contact(
    id: 'me',
    name: 'Devin',
    wechatId: 'wecheat_dev',
    region: '上海',
    avatarAsset: 'assets/avatars/me.jpg',
  );

  /// 本地 AI 助手（走 Ollama，不是真人会话）
  static const aiAssistant = Contact(
    id: 'ai_assistant',
    name: 'AI 助手',
    wechatId: 'wecheat_ai',
    isAi: true,
  );

  /// 通讯录基础联系人：内置 AI 助手 + AI 角色（其余联系人都已清掉）
  static final contacts = <Contact>[
    aiAssistant,
    for (final c in AiCharacters.all) c.contact,
  ];

  static List<Conversation> seedConversations() {
    final now = DateTime.now();
    return [
      aiConversation(now),
      for (final c in AiCharacters.all) AiCharacters.conversationOf(c, now),
      AiCharacters.groupConversation(now),
    ];
  }

  /// AI 助手会话（单独抽出，老版本 Hive 数据升级时补种用）
  static Conversation aiConversation(DateTime now) => Conversation(
    id: 'conv_ai',
    contact: aiAssistant,
    lastMessage: '你好，我是本地 AI 助手，有什么可以帮你？',
    lastMessageTime: now.subtract(const Duration(minutes: 1)),
  );

  /// 首次启动时的种子聊天记录：AI 助手问候 + 各角色开场白
  static Map<String, List<Message>> seedMessages() {
    final now = DateTime.now();
    return {
      'conv_ai': [
        Message(
          id: 'ai_m1',
          conversationId: 'conv_ai',
          senderId: 'ai_assistant',
          isMe: false,
          type: MessageType.text,
          content: '你好，我是本地 AI 助手，有什么可以帮你？',
          createdAt: now.subtract(const Duration(minutes: 1)),
        ),
      ],
      for (final c in AiCharacters.all)
        c.conversationId: [AiCharacters.greetingMessage(c, now)],
    };
  }

  /// 朋友圈种子数据（AI 角色与我）
  static List<Moment> seedMoments() {
    final now = DateTime.now();
    Contact byName(String name) => contacts.firstWhere((c) => c.name == name);

    return [
      Moment(
        author: byName('雅儿贝德'),
        text: '纳萨力克的夜色很安静，适合陪安兹大人聊一会儿。',
        images: const ['assets/moments/p1.jpg', 'assets/moments/p2.jpg'],
        createdAt: now.subtract(const Duration(minutes: 40)),
        likes: const ['夏提雅·布拉德弗伦'],
        comments: const ['宝青坊主: 夜里说话，倒也不坏。'],
      ),
      Moment(
        author: byName('夏提雅·布拉德弗伦'),
        text: '今天也完成了训练，随时听候安兹大人的命令！',
        createdAt: now.subtract(const Duration(hours: 2)),
        likes: const ['雅儿贝德'],
      ),
      Moment(
        author: byName('宝青坊主'),
        images: const [
          'assets/moments/p4.jpg',
          'assets/moments/p5.jpg',
          'assets/moments/p6.jpg',
        ],
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        comments: const ['雅儿贝德: 很有品味。'],
      ),
      Moment(
        author: me,
        text: '新项目上线倒计时，加油',
        createdAt: now.subtract(const Duration(days: 2)),
        likes: const ['雅儿贝德', '宝青坊主'],
      ),
    ];
  }
}
