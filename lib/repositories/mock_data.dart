import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/moment.dart';
import 'ai_characters.dart';

/// Mock 数据源：当前用户 + 四位内置 AI 角色
abstract final class MockData {
  /// 当前登录用户（我）
  static const me = Contact(
    id: 'me',
    name: 'Devin',
    wechatId: 'wecheat_dev',
    region: '上海',
    avatarAsset: 'assets/avatars/me.jpg',
  );

  /// 通讯录基础联系人
  static List<Contact> get contacts => [
    for (final c in AiCharacters.all)
      if (!AiCharacters.deletedFriends().contains(c.contact.id)) c.contact,
  ];

  static List<Conversation> seedConversations() {
    final now = DateTime.now();
    return [
      for (final c in AiCharacters.all)
        if (!AiCharacters.deletedFriends().contains(c.contact.id))
          AiCharacters.conversationOf(c, now),
      AiCharacters.groupConversation(now).copyWith(members: contacts),
    ];
  }

  /// 首次启动时的种子聊天记录：各角色开场白
  static Map<String, List<Message>> seedMessages() {
    final now = DateTime.now();
    return {
      for (final c in AiCharacters.all)
        if (!AiCharacters.deletedFriends().contains(c.contact.id))
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
