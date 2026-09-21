import 'package:hive_flutter/hive_flutter.dart';

import '../models/message.dart';
import 'mock_data.dart';

/// 消息仓库：Hive 持久化聊天记录，key 为消息 id
class MessageRepository {
  static const _boxName = 'messages';

  Box? _box;

  Future<void> init() async {
    if (_box != null) return;
    _box = await Hive.openBox(_boxName);
    if (_box!.isEmpty) {
      for (final entry in MockData.seedMessages().entries) {
        await _box!.putAll({for (final m in entry.value) m.id: m.toMap()});
      }
    }
  }

  /// 某会话的全部消息，按时间升序
  List<Message> loadByConversation(String conversationId) {
    final list = _box!.values
        .map((raw) => Message.fromMap(raw as Map))
        .where((m) => m.conversationId == conversationId)
        .toList();
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> save(Message message) =>
      _box!.put(message.id, message.toMap());

  /// 清空某会话的全部消息
  Future<void> clearConversation(String conversationId) async {
    final keys = _box!.keys.where((k) {
      final m = Message.fromMap(_box!.get(k) as Map);
      return m.conversationId == conversationId;
    }).toList();
    await _box!.deleteAll(keys);
  }
}
