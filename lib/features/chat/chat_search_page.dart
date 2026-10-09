import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/utils/time_utils.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';

/// 查找聊天记录：全文检索当前会话的消息
class ChatSearchPage extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatSearchPage({super.key, required this.conversationId});

  @override
  ConsumerState<ChatSearchPage> createState() => _ChatSearchPageState();
}

class _ChatSearchPageState extends ConsumerState<ChatSearchPage> {
  final _controller = TextEditingController();
  List<Message> _all = [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = ref.read(messageRepositoryProvider);
    await repo.init();
    if (mounted) {
      setState(() => _all = repo.loadByConversation(widget.conversationId));
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final results = _query.isEmpty
        ? const <Message>[]
        : [
            for (final m in _all)
              if (!m.recalled &&
                  m.type == MessageType.text &&
                  m.content.contains(_query))
                m,
          ];

    final conv = ref
        .watch(resolvedConversationListProvider)
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;

    String senderName(Message m) {
      if (m.isMe) return '我';
      if (conv == null) return '对方';
      if (m.senderId == conv.contact.id) return conv.contact.displayName;
      for (final member in conv.members) {
        if (member.id == m.senderId) return member.displayName;
      }
      return conv.contact.displayName;
    }

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜索聊天记录',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _query = v.trim()),
        ),
      ),
      body: _query.isEmpty
          ? const Center(
              child: Text('输入关键词搜索',
                  style: TextStyle(color: AppColors.textSecondary)))
          : results.isEmpty
              ? const Center(
                  child: Text('无匹配结果',
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.separated(
                  itemCount: results.length,
                  separatorBuilder: (_, _) => const Divider(indent: 16),
                  itemBuilder: (context, i) {
                    final m = results[results.length - 1 - i];
                    return ListTile(
                      dense: true,
                      title: Text(
                        m.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 15),
                      ),
                      subtitle: Text(
                        '${senderName(m)} · ${TimeUtils.formatMessageGroupTime(m.createdAt)}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    );
                  },
                ),
    );
  }
}
