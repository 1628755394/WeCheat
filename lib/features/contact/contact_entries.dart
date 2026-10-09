import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../repositories/mock_data.dart';

/// 通讯录「群聊」入口：列出所有群会话
class GroupListPage extends ConsumerWidget {
  const GroupListPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groups = [
      for (final c
          in ref.watch(resolvedConversationListProvider).value ?? const [])
        if (c.contact.isGroup) c,
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('群聊')),
      body: groups.isEmpty
          ? const Center(
              child: Text('暂无群聊',
                  style: TextStyle(color: AppColors.textSecondary)))
          : ListView.separated(
              itemCount: groups.length,
              separatorBuilder: (_, _) => const Divider(indent: 72),
              itemBuilder: (context, i) => ListTile(
                leading: AppAvatar(contact: groups[i].contact, size: 42),
                title: Text(groups[i].contact.displayName),
                subtitle: Text('${groups[i].members.length + 1} 人',
                    style: const TextStyle(fontSize: 12)),
                onTap: () => context.push('/chat/${groups[i].id}'),
              ),
            ),
    );
  }
}

/// 通讯录「标签」入口：标签分组管理（Hive box=contact_tags，tag → contactIds）
class TagsPage extends ConsumerStatefulWidget {
  const TagsPage({super.key});

  @override
  ConsumerState<TagsPage> createState() => _TagsPageState();
}

class _TagsPageState extends ConsumerState<TagsPage> {
  static const _boxName = 'contact_tags';
  Box? _box;

  @override
  void initState() {
    super.initState();
    Hive.openBox(_boxName).then((b) {
      if (mounted) setState(() => _box = b);
    });
  }

  Map<String, List<String>> get _tags => {
        for (final k in _box?.keys ?? const [])
          k as String: ((_box!.get(k) as List?) ?? const []).cast<String>(),
      };

  @override
  Widget build(BuildContext context) {
    final tags = _tags;
    return Scaffold(
      appBar: AppBar(
        title: const Text('标签'),
        actions: [
          IconButton(icon: const Icon(Icons.add), onPressed: _createTag),
        ],
      ),
      body: _box == null
          ? const Center(child: CircularProgressIndicator())
          : tags.isEmpty
              ? const Center(
                  child: Text('还没有标签\n点右上角 + 新建',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.textSecondary)))
              : ListView.separated(
                  itemCount: tags.length,
                  separatorBuilder: (_, _) => const Divider(indent: 16),
                  itemBuilder: (context, i) {
                    final name = tags.keys.elementAt(i);
                    final ids = tags[name]!;
                    return ListTile(
                      leading: const Icon(Icons.local_offer,
                          color: Color(0xFF3D8BFD)),
                      title: Text(name),
                      subtitle: Text('${ids.length} 人',
                          style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () async {
                          await _box!.delete(name);
                          setState(() {});
                        },
                      ),
                      onTap: () => _showMembers(name, ids),
                    );
                  },
                ),
    );
  }

  List<Contact> _allContacts() {
    final overrides = ref.read(contactOverridesProvider);
    return [
      for (final c in MockData.contacts)
        if (!c.isGroup) resolveContact(overrides, c),
      for (final conv
          in ref.read(resolvedConversationListProvider).value ?? const [])
        if (!conv.contact.isGroup) conv.contact,
    ];
  }

  void _showMembers(String tag, List<String> ids) {
    final all = _allContacts();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('标签：$tag',
                  style: const TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600)),
            ),
            for (final id in ids)
              ListTile(
                leading: AppAvatar(
                    contact: all.firstWhere((c) => c.id == id,
                        orElse: () => Contact(id: id, name: id)),
                    size: 36),
                title: Text(all
                    .firstWhere((c) => c.id == id,
                        orElse: () => Contact(id: id, name: id))
                    .displayName),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _createTag() async {
    final nameCtl = TextEditingController();
    final all = _allContacts();
    final selected = <String>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) => AlertDialog(
          title: const Text('新建标签'),
          content: SizedBox(
            width: 360,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtl,
                  decoration: const InputDecoration(hintText: '标签名'),
                ),
                const SizedBox(height: 8),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final c in all)
                        CheckboxListTile(
                          dense: true,
                          value: selected.contains(c.id),
                          title: Text(c.displayName),
                          onChanged: (v) => setDlg(() => v == true
                              ? selected.add(c.id)
                              : selected.remove(c.id)),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('取消')),
            TextButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('确定')),
          ],
        ),
      ),
    );
    if (ok == true && nameCtl.text.trim().isNotEmpty) {
      await _box!.put(nameCtl.text.trim(), selected.toList());
      setState(() {});
    }
  }
}

/// 通讯录「公众号」入口：Mock 订阅号列表
class OfficialAccountsPage extends StatelessWidget {
  const OfficialAccountsPage({super.key});

  @override
  Widget build(BuildContext context) {
    const accounts = [
      ('WeCheat 官方', '产品更新与使用技巧', Icons.verified),
      ('AI 角色研究所', '人设写作与角色扮演分享', Icons.psychology),
      ('深夜食堂', '每晚十点更新一道菜', Icons.restaurant),
      ('城市漫步', '周末去哪玩', Icons.map),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('公众号')),
      body: ListView.separated(
        itemCount: accounts.length,
        separatorBuilder: (_, _) => const Divider(indent: 72),
        itemBuilder: (context, i) => ListTile(
          leading: CircleAvatar(
            backgroundColor: AppColors.searchBg,
            child: Icon(accounts[i].$3, color: AppColors.primary),
          ),
          title: Text(accounts[i].$1),
          subtitle: Text(accounts[i].$2, style: const TextStyle(fontSize: 12)),
        ),
      ),
    );
  }
}
