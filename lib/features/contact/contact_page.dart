import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../repositories/mock_data.dart';
import 'add_ai_friend_page.dart';

/// 通讯录页：顶部功能入口 + 联系人列表（含用户创建的 AI 好友）
/// TODO(模块四): A-Z 字母索引栏 + 按拼音分组排序（scrollable_positioned_list）
class ContactPage extends ConsumerWidget {
  const ContactPage({super.key});

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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final overrides = ref.watch(contactOverridesProvider);
    final mockIds = MockData.contacts.map((c) => c.id).toSet();
    final contacts = [
      for (final c in MockData.contacts) resolveContact(overrides, c),
      // 用户自建的联系人（AI 好友）随会话持久化，不在 Mock 列表里的补进来
      for (final conv
          in ref.watch(resolvedConversationListProvider).value ?? const [])
        if (!mockIds.contains(conv.contact.id)) conv.contact,
    ];

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
      body: ListView.separated(
        itemCount: _entries.length + contacts.length,
        separatorBuilder: (context, index) => Divider(
          indent: index < _entries.length ? 16 : 76,
        ),
        itemBuilder: (context, index) {
          if (index < _entries.length) {
            final (icon, color, label) = _entries[index];
            return _EntryTile(
              icon: icon,
              color: color,
              label: label,
              onTap: label == '新的朋友' ? () => _addAiFriend(context) : null,
            );
          }
          final contact = contacts[index - _entries.length];
          return _ContactTile(contact: contact);
        },
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
      onTap: () {},
    );
  }
}
