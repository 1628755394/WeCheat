import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../providers/conversation_provider.dart';
import '../../services/background_reply.dart';
import 'side_rail.dart';

/// 骨架：微信 / 通讯录 / 发现 / 我
/// 窄屏 = 底部 Tab；宽屏（≥760）= PC 版左侧图标栏 + 内容区
/// StatefulNavigationShell 保证各 Tab 页面状态（滚动位置等）不丢失
class HomeShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const HomeShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(totalUnreadProvider);
    // 后台巡检：每 30 秒检查有没有 AI 没回复的消息，不在聊天页也照回
    ref.watch(backgroundReplyServiceProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= AppDimens.desktopBreakpoint) {
          return Scaffold(
            body: Row(
              children: [
                SideRail(
                  selectedIndex: navigationShell.currentIndex,
                  onSelect: (index) => navigationShell.goBranch(
                    index,
                    initialLocation: index == navigationShell.currentIndex,
                  ),
                ),
                const VerticalDivider(width: 0.5, color: AppColors.divider),
                Expanded(child: navigationShell),
              ],
            ),
          );
        }

        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: SafeArea(
            top: false,
            child: Container(
              height: 58,
              decoration: const BoxDecoration(
                color: AppColors.navBarBg,
                border: Border(
                  top: BorderSide(color: AppColors.divider, width: 0.5),
                ),
              ),
              child: Row(
                children: [
                  _MobileTab(
                    icon: _BadgeIcon(
                      icon: navigationShell.currentIndex == 0
                          ? Icons.chat_bubble
                          : Icons.chat_bubble_outline,
                      count: unread,
                    ),
                    label: '微信',
                    selected: navigationShell.currentIndex == 0,
                    onTap: () => navigationShell.goBranch(0,
                        initialLocation: navigationShell.currentIndex == 0),
                  ),
                  _MobileTab(
                    icon: const Icon(Icons.contacts_outlined),
                    label: '通讯录',
                    selected: navigationShell.currentIndex == 1,
                    onTap: () => navigationShell.goBranch(1,
                        initialLocation: navigationShell.currentIndex == 1),
                  ),
                  _MobileTab(
                    icon: const Icon(Icons.explore_outlined),
                    label: '发现',
                    selected: navigationShell.currentIndex == 2,
                    onTap: () => navigationShell.goBranch(2,
                        initialLocation: navigationShell.currentIndex == 2),
                  ),
                  _MobileTab(
                    icon: const Icon(Icons.person_outline),
                    label: '我',
                    selected: navigationShell.currentIndex == 3,
                    onTap: () => navigationShell.goBranch(3,
                        initialLocation: navigationShell.currentIndex == 3),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _MobileTab extends StatelessWidget {
  const _MobileTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final Widget icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Expanded(
    child: InkWell(
      onTap: onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconTheme(
            data: IconThemeData(
              color: selected ? AppColors.primary : Colors.black87,
              size: 27,
            ),
            child: icon,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: selected ? AppColors.primary : Colors.black87,
            ),
          ),
        ],
      ),
    ),
  );
}

class _BadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const _BadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return Icon(icon);
    return Badge.count(
      count: count,
      maxCount: 99,
      backgroundColor: AppColors.badge,
      textColor: Colors.white,
      child: Icon(icon),
    );
  }
}
