import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/contact.dart';
import '../models/conversation.dart';
import '../repositories/conversation_repository.dart';
import 'contact_override_provider.dart';

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

  /// 新建会话（添加 AI 好友等），持久化后刷新列表，返回新会话 id
  Future<String> addConversation(Conversation conversation) async {
    await _repo.save(conversation);
    state = AsyncData(_repo.loadAll());
    return conversation.id;
  }

  Future<void> deleteFriend(Conversation conversation) async {
    await _repo.deleteFriend(conversation);
    state = AsyncData(_repo.loadAll());
  }

  /// 更新群成员（群聊加人/减人），并按成员名重新生成默认群名
  Future<void> updateMembers(
      String conversationId, List<Contact> members) async {
    final list = state.value ?? [];
    final index = list.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;

    final conv = list[index];
    final autoName =
        members.take(3).map((m) => m.displayName).join('、');
    final updated = conv.copyWith(
      members: members,
      contact: autoName.isEmpty
          ? conv.contact
          : conv.contact.copyWith(name: autoName),
    );
    await _repo.save(updated);
    state = AsyncData(_repo.loadAll());
  }

  /// 收发消息后更新列表里的摘要与时间，并重新排序
  /// [bumpUnread] 为 true 时未读 +1（AI 消息到达且该会话当前未打开）
  Future<void> updateLastMessage(
      String conversationId, String text, DateTime time,
      {bool bumpUnread = false}) async {
    final list = state.value ?? [];
    final index = list.indexWhere((c) => c.id == conversationId);
    if (index < 0) return;

    final updated = list[index].copyWith(
      lastMessage: text,
      lastMessageTime: time,
      unreadCount: bumpUnread ? list[index].unreadCount + 1 : null,
    );
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

class ChatBackground {
  final int? colorValue;
  final Uint8List? imageBytes;

  const ChatBackground({this.colorValue, this.imageBytes});

  Map<String, dynamic> toMap() => {
    'colorValue': colorValue,
    'imageBytes': imageBytes,
  };

  factory ChatBackground.fromMap(Map map) => ChatBackground(
    colorValue: map['colorValue'] as int?,
    imageBytes: _chatBackgroundBytes(map['imageBytes']),
  );

  static Uint8List? _chatBackgroundBytes(dynamic raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    return Uint8List.fromList((raw as List).cast<int>());
  }
}

class ChatBackgroundNotifier extends Notifier<ChatBackground> {
  ChatBackgroundNotifier(this.conversationId);

  final String conversationId;
  static const _boxName = 'chat_backgrounds';

  Box? _box;
  Future<void>? _loading;

  @override
  ChatBackground build() {
    _loading ??= _load();
    return const ChatBackground();
  }

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _box = await Hive.openBox(_boxName);
    final raw = _box!.get(conversationId);
    if (raw is Map) state = ChatBackground.fromMap(raw);
  }

  Future<void> _save(ChatBackground background) async {
    await ensureLoaded();
    state = background;
    if (background.colorValue == null && background.imageBytes == null) {
      await _box!.delete(conversationId);
    } else {
      await _box!.put(conversationId, background.toMap());
    }
  }

  Future<void> setColor(int value) =>
      _save(ChatBackground(colorValue: value));

  Future<void> setImage(Uint8List bytes) =>
      _save(ChatBackground(imageBytes: bytes));

  Future<void> clear() => _save(const ChatBackground());
}

final chatBackgroundProvider =
    NotifierProvider.family<ChatBackgroundNotifier, ChatBackground, String>(
      ChatBackgroundNotifier.new,
    );

final conversationListProvider =
    AsyncNotifierProvider<ConversationList, List<Conversation>>(
        ConversationList.new);

/// 展示层：会话列表 + 联系人覆盖层合并（自定义头像/备注），UI 一律读这里
final resolvedConversationListProvider =
    Provider<AsyncValue<List<Conversation>>>((ref) {
  final overrides = ref.watch(contactOverridesProvider);
  return ref.watch(conversationListProvider).whenData((list) => [
        for (final c in list)
          c.copyWith(
            contact: resolveContact(overrides, c.contact),
            members: [
              for (final m in c.members) resolveContact(overrides, m),
            ],
          ),
      ]);
});

/// 底部 Tab 未读总数（免打扰会话只显示红点不计数？微信仍计入总角标，这里按计数统计）
final totalUnreadProvider = Provider<int>((ref) {
  final list = ref.watch(conversationListProvider).value;
  if (list == null) return 0;
  return list.fold(0, (sum, c) => sum + c.unreadCount);
});
