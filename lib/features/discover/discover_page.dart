import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 发现页：静态菜单列表
class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  static const _groups = [
    [
      (Icons.filter_vintage, Color(0xFF3D8BFD), '朋友圈'),
    ],
    [
      (Icons.play_circle_outline, Color(0xFFFA9D3B), '视频号'),
      (Icons.live_tv, Color(0xFFFA5151), '直播'),
    ],
    [
      (Icons.qr_code_scanner, Color(0xFF3D8BFD), '扫一扫'),
      (Icons.vibration, Color(0xFF3D8BFD), '摇一摇'),
    ],
    [
      (Icons.visibility_outlined, Color(0xFFFA9D3B), '看一看'),
      (Icons.search, Color(0xFFFA5151), '搜一搜'),
    ],
    [
      (Icons.near_me, Color(0xFF3D8BFD), '附近'),
    ],
    [
      (Icons.shopping_bag_outlined, Color(0xFFFA9D3B), '购物'),
      (Icons.sports_esports_outlined, Color(0xFF8C6BAE), '游戏'),
    ],
    [
      (Icons.apps, Color(0xFF8C6BAE), '小程序'),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(
        title: const Text('发现'),
        backgroundColor: Colors.white,
      ),
      body: ListView.separated(
        itemCount: _groups.length,
        separatorBuilder: (_, _) => const SizedBox(height: 8),
        itemBuilder: (context, groupIndex) {
          final group = _groups[groupIndex];
          return Material(
            color: Colors.white,
            child: Column(
              children: [
                for (var i = 0; i < group.length; i++) ...[
                  if (i > 0) const Divider(indent: 56),
                  _MenuRow(
                      icon: group[i].$1, color: group[i].$2, label: group[i].$3),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;

  const _MenuRow({required this.icon, required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: color, size: 26),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      trailing:
          const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      onTap: () {},
    );
  }
}
