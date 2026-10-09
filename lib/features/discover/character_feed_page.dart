import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../providers/ai_profile_provider.dart';
import '../../repositories/ai_characters.dart';

/// 角色广场：猫箱式上下滑角色卡推荐流
/// 全屏卡片 = 立绘 + 名字 + 人设摘要 + 开场白 + 「开始聊天」
class CharacterFeedPage extends ConsumerWidget {
  const CharacterFeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: const Text('角色广场'),
      ),
      body: PageView.builder(
        scrollDirection: Axis.vertical,
        itemCount: AiCharacters.all.length,
        itemBuilder: (context, i) =>
            _CharacterCard(character: AiCharacters.all[i]),
      ),
    );
  }
}

class _CharacterCard extends ConsumerWidget {
  final AiCharacter character;

  const _CharacterCard({required this.character});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 实时读资料，AI 设置里改过人设/开场白这里会跟着变
    final profile = ref.watch(aiProfileProvider(character.conversationId));
    final persona = profile.persona.isEmpty
        ? character.persona
        : profile.persona;
    final greeting =
        profile.greeting.isEmpty ? character.greeting : profile.greeting;

    return Stack(
      fit: StackFit.expand,
      children: [
        // 立绘
        if (character.avatarAsset != null)
          Image.asset(character.avatarAsset!, fit: BoxFit.cover)
        else
          Container(color: const Color(0xFF2E3238)),
        // 底部渐变遮罩
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.transparent, Colors.black87],
              stops: [0.45, 1.0],
            ),
          ),
        ),
        // 底部信息
        Positioned(
          left: 20,
          right: 20,
          bottom: 40,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                character.name,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 30,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                persona.length > 80 ? '${persona.substring(0, 80)}…' : persona,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white70, fontSize: 13, height: 1.5),
              ),
              const SizedBox(height: 12),
              // 开场白气泡
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  greeting,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white, fontSize: 13, height: 1.5),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        minimumSize: const Size.fromHeight(44),
                      ),
                      icon: const Icon(Icons.chat_bubble_outline),
                      label: const Text('开始聊天'),
                      onPressed: () => context.push(
                          '/chat/${character.conversationId}'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  IconButton.filled(
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.white24,
                      minimumSize: const Size(44, 44),
                    ),
                    icon: const Icon(Icons.call, color: Colors.white),
                    tooltip: '语音通话',
                    onPressed: () => context.push(
                        '/call/${character.conversationId}?video=0'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text('上滑看下一个角色',
                    style: TextStyle(color: Colors.white38, fontSize: 12)),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
