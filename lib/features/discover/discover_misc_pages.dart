import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/moments_provider.dart';
import '../../repositories/ai_characters.dart';

/// 摇一摇：随机摇出一个 AI 角色
class ShakePage extends ConsumerStatefulWidget {
  const ShakePage({super.key});

  @override
  ConsumerState<ShakePage> createState() => _ShakePageState();
}

class _ShakePageState extends ConsumerState<ShakePage> {
  bool _shaking = false;
  String? _resultName;
  String? _resultConvId;

  Future<void> _shake() async {
    if (_shaking) return;
    setState(() {
      _shaking = true;
      _resultName = null;
    });
    await Future.delayed(const Duration(milliseconds: 900));
    final chars = AiCharacters.all
        .where((c) => !AiCharacters.deletedFriends().contains(c.contact.id))
        .toList();
    final c = chars[Random().nextInt(chars.length)];
    String? convId;
    for (final conv in ref.read(conversationListProvider).value ?? const []) {
      if (!conv.contact.isGroup && conv.contact.id == 'char_${c.id}') {
        convId = conv.id;
      }
    }
    if (mounted) {
      setState(() {
        _shaking = false;
        _resultName = c.name;
        _resultConvId = convId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('摇一摇')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedRotation(
              turns: _shaking ? 0.08 : 0,
              duration: const Duration(milliseconds: 300),
              child: const Icon(
                Icons.vibration,
                size: 90,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 24),
            if (_resultName == null)
              const Text(
                '摇一摇，认识新朋友',
                style: TextStyle(color: AppColors.textSecondary),
              )
            else
              Column(
                children: [
                  Text(
                    '摇到了 $_resultName！',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_resultConvId != null)
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                      ),
                      onPressed: () => context.push('/chat/$_resultConvId'),
                      child: const Text('开始聊天'),
                    ),
                ],
              ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              onPressed: _shake,
              icon: const Icon(Icons.refresh),
              label: Text(_shaking ? '摇一摇中…' : '开始摇'),
            ),
          ],
        ),
      ),
    );
  }
}

/// 看一看：Mock 文章流
class LookPage extends StatelessWidget {
  const LookPage({super.key});

  @override
  Widget build(BuildContext context) {
    const articles = [
      ('为什么年轻人开始流行"断亲"？', '三联生活周刊', '10w+'),
      ('AI 陪伴时代：我们还需要真人朋友吗', '新周刊', '5.6w'),
      ('上海咖啡店密度全国第一的背后', '城市数据团', '2.1w'),
      ('庭审心理学：律师如何读懂陪审团', '法治日报', '8.9w'),
      ('深夜食堂经济学', '有意思报告', '3.3w'),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('看一看')),
      body: ListView.separated(
        itemCount: articles.length,
        separatorBuilder: (_, _) => const Divider(indent: 16),
        itemBuilder: (context, i) => ListTile(
          title: Text(articles[i].$1, style: const TextStyle(fontSize: 16)),
          subtitle: Text(
            '${articles[i].$2} · 阅读 ${articles[i].$3}',
            style: const TextStyle(fontSize: 12),
          ),
          trailing: const Icon(
            Icons.chevron_right,
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// 搜一搜：全局搜索联系人 + 聊天记录 + 朋友圈文字
class GlobalSearchPage extends ConsumerStatefulWidget {
  const GlobalSearchPage({super.key});

  @override
  ConsumerState<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends ConsumerState<GlobalSearchPage> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final convs = ref.watch(resolvedConversationListProvider).value ?? const [];
    final moments = ref.watch(momentsProvider).value ?? const [];
    final repo = ref.watch(messageRepositoryProvider);

    final hitConvs = _q.isEmpty
        ? const []
        : [
            for (final c in convs)
              if (c.contact.displayName.contains(_q)) c,
          ];
    final hitMoments = _q.isEmpty
        ? const []
        : [
            for (final m in moments)
              if (m.text.contains(_q)) m,
          ];

    return Scaffold(
      appBar: AppBar(
        title: TextField(
          autofocus: true,
          decoration: const InputDecoration(
            hintText: '搜一搜',
            border: InputBorder.none,
          ),
          onChanged: (v) => setState(() => _q = v.trim()),
        ),
      ),
      body: FutureBuilder(
        future: repo.init().then((_) => repo),
        builder: (context, snap) {
          final hitMsgs = <(String, String)>[];
          if (snap.hasData && _q.isNotEmpty) {
            for (final c in convs) {
              for (final m in snap.data!.loadByConversation(c.id)) {
                if (!m.recalled && m.content.contains(_q)) {
                  hitMsgs.add((c.id, m.content));
                  if (hitMsgs.length > 30) break;
                }
              }
            }
          }
          if (_q.isEmpty) {
            return const Center(
              child: Text(
                '搜索联系人 / 聊天记录 / 朋友圈',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          if (hitConvs.isEmpty && hitMsgs.isEmpty && hitMoments.isEmpty) {
            return const Center(
              child: Text(
                '没有找到相关内容',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            );
          }
          return ListView(
            children: [
              if (hitConvs.isNotEmpty) _Header('联系人'),
              for (final c in hitConvs)
                ListTile(
                  leading: AppAvatar(contact: c.contact, size: 40),
                  title: Text(c.contact.displayName),
                  onTap: () => context.push('/chat/${c.id}'),
                ),
              if (hitMsgs.isNotEmpty) _Header('聊天记录'),
              for (final (convId, text) in hitMsgs)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: Text(
                    text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.push('/chat/$convId'),
                ),
              if (hitMoments.isNotEmpty) _Header('朋友圈'),
              for (final m in hitMoments)
                ListTile(
                  dense: true,
                  leading: const Icon(Icons.photo_library_outlined),
                  title: Text(
                    m.text,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => context.push('/moments'),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    ),
  );
}
