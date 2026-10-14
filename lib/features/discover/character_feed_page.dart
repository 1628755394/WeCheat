import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/contact_override_provider.dart';
import '../../repositories/ai_characters.dart';
import 'character_gallery_widgets.dart';

class CharacterFeedPage extends ConsumerStatefulWidget {
  const CharacterFeedPage({super.key});

  @override
  ConsumerState<CharacterFeedPage> createState() => _CharacterFeedPageState();
}

class _CharacterFeedPageState extends ConsumerState<CharacterFeedPage> {
  String _query = '';
  String _source = '全部';

  @override
  Widget build(BuildContext context) {
    final overrides = ref.watch(contactOverridesProvider);
    final characters = AiCharacters.all.where((character) {
      final presentation = characterPresentation(character);
      final profile = ref.watch(aiProfileProvider(character.conversationId));
      final name = resolveContact(overrides, character.contact).displayName;
      final content =
          '$name ${character.name} ${presentation.source} '
          '${presentation.tags.join(' ')} ${profile.persona.isEmpty ? character.persona : profile.persona}';
      return (_source == '全部' || presentation.source == _source) &&
          content.toLowerCase().contains(_query.trim().toLowerCase());
    }).toList();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('角色广场')),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1080),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
            children: [
              const Text(
                '找一个聊得来的人',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 25,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '熟悉的角色，新的故事。从一句你好开始。',
                style: TextStyle(
                  color: Color(0xFF78817B),
                  fontSize: 13,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 24),
              TextField(
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '搜索角色、作品或性格',
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: const Color(0xFFF5F7F5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: AppColors.primary),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final source in [
                    '全部',
                    ...AiCharacters.all
                        .map((c) => characterPresentation(c).source)
                        .toSet(),
                  ])
                    ChoiceChip(
                      label: Text(source),
                      selected: _source == source,
                      showCheckmark: false,
                      selectedColor: const Color(0xFFE7F5EC),
                      backgroundColor: Colors.white,
                      side: BorderSide(
                        color: _source == source
                            ? const Color(0xFFB8DEC6)
                            : AppColors.divider,
                      ),
                      labelStyle: TextStyle(
                        color: _source == source
                            ? const Color(0xFF267447)
                            : const Color(0xFF737B76),
                        fontSize: 12,
                      ),
                      onSelected: (_) => setState(() => _source = source),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              Text(
                '${characters.length} 位角色',
                style: const TextStyle(color: Color(0xFF78817B), fontSize: 12),
              ),
              const SizedBox(height: 12),
              if (characters.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 48),
                  child: Column(
                    children: [
                      Icon(
                        Icons.search_off_rounded,
                        size: 36,
                        color: Color(0xFFA0AAA3),
                      ),
                      SizedBox(height: 12),
                      Text(
                        '暂时没有找到这个角色',
                        style: TextStyle(color: AppColors.ink),
                      ),
                      SizedBox(height: 6),
                      Text(
                        '试试其他名字，或切换到「全部」',
                        style: TextStyle(
                          color: AppColors.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                )
              else
                CharacterGalleryGrid(characters: characters),
            ],
          ),
        ),
      ),
    );
  }
}
