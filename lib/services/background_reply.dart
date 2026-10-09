import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message.dart';
import '../providers/chat_provider.dart';
import '../providers/conversation_provider.dart';

/// 后台巡检：每 30 秒扫一遍 AI 会话，发现有我没回的未回复消息就补一条
/// 不依赖聊天页是否打开——回复照常落库，未读角标 +1
class BackgroundReplyService {
  final Ref _ref;
  Timer? _timer;
  bool _ticking = false;

  BackgroundReplyService(this._ref);

  void start() {
    _timer ??=
        Timer.periodic(const Duration(seconds: 30), (_) => _tick());
  }

  Future<void> _tick() async {
    if (_ticking) return;
    _ticking = true;
    try {
      await _ref.read(conversationListProvider.future);
      final convs = _ref.read(conversationListProvider).value ?? [];
      final repo = _ref.read(messageRepositoryProvider);
      await repo.init();
      for (final conv in convs) {
        final hasAi = conv.contact.isGroup
            ? conv.members.any((m) => m.isAi)
            : conv.contact.isAi;
        if (!hasAi) continue;
        if (ChatMessages.generatingIds.contains(conv.id)) continue;
        final last = repo.loadByConversation(conv.id).lastOrNull;
        if (last == null ||
            !last.isMe ||
            last.recalled ||
            last.type == MessageType.system) {
          continue;
        }
        // 刚发的消息先等正常回复链路跑一会儿
        if (DateTime.now().difference(last.createdAt).inSeconds < 20) {
          continue;
        }
        await _chase(conv.id);
      }
    } catch (_) {
      // 巡检失败静默，下一轮再来
    } finally {
      _ticking = false;
    }
  }

  /// 让该会话的 chat provider 活起来并补回复；build() 里的主动问候会先兜底
  Future<void> _chase(String conversationId) async {
    final sub =
        _ref.listen(chatMessagesProvider(conversationId), (_, _) {});
    try {
      await _ref.read(chatMessagesProvider(conversationId).future);
      await _ref
          .read(chatMessagesProvider(conversationId).notifier)
          .chaseReply();
    } finally {
      sub.close();
    }
  }
}

final backgroundReplyServiceProvider =
    Provider<BackgroundReplyService>((ref) {
  final svc = BackgroundReplyService(ref)..start();
  ref.onDispose(() => svc._timer?.cancel());
  return svc;
});
