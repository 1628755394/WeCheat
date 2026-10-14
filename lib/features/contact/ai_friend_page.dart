import '../../core/widgets/wechat_dialog.dart';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' show FTile, FTileGroup;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/ai_profile.dart';
import '../../models/contact.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../services/ai_prompt.dart';
import 'ai_diary_page.dart';

/// AI 好友角色卡（猫箱式）：头像 / 人设介绍 / 开场白 + 发消息、AI 设置入口
/// 从通讯录点 AI 联系人进入
class AiFriendPage extends ConsumerWidget {
  final Contact contact;

  const AiFriendPage({super.key, required this.contact});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 该好友对应的单聊会话（创建 AI 好友时已一并生成）
    final conversations =
        ref.watch(resolvedConversationListProvider).value ?? const [];
    final conv = conversations
        .where((c) => !c.contact.isGroup && c.contact.id == contact.id)
        .firstOrNull;
    final profile = conv == null
        ? const AiProfile()
        : ref.watch(aiProfileProvider(conv.id));

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(),
      body: ListView(
        children: [
          const SizedBox(height: 28),
          Center(child: AppAvatar(contact: contact, size: 96)),
          const SizedBox(height: 12),
          Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  contact.displayName,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'AI',
                    style: TextStyle(fontSize: 11, color: AppColors.primary),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          _Card('人设', profile.persona.isEmpty ? '未设置' : profile.persona),
          _Card('开场白', profile.greeting.isEmpty ? '未设置' : profile.greeting),
          const SizedBox(height: 8),
          if (conv != null) ...[
            FTileGroup(
              children: [
                FTile(
                  prefix: const Icon(
                    Icons.favorite_border,
                    color: Colors.redAccent,
                  ),
                  title: const Text('TA 的心声'),
                  subtitle: const Text(
                    '看看 TA 此刻心里在想什么',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  suffix: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onPress: () => _showInnerVoice(context, ref, conv.id),
                ),
                FTile(
                  prefix: const Icon(Icons.book, color: AppColors.primary),
                  title: const Text('TA 的日记'),
                  subtitle: Text(
                    profile.diaries.isEmpty
                        ? '还没有日记，进去让 TA 写一篇'
                        : '共 ${profile.diaries.length} 篇 · 最新：${profile.diaries.last.split('|').first}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  suffix: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onPress: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AiDiaryPage(
                        conversationId: conv.id,
                        name: contact.displayName,
                      ),
                    ),
                  ),
                ),
                FTile(
                  prefix: const Icon(Icons.tune, color: AppColors.primary),
                  title: const Text('AI 设置'),
                  subtitle: const Text(
                    '模型、知识库、聊天记录风格',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  suffix: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onPress: () => context.push('/chat/${conv.id}/ai'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  minimumSize: const Size.fromHeight(44),
                ),
                onPressed: () {
                  final wide =
                      MediaQuery.sizeOf(context).width >=
                      AppDimens.desktopBreakpoint;
                  if (wide) {
                    context.go('/chat/${conv.id}');
                  } else {
                    context.push('/chat/${conv.id}');
                  }
                },
                child: const Text('发消息', style: TextStyle(fontSize: 16)),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: OutlinedButton.icon(
                onPressed: () async {
                  final delete = await showDialog<bool>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      title: const Text('删除好友'),
                      content: Text('删除 ${contact.displayName} 及其聊天记录和角色资料？'),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, false),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () => Navigator.pop(dialogContext, true),
                          child: const Text('删除'),
                        ),
                      ],
                    ),
                  );
                  if (delete != true || !context.mounted) return;
                  await ref
                      .read(conversationListProvider.notifier)
                      .deleteFriend(conv);
                  if (context.mounted) Navigator.of(context).pop();
                },
                icon: const Icon(Icons.person_remove_outlined),
                label: const Text('删除好友'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// 「TA 的心声」：生成该 AI 此刻的内心独白（猫箱式内心戏）
  void _showInnerVoice(BuildContext context, WidgetRef ref, String convId) {
    showDialog(
      context: context,
      builder: (ctx) => WeChatDialog(
        title: Text(
          '${contact.displayName}的心声',
          style: const TextStyle(fontSize: 17),
        ),
        content: FutureBuilder<String>(
          future: _innerVoice(ref, convId),
          builder: (ctx, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const SizedBox(
                height: 80,
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Text(
              snap.data?.isNotEmpty == true ? snap.data! : '（TA 现在不想说话）',
              style: const TextStyle(fontSize: 15, height: 1.6),
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  /// 内心独白生成：完整人设 prompt + 内心戏指令，参考最近聊天记录
  Future<String> _innerVoice(WidgetRef ref, String convId) async {
    await ref.read(aiProfileProvider(convId).notifier).ensureLoaded();
    final profile = ref.read(aiProfileProvider(convId));
    final repo = ref.read(messageRepositoryProvider);
    await repo.init();
    final history = [
      for (final m in repo.loadByConversation(convId).reversed.take(10))
        if (!m.recalled)
          (role: m.isMe ? 'user' : 'assistant', content: m.content),
    ].reversed.toList();
    final systemPrompt =
        '${buildAiSystemPrompt(profile)}'
        '\n\n【任务】以第一人称写一段你此刻的内心独白：关于 TA、你们最近的聊天、'
        '你不敢说出口的真实想法和藏在心里的感受。100 字左右，私密、真实、'
        '符合你的性格，不要括号动作描写，像深夜写给日记的话。';
    var out = '';
    try {
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(profile, history, systemPrompt: systemPrompt)) {
        out += chunk;
      }
    } catch (_) {}
    return out.trim();
  }
}

class _Card extends StatelessWidget {
  final String title;
  final String text;

  const _Card(this.title, this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Text(text, style: const TextStyle(fontSize: 15, height: 1.5)),
        ],
      ),
    );
  }
}
