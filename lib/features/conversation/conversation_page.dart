import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
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

    return const Scaffold(body: ConversationListPane());
  }
}

/// 会话列表栏（PC 中栏 / 窄屏 body 共用）：顶部搜索 + 可选 + 菜单，下面会话列表
class ConversationListPane extends ConsumerWidget {
  /// 当前打开的会话 id（宽屏下高亮选中行）
  final String? selectedId;

  const ConversationListPane({super.key, this.selectedId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(resolvedConversationListProvider);
    final desktop =
        MediaQuery.sizeOf(context).width >= AppDimens.desktopBreakpoint;
    return ColoredBox(
      color: desktop ? AppColors.desktopList : Colors.white,
      child: Column(
        children: [
          if (desktop)
            const _DesktopListToolbar()
          else
            const _MobileListToolbar(),
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
  final bool dense;

  const ConversationAddButton({super.key, this.dense = false});

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

class _DesktopListToolbar extends StatelessWidget {
  const _DesktopListToolbar();

  @override
  Widget build(BuildContext context) => Container(
    height: 60,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: const BoxDecoration(
      color: AppColors.desktopList,
      border: Border(bottom: BorderSide(color: Color(0xFFD8D8D8), width: 0.5)),
    ),
    child: Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => context.push('/discover/search'),
            borderRadius: BorderRadius.circular(5),
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: AppColors.searchBg,
                borderRadius: BorderRadius.circular(5),
              ),
              child: const Row(
                children: [
                  SizedBox(width: 9),
                  Icon(Icons.search, size: 17, color: Color(0xFF777777)),
                  SizedBox(width: 6),
                  Text(
                    '搜索',
                    style: TextStyle(fontSize: 12, color: Color(0xFF777777)),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          height: 32,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.searchBg,
              borderRadius: BorderRadius.circular(5),
            ),
            child: const ConversationAddButton(dense: true),
          ),
        ),
      ],
    ),
  );
}

class _MobileListToolbar extends StatelessWidget {
  const _MobileListToolbar();

  @override
  Widget build(BuildContext context) => SafeArea(
    bottom: false,
    child: Container(
      height: 56,
      decoration: const BoxDecoration(
        color: AppColors.navBarBg,
        border: Border(
          bottom: BorderSide(color: AppColors.divider, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          const SizedBox(width: 48),
          const Expanded(
            child: Center(
              child: Text(
                '微信',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          IconButton(
            tooltip: '搜索',
            icon: const Icon(Icons.search, size: 27),
            onPressed: () => context.push('/discover/search'),
          ),
          const ConversationAddButton(),
          const SizedBox(width: 4),
        ],
      ),
    ),
  );
}

/// PC 布局下未选中会话时右侧的占位页
class _EmptyChatPane extends StatelessWidget {
  const _EmptyChatPane();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.white,
      child: Center(
        child: Icon(Icons.chat_bubble_outline, size: 72, color: Colors.black12),
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
      padding: EdgeInsets.zero,
      // 列表性能：懒加载，不一次性渲染全部 item
      itemCount: list.length,
      separatorBuilder: (_, _) => Divider(
        height: 0.5,
        thickness: 0.5,
        indent: wide ? 66 : 72,
        color: AppColors.divider,
      ),
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
