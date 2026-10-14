import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/contact_override_provider.dart';
import '../../repositories/ai_characters.dart';
import '../contact/ai_friend_page.dart';

typedef CharacterPresentation = ({
  String source,
  String description,
  List<String> tags,
  Color color,
  String initial,
});

CharacterPresentation characterPresentation(AiCharacter character) =>
    switch (character.id) {
      'fengbaobao' => (
        source: '一人之下',
        description: '话不多，心很直。陪宝儿姐聊聊日常。',
        tags: ['直率', '四川话', '异人世界'],
        color: const Color(0xFF397664),
        initial: '宝',
      ),
      'yarebede' => (
        source: 'OVERLORD',
        description: '优雅与忠诚之下，是只对你流露的温柔。',
        tags: ['优雅', '守护', '纳萨力克'],
        color: const Color(0xFF70608F),
        initial: '雅',
      ),
      'shalltear' => (
        source: 'OVERLORD',
        description: '骄傲的小脾气，藏着想靠近你的心思。',
        tags: ['吸血鬼', '骄傲', '奇幻'],
        color: const Color(0xFFA35971),
        initial: '夏',
      ),
      _ => (
        source: character.id == 'baoqingfangzhu' ? '白蛇系列' : '原创角色',
        description: character.id == 'baoqingfangzhu'
            ? '一盏茶，一桩奇物，听坊主说说人间故事。'
            : '从一句问候开始，认识一个新的朋友。',
        tags: character.id == 'baoqingfangzhu'
            ? ['狐妖', '东方奇幻', '宝青坊']
            : ['日常', '陪伴'],
        color: const Color(0xFFA27642),
        initial: character.name.characters.first,
      ),
    };

class CharacterGalleryCard extends ConsumerWidget {
  const CharacterGalleryCard({super.key, required this.character});
  final AiCharacter character;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final presentation = characterPresentation(character);
    final profile = ref.watch(aiProfileProvider(character.conversationId));
    final contact = resolveContact(
      ref.watch(contactOverridesProvider),
      character.contact,
    );
    final greeting = profile.greeting.isEmpty
        ? character.greeting
        : profile.greeting;
    final color = presentation.color;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.divider),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => AiFriendPage(contact: contact),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color.withValues(alpha: 0.13),
                    color.withValues(alpha: 0.04),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                children: [
                  if (contact.avatarBytes != null ||
                      contact.avatarAsset != null)
                    AppAvatar(contact: contact, size: 64, radius: 16)
                  else
                    Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        presentation.initial,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 30,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          presentation.source,
                          style: TextStyle(
                            color: color,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            letterSpacing: 0.8,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          contact.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 19,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(Icons.arrow_outward_rounded, size: 18, color: color),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  profile.persona.isNotEmpty &&
                          profile.persona != character.persona
                      ? profile.persona
                            .replaceAll(RegExp(r'【[^】]*】'), '')
                            .trim()
                      : presentation.description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Color(0xFF626B66),
                    fontSize: 13,
                    height: 1.6,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final tag in presentation.tags)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.07),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          tag,
                          style: TextStyle(color: color, fontSize: 11),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF7F8F7),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    greeting.isEmpty ? '想聊些什么？来打个招呼吧。' : greeting,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFF525C56),
                      fontSize: 12,
                      height: 1.6,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: FButton(
                        onPress: () =>
                            context.push('/chat/${character.conversationId}'),
                        child: const Text('开始聊天'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FButton.icon(
                      variant: FButtonVariant.outline,
                      semanticsLabel: '与${contact.displayName}语音通话',
                      onPress: () => context.push(
                        '/call/${character.conversationId}?video=0',
                      ),
                      child: const Icon(Icons.call_outlined, size: 18),
                    ),
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

/// Natural card heights avoid clipping when the user increases text size.
class CharacterGalleryGrid extends StatelessWidget {
  const CharacterGalleryGrid({super.key, required this.characters});
  final List<AiCharacter> characters;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final columns = constraints.maxWidth >= 940
          ? 3
          : constraints.maxWidth >= 600
          ? 2
          : 1;
      final width = (constraints.maxWidth - (columns - 1) * 16) / columns;
      return Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final character in characters)
            SizedBox(
              width: width,
              child: CharacterGalleryCard(character: character),
            ),
        ],
      );
    },
  );
}
