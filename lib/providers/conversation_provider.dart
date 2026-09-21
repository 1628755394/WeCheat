import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/conversation.dart';
import '../repositories/conversation_repository.dart';

final conversationRepositoryProvider =
    Provider<ConversationRepository>((ref) => ConversationRepository());

/// 会话列表：从 Hive 加载，提供刷新与已读操作
class ConversationList extends AsyncNotifier<List<Conversation>> {
  ConversationRepository get _repo =>
      ref.read(conversationRepositoryProvider);

  @override
  Future<List<Conversation>> build() async {
    await _repo.init();
    return _repo.loadAll();
  }

  Future<void> refresh() async {
    state = AsyncData(_repo.loadAll());
  }

  /// 收发消息后更新列表里的摘要与时间，并重新排序
  Future<void> updateLastMessage(
      String conversationId, String text, DateTime time) async {
    final list = state.value ?? [];
    final index = list.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;

    final updated =
        list[index].copyWith(lastMessage: text, lastMessageTime: time);
    await _repo.save(updated);
    state = AsyncData(_repo.loadAll());
  }

  /// 切换置顶 / 免打扰
  Future<void> setFlag(String conversationId,
      {bool? pinned, bool? muted}) async {
    final list = state.value ?? [];
    final index = list.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;

    final updated = list[index].copyWith(pinned: pinned, muted: muted);
    await _repo.save(updated);
    state = AsyncData(_repo.loadAll());
  }

  /// 进入会话后清零未读数
  Future<void> markRead(String conversationId) async {
    final list = state.value ?? [];
    final index = list.indexWhere((c) => c.id == conversationId);
    if (index < 0 || list[index].unreadCount == 0) return;

    final updated = list[index].copyWith(unreadCount: 0);
    await _repo.save(updated);
    final next = [...list]..[index] = updated;
    state = AsyncData(next);
  }
}

final conversationListProvider =
    AsyncNotifierProvider<ConversationList, List<Conversation>>(
        ConversationList.new);

/// 底部 Tab 未读总数（免打扰会话只显示红点不计数？微信仍计入总角标，这里按计数统计）
final totalUnreadProvider = Provider<int>((ref) {
  final list = ref.watch(conversationListProvider).value;
  if (list == null) return 0;
  return list.fold(0, (sum, c) => sum + c.unreadCount);
});
