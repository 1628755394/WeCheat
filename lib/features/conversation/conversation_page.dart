import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/output_mode_button.dart';
import '../../models/conversation.dart';
import '../../providers/conversation_provider.dart';
import '../contact/add_ai_friend_page.dart';
import 'group_create_page.dart';
import 'widgets/conversation_tile.dart';

/// 微信页：窄屏单栏（AppBar + 列表）；宽屏 PC 布局（列表栏 + 右侧空占位）
class ConversationPage extends ConsumerWidget {
  const ConversationPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(totalUnreadProvider);
    final wide =
        MediaQuery.sizeOf(context).width >= AppDimens.desktopBreakpoint;

    if (wide) {
      return const Scaffold(
        body: Row(
          children: [
            SizedBox(
              width: AppDimens.listPaneWidth,
              child: ConversationListPane(),
            ),
            VerticalDivider(width: 0.5, color: AppColors.divider),
            Expanded(child: _EmptyChatPane()),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(unread > 0 ? '微信($unread)' : '微信'),
        actions: const [OutputModeButton(), ConversationAddButton()],
      ),
      // 窄屏的 + 菜单在 AppBar，栏内不重复显示
      body: const ConversationListPane(showAddButton: false),
    );
  }
}

/// 会话列表栏（PC 中栏 / 窄屏 body 共用）：顶部搜索 + 可选 + 菜单，下面会话列表
class ConversationListPane extends ConsumerWidget {
  /// 当前打开的会话 id（宽屏下高亮选中行）
  final String? selectedId;

  /// 栏内是否显示 + 菜单按钮（窄屏时按钮在 AppBar 上）
  final bool showAddButton;

  const ConversationListPane({
    super.key,
    this.selectedId,
    this.showAddButton = true,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(resolvedConversationListProvider);

    return ColoredBox(
      color: Colors.white,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 2),
            child: Row(
              children: [
                const Expanded(child: _SearchBar()),
                if (showAddButton) const ConversationAddButton(),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              color: AppColors.primary,
              onRefresh: () =>
                  ref.read(conversationListProvider.notifier).refresh(),
              child: conversations.when(
                loading: () => const _ScrollablePlaceholder(
                  child: CircularProgressIndicator(),
                ),
                error: (e, _) => _ScrollablePlaceholder(child: Text('加载失败：$e')),
                data: (list) => list.isEmpty
                    ? const _ScrollablePlaceholder(child: Text('暂无会话'))
                    : ConversationListView(list: list, selectedId: selectedId),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 右上角 + 菜单：发起群聊 / 添加朋友 / 扫一扫 / 收付款（AppBar 与 PC 栏头共用）
class ConversationAddButton extends StatelessWidget {
  const ConversationAddButton({super.key});

  static PopupMenuItem<String> _menuItem(
    String value,
    IconData icon,
    String label,
  ) {
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 22),
          const SizedBox(width: 12),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }

  static void _onMenuSelected(BuildContext context, String value) {
    if (value == 'add') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const AddAiFriendPage()));
      return;
    }
    if (value == 'group') {
      Navigator.of(context)
          .push(MaterialPageRoute(builder: (_) => const GroupCreatePage()));
      return;
    }
    if (value == 'scan') {
      context.push('/scan');
      return;
    }
    if (value == 'pay') {
      context.push('/pay');
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.add_circle_outline),
      tooltip: '更多',
      color: const Color(0xFF2E2E2E),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      offset: const Offset(0, 8),
      onSelected: (value) => _onMenuSelected(context, value),
      itemBuilder: (context) => [
        _menuItem('group', Icons.chat_bubble_outline, '发起群聊'),
        _menuItem('add', Icons.person_add_alt_1, '添加朋友'),
        _menuItem('scan', Icons.qr_code_scanner, '扫一扫'),
        _menuItem('pay', Icons.payments_outlined, '收付款'),
      ],
    );
  }
}

/// PC 布局下未选中会话时右侧的占位页
class _EmptyChatPane extends StatelessWidget {
  const _EmptyChatPane();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.chatBg,
      appBar: AppBar(actions: const [OutputModeButton()]),
      body: const Center(
        child: Icon(Icons.chat_bubble_outline, size: 80, color: Colors.black12),
      ),
    );
  }
}

class ConversationListView extends ConsumerWidget {
  final List<Conversation> list;
  final String? selectedId;

  const ConversationListView({super.key, required this.list, this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wide =
        MediaQuery.sizeOf(context).width >= AppDimens.desktopBreakpoint;
    return ListView.separated(
      // 列表性能：懒加载，不一次性渲染全部 item
      itemCount: list.length,
      separatorBuilder: (_, _) => const Divider(indent: 76, height: 1),
      itemBuilder: (context, index) {
        final conversation = list[index];
        return ConversationTile(
          conversation: conversation,
          selected: conversation.id == selectedId,
          onTap: () {
            ref
                .read(conversationListProvider.notifier)
                .markRead(conversation.id);
            // 宽屏切换会话不换路由栈，直接 go（列表常驻，无返回箭头）
            if (wide) {
              context.go('/chat/${conversation.id}');
            } else {
              context.push('/chat/${conversation.id}');
            }
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
          Text(
            '搜索',
            style: TextStyle(fontSize: 14, color: AppColors.textSecondary),
          ),
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
