import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../providers/conversation_provider.dart';
import '../contact/add_ai_friend_page.dart';

/// 发起群聊 / 群聊加人：从 AI 好友里勾选成员组成多 agent 群聊
/// - 创建模式：微信页 + 菜单进入，勾选 ≥1 位 AI 好友生成群会话
/// - 编辑模式：传 [existing] 时为已有群聊增删成员
class GroupCreatePage extends ConsumerStatefulWidget {
  /// 已有群聊（聊天信息页 + 号进入时传入）
  final Conversation? existing;

  /// 预勾选成员（单聊页 + 号把当前联系人带进来建群）
  final List<Contact> initialSelected;

  const GroupCreatePage({
    super.key,
    this.existing,
    this.initialSelected = const [],
  });

  @override
  ConsumerState<GroupCreatePage> createState() => _GroupCreatePageState();
}

class _GroupCreatePageState extends ConsumerState<GroupCreatePage> {
  final List<Contact> _selected = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected.addAll(widget.existing?.members ?? widget.initialSelected);
  }

  /// 可选成员 = 所有 AI 好友，已选但不在列表里的也补上
  List<Contact> _candidates(List<Conversation> conversations) {
    final result = <Contact>[];
    final seen = <String>{};
    for (final c in _selected) {
      if (seen.add(c.id)) result.add(c);
    }
    for (final conv in conversations) {
      final contact = conv.contact;
      if (contact.isAi && !contact.isGroup && seen.add(contact.id)) {
        result.add(contact);
      }
    }
    return result;
  }

  void _toggle(Contact contact) {
    setState(() {
      final index = _selected.indexWhere((c) => c.id == contact.id);
      if (index >= 0) {
        _selected.removeAt(index);
      } else {
        _selected.add(contact);
      }
    });
  }

  Future<void> _done() async {
    if (_saving || _selected.isEmpty) return;
    setState(() => _saving = true);

    final existing = widget.existing;
    if (existing != null) {
      await ref
          .read(conversationListProvider.notifier)
          .updateMembers(existing.id, List.of(_selected));
      if (mounted) context.pop();
      return;
    }

    final ts = DateTime.now().millisecondsSinceEpoch;
    final id = 'conv_group_$ts';
    final name = _selected.take(3).map((c) => c.displayName).join('、');
    await ref.read(conversationListProvider.notifier).addConversation(
          Conversation(
            id: id,
            contact: Contact(id: 'group_$ts', name: name, isGroup: true),
            members: List.of(_selected),
            lastMessage: '',
            lastMessageTime: DateTime.now(),
          ),
        );
    if (!mounted) return;
    context.pop();
    context.push('/chat/$id');
  }

  @override
  Widget build(BuildContext context) {
    final conversations =
        ref.watch(resolvedConversationListProvider).value ?? const [];
    final candidates = _candidates(conversations);
    final isEdit = widget.existing != null;

    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? '选择成员' : '发起群聊'),
        actions: [
          TextButton(
            onPressed: _selected.isEmpty || _saving ? null : _done,
            child: Text(
              _selected.isEmpty ? '完成' : '完成(${_selected.length})',
              style: TextStyle(
                color: _selected.isEmpty
                    ? AppColors.textSecondary
                    : AppColors.primary,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 已选成员头像横排（仿微信选人页顶部）
          if (_selected.isNotEmpty)
            Container(
              width: double.infinity,
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Wrap(
                spacing: 14,
                runSpacing: 10,
                children: [
                  for (final c in _selected)
                    GestureDetector(
                      onTap: () => _toggle(c),
                      child: Column(
                        children: [
                          AppAvatar(contact: c, size: 48),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 52,
                            child: Text(
                              c.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.textSecondary),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          Expanded(
            child: ListView(
              children: [
                // 没有想要的 AI？现场新建一个再回来勾选
                ListTile(
                  leading: Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.divider),
                      borderRadius:
                          BorderRadius.circular(AppDimens.avatarRadius),
                    ),
                    child: const Icon(Icons.add,
                        color: AppColors.textSecondary),
                  ),
                  title: const Text('新建 AI 好友',
                      style: TextStyle(fontSize: 16)),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const AddAiFriendPage())),
                ),
                const Divider(height: 1),
                if (candidates.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(
                      child: Text('还没有 AI 好友，先点上方「新建 AI 好友」',
                          style:
                              TextStyle(color: AppColors.textSecondary)),
                    ),
                  ),
                for (final c in candidates) _MemberTile(
                  contact: c,
                  checked: _selected.any((s) => s.id == c.id),
                  onTap: () => _toggle(c),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  final Contact contact;
  final bool checked;
  final VoidCallback onTap;

  const _MemberTile({
    required this.contact,
    required this.checked,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              checked ? Icons.check_circle : Icons.circle_outlined,
              color: checked ? AppColors.primary : AppColors.divider,
              size: 24,
            ),
            const SizedBox(width: 12),
            AppAvatar(contact: contact, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Text(contact.displayName,
                  style: const TextStyle(fontSize: 16),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis),
            ),
          ],
        ),
      ),
    );
  }
}
