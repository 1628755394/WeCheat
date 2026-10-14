import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:forui/forui.dart' show FTile, FTileGroup;

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/app_visual.dart';
import '../../providers/user_provider.dart';

/// 我的页面：个人信息卡片 + 菜单
class MinePage extends ConsumerWidget {
  const MinePage({super.key});

  static const _menus = [
    (Icons.star_outline, Color(0xFFFA9D3B), '收藏', '/favorites'),
    (Icons.photo_library_outlined, Color(0xFF3D8BFD), '朋友圈', '/moments'),
    (Icons.emoji_emotions_outlined, Color(0xFFFA9D3B), '表情', '/emoji'),
    (Icons.settings_outlined, Color(0xFF3D8BFD), '设置', '/settings'),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: ListView(
        padding: const EdgeInsets.only(bottom: 28),
        children: [
          const AppPageHeading(title: '我', subtitle: '你的个人空间'),
          // 个人信息卡片：点击进个人信息页
          AppPanel(
            child: InkWell(
              onTap: () => context.push('/profile'),
              child: Container(
                color: Colors.white,
                padding: const EdgeInsets.all(18),
                child: Row(
                  children: [
                    AppAvatar(contact: me, size: 66),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            me.name,
                            style: const TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '微信号：${me.wechatId}',
                            style: const TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Icon(
                      Icons.qr_code_2,
                      size: 20,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
          const AppSectionLabel('我的收藏'),
          AppPanel(child: _MenuSection(menus: [_menus[0]])),
          const AppSectionLabel('更多服务'),
          AppPanel(child: _MenuSection(menus: _menus.sublist(1))),
        ],
      ),
    );
  }
}

class _MenuSection extends StatelessWidget {
  final List<(IconData, Color, String, String)> menus;

  const _MenuSection({required this.menus});

  @override
  Widget build(BuildContext context) {
    return FTileGroup(
      children: [
        for (var i = 0; i < menus.length; i++)
          FTile(
            prefix: AppIconBadge(icon: menus[i].$1, color: menus[i].$2),
            title: Text(menus[i].$3),
            suffix: const Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: AppColors.textSecondary,
            ),
            onPress: menus[i].$4.isEmpty
                ? null
                : () => context.push(menus[i].$4),
          ),
      ],
    );
  }
}
