import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../repositories/mock_data.dart';

/// 我的页面：个人信息卡片 + 菜单
class MinePage extends StatelessWidget {
  const MinePage({super.key});

  static const _me = MockData.me;

  static const _menus = [
    (Icons.payment, Color(0xFF07C160), '服务', ''),
    (Icons.star_outline, Color(0xFFFA9D3B), '收藏', ''),
    (Icons.photo_library_outlined, Color(0xFF3D8BFD), '朋友圈', '/moments'),
    (Icons.credit_card, Color(0xFF3D8BFD), '卡包', ''),
    (Icons.emoji_emotions_outlined, Color(0xFFFA9D3B), '表情', ''),
    (Icons.settings_outlined, Color(0xFF3D8BFD), '设置', ''),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(backgroundColor: Colors.white),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // 个人信息卡片
          Container(
            color: Colors.white,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            child: Row(
              children: [
                AppAvatar(contact: _me, size: 62),
                const SizedBox(width: 16),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Devin',
                        style: TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w600),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '微信号：wecheat_dev',
                        style: TextStyle(
                            fontSize: 14, color: AppColors.textSecondary),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.qr_code_2,
                    size: 20, color: AppColors.textSecondary),
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right,
                    color: AppColors.textSecondary),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _MenuSection(menus: [_menus[0]]),
          const SizedBox(height: 8),
          _MenuSection(menus: _menus.sublist(1, 5)),
          const SizedBox(height: 8),
          _MenuSection(menus: [_menus[5]]),
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
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          for (var i = 0; i < menus.length; i++) ...[
            if (i > 0) const Divider(indent: 56),
            ListTile(
              leading: Icon(menus[i].$1, color: menus[i].$2, size: 26),
              title: Text(menus[i].$3, style: const TextStyle(fontSize: 16)),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
              onTap: menus[i].$4.isEmpty
                  ? null
                  : () => context.push(menus[i].$4),
            ),
          ],
        ],
      ),
    );
  }
}
