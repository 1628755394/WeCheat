import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lpinyin/lpinyin.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../repositories/mock_data.dart';
import 'add_ai_friend_page.dart';
import 'ai_friend_page.dart';
import 'contact_entries.dart';

/// 通讯录页：顶部功能入口 + A-Z 拼音分组 + 右侧字母索引栏
class ContactPage extends ConsumerStatefulWidget {
  const ContactPage({super.key});

  @override
  ConsumerState<ContactPage> createState() => _ContactPageState();
}

class _ContactPageState extends ConsumerState<ContactPage> {
  final _scrollController = ItemScrollController();

  static const _entries = [
    (Icons.person_add_alt_1, Color(0xFFFA9D3B), '新的朋友'),
    (Icons.groups, Color(0xFF3D8BFD), '群聊'),
    (Icons.local_offer, Color(0xFF3D8BFD), '标签'),
    (Icons.person, Color(0xFFFA9D3B), '公众号'),
  ];

  void _addAiFriend(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddAiFriendPage()),
    );
  }

  /// 拼音首字母（非中文按首字符大写，无法识别归到 #）
  static String _letterOf(String name) {
    if (name.isEmpty) return '#';
    final py = PinyinHelper.getFirstWordPinyin(name.characters.first);
    if (py.isEmpty) return '#';
    final ch = py.characters.first.toUpperCase();
    return RegExp(r'[A-Z]').hasMatch(ch) ? ch : '#';
  }

  void _openEntry(String label) {
    Widget page = switch (label) {
      '群聊' => const GroupListPage(),
      '标签' => const TagsPage(),
      '公众号' => const OfficialAccountsPage(),
      _ => const AddAiFriendPage(),
    };
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => page));
  }

  @override
  Widget build(BuildContext context) {
    final overrides = ref.watch(contactOverridesProvider);
    final mockIds = MockData.contacts.map((c) => c.id).toSet();
    final contacts = [
      for (final c in MockData.contacts) resolveContact(overrides, c),
      // 用户自建的联系人（AI 好友）随会话持久化，不在 Mock 列表里的补进来；
      // 群聊的占位 contact 不算联系人，不混入通讯录
      for (final conv
          in ref.watch(resolvedConversationListProvider).value ?? const [])
        if (!conv.contact.isGroup && !mockIds.contains(conv.contact.id))
          conv.contact,
    ];

    // 按拼音首字母分组排序
    contacts.sort((a, b) => _letterOf(a.displayName)
        .compareTo(_letterOf(b.displayName)));
    // 扁平化：条目 + 分组头 + 联系人
    final items = <Object>[
      ..._entries.map((e) => e), // _EntryItem 用 record
      for (var i = 0; i < contacts.length; i++) ...[
        if (i == 0 ||
            _letterOf(contacts[i - 1].displayName) !=
                _letterOf(contacts[i].displayName))
          _letterOf(contacts[i].displayName),
        contacts[i],
      ],
    ];
    // 字母 → 该字母分组头在 items 里的下标（索引栏跳转用）
    final letterIndex = <String, int>{
      for (var i = _entries.length; i < items.length; i++)
        if (items[i] is String) items[i] as String: i,
    };
    final letters = letterIndex.keys.toList()..sort();

    return Scaffold(
      appBar: AppBar(
        title: const Text('通讯录'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_add_alt),
            onPressed: () => _addAiFriend(context),
          ),
        ],
      ),
      body: Stack(
        children: [
          ScrollablePositionedList.builder(
            itemScrollController: _scrollController,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item is (IconData, Color, String)) {
                return Column(
                  children: [
                    _EntryTile(
                      icon: item.$1,
                      color: item.$2,
                      label: item.$3,
                      onTap: () => _openEntry(item.$3),
                    ),
                    const Divider(indent: 16, height: 1),
                  ],
                );
              }
              if (item is String) {
                return Container(
                  width: double.infinity,
                  color: AppColors.searchBg,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: Text(item,
                      style: const TextStyle(
                          fontSize: 13, color: AppColors.textSecondary)),
                );
              }
              final contact = item as Contact;
              return Column(
                children: [
                  _ContactTile(contact: contact),
                  const Divider(indent: 76, height: 1),
                ],
              );
            },
          ),
          // 右侧 A-Z 索引栏
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final letter in letters)
                    GestureDetector(
                      onTap: () => _scrollController.scrollTo(
                        index: letterIndex[letter]!,
                        duration: const Duration(milliseconds: 200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 1),
                        child: Text(
                          letter,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.primary,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  const _EntryTile({
    required this.icon,
    required this.color,
    required this.label,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(AppDimens.avatarRadius),
        ),
        child: Icon(icon, color: Colors.white, size: 24),
      ),
      title: Text(label, style: const TextStyle(fontSize: 16)),
      onTap: onTap,
    );
  }
}

class _ContactTile extends StatelessWidget {
  final Contact contact;

  const _ContactTile({required this.contact});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: AppAvatar(contact: contact, size: 40),
      title: Text(contact.displayName, style: const TextStyle(fontSize: 16)),
      // AI 好友进角色卡主页（猫箱式）
      onTap: contact.isAi
          ? () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => AiFriendPage(contact: contact)))
          : null,
    );
  }
}
