import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../models/conversation.dart';
import '../../providers/conversation_provider.dart';
import 'widgets/conversation_tile.dart';

/// 微信页：会话列表
class ConversationPage extends ConsumerWidget {
  const ConversationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(resolvedConversationListProvider);
    final unread = ref.watch(totalUnreadProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(unread > 0 ? '微信($unread)' : '微信'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: '发起群聊',
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        children: [
          const _SearchBar(),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () =>
                  ref.read(conversationListProvider.notifier).refresh(),
              child: conversations.when(
                loading: () => const _ScrollablePlaceholder(
                    child: CircularProgressIndicator()),
                error: (e, _) =>
                    _ScrollablePlaceholder(child: Text('加载失败：$e')),
                data: (list) => list.isEmpty
                    ? const _ScrollablePlaceholder(child: Text('暂无会话'))
                    : _ConversationListView(list: list),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationListView extends ConsumerWidget {
  final List<Conversation> list;

  const _ConversationListView({required this.list});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView.separated(
      // 列表性能：懒加载，不一次性渲染全部 item
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(indent: 76),
      itemBuilder: (context, index) {
        final conversation = list[index];
        return ConversationTile(
          conversation: conversation,
          onTap: () {
            ref
                .read(conversationListProvider.notifier)
                .markRead(conversation.id);
            context.push('/chat/${conversation.id}');
          },
        );
      },
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      height: 36,
      decoration: BoxDecoration(
        color: AppColors.searchBg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search, size: 18, color: AppColors.textSecondary),
          SizedBox(width: 4),
          Text('搜索', style: TextStyle(fontSize: 14, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// 让 loading / 空态也可下拉触发 RefreshIndicator
class _ScrollablePlaceholder extends StatelessWidget {
  final Widget child;

  const _ScrollablePlaceholder({required this.child});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: constraints.maxHeight,
            child: Center(child: child),
          ),
        ],
      ),
    );
  }
}
