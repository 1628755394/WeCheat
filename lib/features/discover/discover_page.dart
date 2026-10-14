import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../repositories/ai_characters.dart';
import 'character_gallery_widgets.dart';

class DiscoverPage extends StatelessWidget {
  const DiscoverPage({super.key});

  static const _groups = [
    ('日常', [(Icons.filter_vintage, Color(0xFF3D8BFD), '朋友圈', '/moments')]),
    (
      '互动',
      [
        (Icons.qr_code_scanner, Color(0xFF3D8BFD), '扫一扫', '/scan'),
        (Icons.vibration, Color(0xFF3D8BFD), '摇一摇', '/discover/shake'),
      ],
    ),
    (
      '更多',
      [
        (Icons.visibility_outlined, Color(0xFFFA9D3B), '看一看', '/discover/look'),
        (Icons.search, Color(0xFFFA5151), '搜一搜', '/discover/search'),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 960),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
            children: [
              const Text(
                '发现',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 26,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              const Text(
                '认识新朋友，也看看他们的日常。',
                style: TextStyle(color: Color(0xFF78817B), fontSize: 13),
              ),
              const SizedBox(height: 28),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '角色广场',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => context.push('/discover/cards'),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('查看全部', style: TextStyle(fontSize: 12)),
                        SizedBox(width: 4),
                        Icon(Icons.arrow_forward_rounded, size: 15),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              const Text(
                '挑一位角色，开启今天的对话',
                style: TextStyle(color: Color(0xFF78817B), fontSize: 12),
              ),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) => CharacterGalleryGrid(
                  characters: AiCharacters.all
                      .where((c) =>
                          !AiCharacters.deletedFriends().contains(c.contact.id))
                      .take(constraints.maxWidth >= 600 ? 2 : 1)
                      .toList(),
                ),
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 24),
              LayoutBuilder(
                builder: (context, constraints) {
                  final columns = constraints.maxWidth >= 700 ? 3 : 1;
                  final width =
                      (constraints.maxWidth - (columns - 1) * 20) / columns;
                  return Wrap(
                    spacing: 20,
                    runSpacing: 20,
                    children: [
                      for (final group in _groups)
                        SizedBox(
                          width: width,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                group.$1,
                                style: const TextStyle(
                                  color: Color(0xFF78817B),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              for (final item in group.$2)
                                Material(
                                  color: Colors.white,
                                  child: ListTile(
                                    contentPadding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                    ),
                                    minTileHeight: 56,
                                    leading: Icon(
                                      item.$1,
                                      color: item.$2,
                                      size: 23,
                                    ),
                                    title: Text(
                                      item.$3,
                                      style: const TextStyle(
                                        fontSize: 14,
                                        color: AppColors.ink,
                                      ),
                                    ),
                                    trailing: const Icon(
                                      Icons.chevron_right_rounded,
                                      color: Color(0xFFA2AAA5),
                                      size: 18,
                                    ),
                                    onTap: () => context.push(item.$4),
                                  ),
                                ),
                            ],
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
