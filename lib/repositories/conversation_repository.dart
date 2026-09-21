import 'package:hive_flutter/hive_flutter.dart';

import '../models/conversation.dart';
import 'mock_data.dart';

/// 会话仓库：Hive 本地持久化 + Mock 数据种子
class ConversationRepository {
  static const _boxName = 'conversations';

  Box? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox(_boxName);
    if (_box!.isEmpty) {
      final seeds = MockData.seedConversations();
      await _box!.putAll({for (final c in seeds) c.id: c.toMap()});
    }
    // 老版本数据迁移：补种 AI 助手会话
    if (!_box!.containsKey('conv_ai')) {
      await _box!.put('conv_ai', MockData.aiConversation(DateTime.now()).toMap());
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

  Future<void> saveAll(Iterable<Conversation> conversations) => _box!.putAll(
        {for (final c in conversations) c.id: c.toMap()},
      );
}
