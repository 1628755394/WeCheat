import '../models/contact.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/moment.dart';

/// Mock 数据源：模拟后端返回的通讯录与会话数据
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

  static final contacts = <Contact>[
    aiAssistant,
    const Contact(id: 'c1', name: '林晓雨', wechatId: 'linxy_2024', region: '上海', avatarAsset: 'assets/avatars/c1.jpg'),
    const Contact(id: 'c2', name: '王建国', remark: '王哥', wechatId: 'wjg668', region: '北京', avatarAsset: 'assets/avatars/c2.jpg'),
    const Contact(id: 'c3', name: '文件传输助手', wechatId: 'filehelper'),
    const Contact(id: 'c4', name: '前端技术交流群', isGroup: true),
    const Contact(id: 'c5', name: '李雷', wechatId: 'lilei_hm', region: '杭州', avatarAsset: 'assets/avatars/c5.jpg'),
    const Contact(id: 'c6', name: '韩梅梅', wechatId: 'hanmm', region: '杭州', avatarAsset: 'assets/avatars/c6.jpg'),
    const Contact(id: 'c7', name: '家庭群', isGroup: true),
    const Contact(id: 'c8', name: '刘洋', remark: '产品经理-刘洋', wechatId: 'liuyang_pm', region: '深圳', avatarAsset: 'assets/avatars/c8.jpg'),
    const Contact(id: 'c9', name: '楼下快递驿站', wechatId: 'kd_yz001', avatarAsset: 'assets/avatars/c9.jpg'),
    const Contact(id: 'c10', name: '陈晓', wechatId: 'chenxiao', region: '成都', avatarAsset: 'assets/avatars/c10.jpg'),
    const Contact(id: 'c11', name: '赵磊', remark: '大学室友-赵磊', wechatId: 'zhaolei88', region: '武汉', avatarAsset: 'assets/avatars/c11.jpg'),
    const Contact(id: 'c12', name: '羽毛球俱乐部', isGroup: true),
    const Contact(id: 'c13', name: '周芷若', wechatId: 'zzr_ruo', region: '南京', avatarAsset: 'assets/avatars/c13.jpg'),
    const Contact(id: 'c14', name: '吴彦祖', wechatId: 'wyz_real', region: '广州', avatarAsset: 'assets/avatars/c14.jpg'),
  ];

  static List<Conversation> seedConversations() {
    final now = DateTime.now();
    Contact byId(String id) => contacts.firstWhere((c) => c.id == id);

    return [
      aiConversation(now),
      Conversation(
        id: 'conv3',
        contact: byId('c3'),
        lastMessage: '[图片]',
        lastMessageTime: now.subtract(const Duration(minutes: 3)),
        pinned: true,
      ),
      Conversation(
        id: 'conv1',
        contact: byId('c1'),
        lastMessage: '晚上一起吃饭吗？公司附近新开了家湘菜',
        lastMessageTime: now.subtract(const Duration(minutes: 12)),
        unreadCount: 3,
      ),
      Conversation(
        id: 'conv4',
        contact: byId('c4'),
        lastMessage: '阿伟: Flutter 3.47 的发布笔记有人看了吗',
        lastMessageTime: now.subtract(const Duration(minutes: 45)),
        unreadCount: 99,
        muted: true,
      ),
      Conversation(
        id: 'conv2',
        contact: byId('c2'),
        lastMessage: '方案我发你邮箱了，明天早上对一下',
        lastMessageTime: now.subtract(const Duration(hours: 2)),
        unreadCount: 1,
      ),
      Conversation(
        id: 'conv7',
        contact: byId('c7'),
        lastMessage: '妈: 周末回家吃饭，你爸买了大闸蟹',
        lastMessageTime: now.subtract(const Duration(hours: 5)),
        pinned: true,
        unreadCount: 2,
      ),
      Conversation(
        id: 'conv9',
        contact: byId('c9'),
        lastMessage: '您的包裹已放入3号柜，取件码 8842',
        lastMessageTime: now.subtract(const Duration(hours: 8)),
      ),
      Conversation(
        id: 'conv8',
        contact: byId('c8'),
        lastMessage: '这个需求评审改到周四下午了',
        lastMessageTime: now.subtract(const Duration(days: 1, hours: 2)),
      ),
      Conversation(
        id: 'conv6',
        contact: byId('c6'),
        lastMessage: '哈哈哈哈哈好的',
        lastMessageTime: now.subtract(const Duration(days: 1, hours: 6)),
        unreadCount: 5,
      ),
      Conversation(
        id: 'conv12',
        contact: byId('c12'),
        lastMessage: '教练: 本周六场地已定，老地方见',
        lastMessageTime: now.subtract(const Duration(days: 3)),
        muted: true,
        unreadCount: 12,
      ),
      Conversation(
        id: 'conv5',
        contact: byId('c5'),
        lastMessage: '代码 review 完了，LGTM',
        lastMessageTime: now.subtract(const Duration(days: 5)),
      ),
      Conversation(
        id: 'conv11',
        contact: byId('c11'),
        lastMessage: '国庆回武汉聚一波？',
        lastMessageTime: now.subtract(const Duration(days: 20)),
      ),
      Conversation(
        id: 'conv10',
        contact: byId('c10'),
        lastMessage: '收到，谢谢！',
        lastMessageTime: DateTime(now.year - 1, 11, 20),
      ),
    ];
  }

  /// AI 助手会话（单独抽出，老版本 Hive 数据升级时补种用）
  static Conversation aiConversation(DateTime now) => Conversation(
        id: 'conv_ai',
        contact: aiAssistant,
        lastMessage: '你好，我是本地 AI 助手，有什么可以帮你？',
        lastMessageTime: now.subtract(const Duration(minutes: 1)),
      );

  /// 首次启动时的种子聊天记录
  static Map<String, List<Message>> seedMessages() {
    final now = DateTime.now();

    Message msg(
      String id,
      String convId,
      String senderId,
      bool isMe,
      String content,
      DateTime time,
    ) =>
        Message(
          id: id,
          conversationId: convId,
          senderId: senderId,
          isMe: isMe,
          type: MessageType.text,
          content: content,
          createdAt: time,
        );

    return {
      'conv_ai': [
        msg('ai_m1', 'conv_ai', 'ai_assistant', false,
            '你好，我是本地 AI 助手，有什么可以帮你？', now.subtract(const Duration(minutes: 1))),
      ],
      'conv1': [
        msg('c1_m1', 'conv1', 'c1', false, '下班了吗？',
            now.subtract(const Duration(minutes: 15))),
        msg('c1_m2', 'conv1', 'me', true, '刚出公司，在路上了',
            now.subtract(const Duration(minutes: 14))),
        msg('c1_m3', 'conv1', 'c1', false, '晚上一起吃饭吗？公司附近新开了家湘菜',
            now.subtract(const Duration(minutes: 12))),
      ],
      'conv4': [
        msg('c4_m1', 'conv4', 'c4', false, '阿伟: Flutter 3.47 的发布笔记有人看了吗',
            now.subtract(const Duration(minutes: 45))),
      ],
      'conv2': [
        msg('c2_m1', 'conv2', 'c2', false, '方案我发你邮箱了，明天早上对一下',
            now.subtract(const Duration(hours: 2))),
      ],
    };
  }

  /// 朋友圈种子数据
  static List<Moment> seedMoments() {
    final now = DateTime.now();
    Contact byId(String id) => contacts.firstWhere((c) => c.id == id);

    return [
      Moment(
        author: byId('c1'),
        text: '周末探店成功，这家湘菜真的绝了，剁椒鱼头必须点！',
        images: const ['assets/moments/p1.jpg', 'assets/moments/p2.jpg'],
        createdAt: now.subtract(const Duration(minutes: 40)),
        likes: const ['王哥', '韩梅梅'],
        comments: const ['韩梅梅: 求地址！'],
      ),
      Moment(
        author: byId('c6'),
        text: '今天也是元气满满的一天 ☀️',
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      Moment(
        author: byId('c8'),
        text: '版本终于发了，连续加班两周，周末好好睡一觉',
        images: const ['assets/moments/p3.jpg'],
        createdAt: now.subtract(const Duration(hours: 5)),
        likes: const ['林晓雨', '赵磊', '陈晓'],
      ),
      Moment(
        author: byId('c14'),
        images: const [
          'assets/moments/p4.jpg',
          'assets/moments/p5.jpg',
          'assets/moments/p6.jpg',
        ],
        createdAt: now.subtract(const Duration(days: 1, hours: 3)),
        comments: const ['周芷若: 拍得不错'],
      ),
      Moment(
        author: me,
        text: '新项目上线倒计时，加油',
        createdAt: now.subtract(const Duration(days: 2)),
        likes: const ['林晓雨'],
      ),
    ];
  }
}
