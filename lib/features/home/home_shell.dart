import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../providers/conversation_provider.dart';

/// 底部 Tab 骨架：微信 / 通讯录 / 发现 / 我
/// StatefulNavigationShell 保证各 Tab 页面状态（滚动位置等）不丢失
class HomeShell extends ConsumerWidget {
  final StatefulNavigationShell navigationShell;

  const HomeShell({super.key, required this.navigationShell});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(totalUnreadProvider);

    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColors.divider, width: 0.5)),
        ),
        child: BottomNavigationBar(
          currentIndex: navigationShell.currentIndex,
          onTap: (index) => navigationShell.goBranch(
            index,
            // 重复点击当前 Tab 回到该分支初始页面
            initialLocation: index == navigationShell.currentIndex,
          ),
          type: BottomNavigationBarType.fixed,
          backgroundColor: AppColors.navBarBg,
          elevation: 0,
          selectedItemColor: AppColors.primary,
          unselectedItemColor: Colors.black87,
          selectedFontSize: 11,
          unselectedFontSize: 11,
          items: [
            BottomNavigationBarItem(
              icon: _BadgeIcon(
                  icon: Icons.chat_bubble_outline, count: unread),
              activeIcon: _BadgeIcon(
                  icon: Icons.chat_bubble, count: unread),
              label: '微信',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.contacts_outlined),
              activeIcon: Icon(Icons.contacts),
              label: '通讯录',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.explore_outlined),
              activeIcon: Icon(Icons.explore),
              label: '发现',
            ),
            const BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: '我',
            ),
          ],
        ),
      ),
    );
  }
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
