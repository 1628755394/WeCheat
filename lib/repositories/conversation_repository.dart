import 'package:hive_flutter/hive_flutter.dart';

import '../models/conversation.dart';
import 'ai_characters.dart';
import 'mock_data.dart';

/// 会话仓库：Hive 本地持久化 + Mock 数据种子
class ConversationRepository {
  static const _boxName = 'conversations';

  /// 旧版 Mock 真人会话 id，升级时连同消息一起清掉
  static const _legacyIds = [
    'conv1', 'conv2', 'conv3', 'conv4', 'conv5', 'conv6',
    'conv7', 'conv8', 'conv9', 'conv10', 'conv11', 'conv12',
  ];

  Box? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox(_boxName);
    if (_box!.isEmpty) {
      final seeds = MockData.seedConversations();
      await _box!.putAll({for (final c in seeds) c.id: c.toMap()});
    }
    // 清理旧版 Mock 假人会话（AI 会话与用户自建数据保留）
    await _box!.deleteAll(_legacyIds.where(_box!.containsKey));
    final msgBox = await Hive.openBox('messages');
    final deadKeys = msgBox.keys.where((k) {
      final raw = msgBox.get(k) as Map;
      return _legacyIds.contains(raw['conversationId']);
    }).toList();
    await msgBox.deleteAll(deadKeys);
    // 补种 AI 角色单聊 + 全员群 + 各角色资料（覆盖人设类内容，保留用户改的模型/音色/记忆）
    await AiCharacters.seed(_box!, forceProfiles: true);
    // 联系人资料以 MockData 为准：同步新增字段（头像图、AI 标记等）
    for (final key in _box!.keys.toList()) {
      final conv = Conversation.fromMap(_box!.get(key) as Map);
      final fresh = MockData.contacts
          .where((c) => c.id == conv.contact.id)
          .firstOrNull;
      if (fresh == null) continue;
      if (fresh.avatarAsset != conv.contact.avatarAsset ||
          fresh.isAi != conv.contact.isAi ||
          fresh.name != conv.contact.name) {
        await _box!.put(key, conv.copyWith(contact: fresh).toMap());
      }
      // 群成员资料同样按 MockData 同步（头像等）
      var membersChanged = false;
      final members = [
        for (final m in conv.members)
          MockData.contacts.where((c) => c.id == m.id).firstOrNull ?? m,
      ];
      for (var i = 0; i < members.length; i++) {
        if (members[i].avatarAsset != conv.members[i].avatarAsset) {
          membersChanged = true;
        }
      }
      if (membersChanged) {
        await _box!.put(key, conv.copyWith(members: members).toMap());
      }
    }
  }

  /// 读取全部会话，置顶优先，其余按最新消息时间倒序
  List<Conversation> loadAll() {
    final list = _box!.values
        .map((raw) => Conversation.fromMap(raw as Map))
        .toList();
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.lastMessageTime.compareTo(a.lastMessageTime);
    });
    return list;
  }

  Future<void> save(Conversation conversation) =>
      _box!.put(conversation.id, conversation.toMap());

  Future<void> deleteFriend(Conversation conversation) =>
      AiCharacters.deleteFriend(conversation);

  Future<void> saveAll(Iterable<Conversation> conversations) => _box!.putAll(
        {for (final c in conversations) c.id: c.toMap()},
      );
}
