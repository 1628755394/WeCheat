import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/user_provider.dart';

/// PC 版左侧图标导航栏（仿微信 PC）：头像 + 功能图标（未读角标）+ 底部菜单
class SideRail extends ConsumerWidget {
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  const SideRail({
    super.key,
    required this.selectedIndex,
    required this.onSelect,
  });

  static const _tabs = [
    (Icons.chat_bubble_outline, Icons.chat_bubble, '微信'),
    (Icons.contacts_outlined, Icons.contacts, '通讯录'),
    (Icons.explore_outlined, Icons.explore, '发现'),
    (Icons.person_outline, Icons.person, '我'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(totalUnreadProvider);
    final me = ref.watch(currentUserProvider);

    return Container(
      width: 68,
      color: AppColors.desktopRail,
      child: Column(
        children: [
          const SizedBox(height: 22),
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: AppAvatar(contact: me, size: 40, radius: 6),
          ),
          const SizedBox(height: 24),
          for (var i = 0; i < _tabs.length; i++)
            _RailIcon(
              icon: selectedIndex == i ? _tabs[i].$2 : _tabs[i].$1,
              label: _tabs[i].$3,
              selected: selectedIndex == i,
              badge: i == 0 ? unread : 0,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          IconButton(
            icon: const Icon(Icons.phone_iphone_outlined, size: 22),
            tooltip: '个人资料',
            color: const Color(0xFF666666),
            onPressed: () => context.push('/profile'),
          ),
          const SizedBox(height: 12),
          PopupMenuButton<String>(
            icon: const Icon(
              Icons.menu_rounded,
              size: 23,
              color: Color(0xFF666666),
            ),
            tooltip: '更多',
            onSelected: (value) {
              if (value == 'settings' || value == 'about') {
                context.push('/settings');
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'settings', child: Text('设置')),
              PopupMenuItem(value: 'about', child: Text('关于')),
            ],
          ),
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _RailIcon extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final int badge;
  final VoidCallback onTap;

  const _RailIcon({
    required this.icon,
    required this.label,
    required this.selected,
    required this.badge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = selected ? AppColors.primary : const Color(0xFF666666);
    final iconWidget = Icon(icon, color: color, size: 24);
    return Tooltip(
      message: label,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(
              width: 68,
              height: 48,
              child: Center(
                child: badge > 0
                    ? Badge.count(
                        count: badge,
                        maxCount: 99,
                        backgroundColor: AppColors.badge,
                        textColor: Colors.white,
                        child: iconWidget,
                      )
                    : iconWidget,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
