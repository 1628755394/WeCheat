import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/fake_qr.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/user_provider.dart';

/// 二维码名片：头像 + 昵称 + 伪二维码
class QrCardPage extends ConsumerWidget {
  const QrCardPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('二维码名片')),
      body: Center(
        child: Container(
          width: 300,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppColors.divider),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppAvatar(contact: me, size: 48),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        me.displayName,
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        me.region.isEmpty ? '' : me.region,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),
              FakeQr(seed: 'card-${me.wechatId}', size: 240),
              const SizedBox(height: 12),
              const Text(
                '扫一扫上面的二维码，加我为朋友',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 收藏：所有被标记为「重点记忆」的消息
class FavoritesPage extends ConsumerWidget {
  const FavoritesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 触发会话列表加载以拿发送者名
    final convs = ref.watch(resolvedConversationListProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('收藏')),
      body: FutureBuilder(
        future: ref
            .read(messageRepositoryProvider)
            .init()
            .then((_) => ref.read(messageRepositoryProvider).loadMemories()),
        builder: (context, snap) {
          final list = snap.data;
          if (list == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (list.isEmpty) {
            return const Center(
              child: Text(
                '还没有收藏\n聊天里长按消息 →「标记为记忆」即可收藏',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          String senderOf(m) {
            if (m.isMe) return '我';
            for (final c in convs ?? const []) {
              if (c.id == m.conversationId) {
                if (m.senderId == c.contact.id) {
                  return c.contact.displayName;
                }
                for (final member in c.members) {
                  if (member.id == m.senderId) return member.displayName;
                }
              }
            }
            return '对方';
          }

          return ListView.separated(
            itemCount: list.length,
            separatorBuilder: (_, _) => const Divider(indent: 16),
            itemBuilder: (context, i) {
              final m = list[i];
              return ListTile(
                leading: const Icon(Icons.star, color: Colors.amber),
                title: Text(
                  m.content,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text('${senderOf(m)} · ${_fmt(m.createdAt)}'),
                onTap: () =>
                    context.pushReplacement('/chat/${m.conversationId}'),
              );
            },
          );
        },
      ),
    );
  }

  static String _fmt(DateTime t) =>
      '${t.month}月${t.day}日 ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

/// 表情商店：emoji 宫格（点击可复制）
class EmojiStorePage extends StatelessWidget {
  const EmojiStorePage({super.key});

  static const _packs = [
    ('小黄脸', ['😀', '😂', '🥰', '😭', '😤', '🥺', '😎', '🤯']),
    ('手势', ['👍', '👏', '🙏', '💪', '🤝', '👌', '✌️', '🫶']),
    ('萌宠', ['🐱', '🐶', '🐰', '🐻', '🐼', '🦊', '🐸', '🐥']),
    ('食物', ['🍜', '🍰', '☕', '🧋', '🍺', '🍉', '🥟', '🍢']),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('表情')),
      body: ListView(
        children: [
          for (final (name, emojis) in _packs)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      for (final e in emojis)
                        Text(e, style: const TextStyle(fontSize: 34)),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
