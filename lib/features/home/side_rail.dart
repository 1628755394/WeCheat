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
      width: 60,
      color: AppColors.navBarBg,
      child: Column(
        children: [
          const SizedBox(height: 20),
          GestureDetector(
            onTap: () => context.push('/profile'),
            child: AppAvatar(contact: me, size: 38),
          ),
          const SizedBox(height: 28),
          for (var i = 0; i < _tabs.length; i++)
            _RailIcon(
              icon: selectedIndex == i ? _tabs[i].$2 : _tabs[i].$1,
              label: _tabs[i].$3,
              selected: selectedIndex == i,
              badge: i == 0 ? unread : 0,
              onTap: () => onSelect(i),
            ),
          const Spacer(),
          PopupMenuButton<String>(
            icon: const Icon(Icons.menu, color: Colors.black54),
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
          const SizedBox(height: 16),
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
    final color = selected ? AppColors.primary : Colors.black54;
    final iconWidget = Icon(icon, color: color, size: 26);
    return Tooltip(
      message: label,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 60,
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
    );
  }
}
