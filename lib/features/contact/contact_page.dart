import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../repositories/mock_data.dart';

/// 通讯录页：顶部功能入口 + 联系人列表
/// TODO(模块四): A-Z 字母索引栏 + 按拼音分组排序（scrollable_positioned_list）
class ContactPage extends StatelessWidget {
  const ContactPage({super.key});

  static const _entries = [
    (Icons.person_add_alt_1, Color(0xFFFA9D3B), '新的朋友'),
    (Icons.groups, Color(0xFF3D8BFD), '群聊'),
    (Icons.local_offer, Color(0xFF3D8BFD), '标签'),
    (Icons.person, Color(0xFFFA9D3B), '公众号'),
  ];

  @override
  Widget build(BuildContext context) {
    final contacts = MockData.contacts;

    return Scaffold(
      appBar: AppBar(
        title: const Text('通讯录'),
        actions: [
          IconButton(icon: const Icon(Icons.person_add_alt), onPressed: () {}),
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
            return _EntryTile(icon: icon, color: color, label: label);
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

  const _EntryTile({required this.icon, required this.color, required this.label});

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
      onTap: () {},
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
