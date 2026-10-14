import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../models/moment.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/moments_provider.dart';
import 'add_ai_friend_page.dart';
import 'ai_friend_page.dart';
import 'contact_entries.dart';

/// Desktop contacts keep the category pane visible while showing a profile.
class DesktopContactPage extends ConsumerStatefulWidget {
  const DesktopContactPage({super.key, required this.contacts});

  final List<Contact> contacts;

  @override
  ConsumerState<DesktopContactPage> createState() => _DesktopContactPageState();
}

class _DesktopContactPageState extends ConsumerState<DesktopContactPage> {
  final _search = TextEditingController();
  String? _selectedId;
  bool _contactsExpanded = false;
  String? _emptyCategory;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _open(Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  @override
  Widget build(BuildContext context) {
    final contacts = [...widget.contacts]
      ..sort((a, b) => a.displayName.compareTo(b.displayName));
    final query = _search.text.trim().toLowerCase();
    final visible = contacts
        .where(
          (contact) =>
              contact.displayName.toLowerCase().contains(query) ||
              contact.wechatId.toLowerCase().contains(query),
        )
        .toList();
    final selected =
        visible.where((c) => c.id == _selectedId).firstOrNull ??
        (visible.isEmpty ? null : visible.first);
    final conversations =
        ref.watch(resolvedConversationListProvider).value ??
        const <Conversation>[];
    final conversation = conversations
        .where((c) => !c.contact.isGroup && c.contact.id == selected?.id)
        .firstOrNull;

    return Scaffold(
      backgroundColor: const Color(0xFFF9F9F9),
      body: Row(
        children: [
          Container(
            width: AppDimens.listPaneWidth,
            color: const Color(0xFFEDEDEF),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
                  child: TextField(
                    controller: _search,
                    onChanged: (_) => setState(() {}),
                    decoration: InputDecoration(
                      hintText: '搜索',
                      prefixIcon: const Icon(Icons.search, size: 19),
                      suffixIcon: query.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.close, size: 16),
                              onPressed: () => setState(_search.clear),
                            ),
                      filled: true,
                      fillColor: const Color(0xFFF9F9F9),
                      isDense: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(7),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  child: SizedBox(
                    width: double.infinity,
                    height: 42,
                    child: PopupMenuButton<String>(
                      tooltip: '通讯录管理',
                      onSelected: (value) => _open(switch (value) {
                        'add' => const AddAiFriendPage(),
                        'groups' => const GroupListPage(),
                        _ => const TagsPage(),
                      }),
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'add', child: Text('添加朋友')),
                        PopupMenuItem(value: 'groups', child: Text('群聊')),
                        PopupMenuItem(value: 'tags', child: Text('管理标签')),
                      ],
                      child: Container(
                        decoration: BoxDecoration(
                          color: const Color(0xFFF9F9F9),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.people_outline, size: 21),
                            SizedBox(width: 9),
                            Text('通讯录管理'),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 19),
                Expanded(
                  child: ListView(
                    padding: EdgeInsets.zero,
                    children: [
                      _CategoryRow(
                        label: '新的朋友',
                        onTap: () => _open(const AddAiFriendPage()),
                      ),
                      _CategoryRow(
                        label: '公众号、服务号',
                        onTap: () => _open(const OfficialAccountsPage()),
                      ),
                      _CategoryRow(
                        label: '企业微信联系人',
                        count: 0,
                        onTap: () =>
                            setState(() => _emptyCategory = '暂无企业微信联系人'),
                      ),
                      _CategoryRow(
                        label: '我的企业',
                        count: 0,
                        onTap: () =>
                            setState(() => _emptyCategory = '暂无已加入的企业'),
                      ),
                      _CategoryRow(
                        label: '联系人',
                        count: contacts.length,
                        expanded: _contactsExpanded,
                        onTap: () => setState(() {
                          _emptyCategory = null;
                          _contactsExpanded = !_contactsExpanded;
                        }),
                      ),
                      if (_contactsExpanded || query.isNotEmpty)
                        for (final contact in visible)
                          _ContactRow(
                            contact: contact,
                            selected: selected?.id == contact.id,
                            onTap: () => setState(() {
                              _emptyCategory = null;
                              _selectedId = contact.id;
                            }),
                          ),
                      if ((_contactsExpanded || query.isNotEmpty) &&
                          visible.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(20),
                          child: Text(
                            '没有找到联系人',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const VerticalDivider(width: 0.5, color: AppColors.divider),
          Expanded(
            child: _emptyCategory != null
                ? Center(
                    child: Text(
                      _emptyCategory!,
                      style: const TextStyle(color: AppColors.textSecondary),
                    ),
                  )
                : selected == null
                ? const Center(child: Text('暂无联系人'))
                : _ContactDetails(
                    contact: selected,
                    conversation: conversation,
                    onRemarkChanged: () => setState(() {}),
                  ),
          ),
        ],
      ),
    );
  }
}

class _CategoryRow extends StatelessWidget {
  const _CategoryRow({
    required this.label,
    required this.onTap,
    this.count,
    this.expanded = false,
  });
  final String label;
  final int? count;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: SizedBox(
      height: 46,
      child: Row(
        children: [
          const SizedBox(width: 23),
          Icon(
            expanded ? Icons.keyboard_arrow_down : Icons.chevron_right,
            size: 21,
            color: const Color(0xFF777777),
          ),
          const SizedBox(width: 4),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 14))),
          if (count != null)
            Text(
              '$count',
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
              ),
            ),
          const SizedBox(width: 19),
        ],
      ),
    ),
  );
}

class _ContactRow extends StatelessWidget {
  const _ContactRow({
    required this.contact,
    required this.selected,
    required this.onTap,
  });
  final Contact contact;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      height: 58,
      color: selected ? const Color(0xFFD7D7D9) : null,
      padding: const EdgeInsets.only(left: 35, right: 14),
      child: Row(
        children: [
          AppAvatar(contact: contact, size: 36),
          const SizedBox(width: 11),
          Expanded(
            child: Text(
              contact.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 14),
            ),
          ),
        ],
      ),
    ),
  );
}

class _ContactDetails extends ConsumerWidget {
  const _ContactDetails({
    required this.contact,
    required this.conversation,
    required this.onRemarkChanged,
  });
  final Contact contact;
  final Conversation? conversation;
  final VoidCallback onRemarkChanged;

  Future<void> _editRemark(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController(text: contact.remark ?? '');
    final remark = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('设置备注名'),
        content: TextField(controller: controller, autofocus: true),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (remark == null) return;
    await ref
        .read(contactOverridesProvider.notifier)
        .setRemark(contact, remark);
    onRemarkChanged();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = conversation == null
        ? null
        : ref.watch(aiProfileProvider(conversation!.id));
    final description = profile?.persona ?? '';
    final moments = (ref.watch(momentsProvider).value ?? const <Moment>[])
        .where((moment) => moment.author.id == contact.id)
        .expand((moment) => moment.images)
        .take(6)
        .toList();
    return Align(
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(28, 90, 28, 40),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 470),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppAvatar(contact: contact, size: 88, radius: 7),
                  const SizedBox(width: 24),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.displayName,
                          maxLines: 2,
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 10),
                        if (contact.wechatId.isNotEmpty)
                          Text(
                            '微信号：${contact.wechatId}',
                            style: const TextStyle(color: Color(0xFF777777)),
                          ),
                        if (contact.region.isNotEmpty)
                          Text(
                            '地区：${contact.region}',
                            style: const TextStyle(color: Color(0xFF777777)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),
              const Divider(),
              const SizedBox(height: 12),
              const Text(
                '朋友资料',
                style: TextStyle(color: Color(0xFF777777), fontSize: 14),
              ),
              const SizedBox(height: 13),
              InkWell(
                onTap: () => _editRemark(context, ref),
                child: _DetailLine(
                  label: '备注',
                  value: contact.remark?.isNotEmpty == true
                      ? contact.remark!
                      : '添加备注名',
                ),
              ),
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 16),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(
                    width: 100,
                    child: Text(
                      '朋友圈',
                      style: TextStyle(color: Color(0xFF777777)),
                    ),
                  ),
                  Expanded(
                    child: moments.isEmpty
                        ? const Text(
                            '暂无动态',
                            style: TextStyle(color: AppColors.textSecondary),
                          )
                        : Wrap(
                            spacing: 7,
                            runSpacing: 7,
                            children: [
                              for (final asset in moments)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(3),
                                  child: Image.asset(
                                    asset,
                                    width: 45,
                                    height: 45,
                                    fit: BoxFit.cover,
                                  ),
                                ),
                            ],
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 14),
              const Text(
                '更多信息',
                style: TextStyle(color: Color(0xFF777777), fontSize: 14),
              ),
              const SizedBox(height: 16),
              _DetailLine(label: '来源', value: contact.isAi ? 'AI 角色' : '通讯录'),
              if (contact.isAi && description.isNotEmpty) ...[
                const SizedBox(height: 22),
                const Divider(),
                const SizedBox(height: 14),
                const Text(
                  '角色资料',
                  style: TextStyle(color: Color(0xFF777777), fontSize: 14),
                ),
                const SizedBox(height: 14),
                Text(
                  description,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14, height: 1.5),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => AiFriendPage(contact: contact),
                    ),
                  ),
                  child: const Text('查看完整资料'),
                ),
              ],
              const SizedBox(height: 22),
              const Divider(),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _ProfileAction(
                    icon: Icons.chat_bubble_outline,
                    label: '发消息',
                    onTap: conversation == null
                        ? null
                        : () => context.go('/chat/${conversation!.id}'),
                  ),
                  _ProfileAction(
                    icon: Icons.call_outlined,
                    label: '语音聊天',
                    onTap: conversation == null
                        ? null
                        : () =>
                              context.push('/call/${conversation!.id}?video=0'),
                  ),
                  _ProfileAction(
                    icon: Icons.videocam_outlined,
                    label: '视频聊天',
                    onTap: conversation == null
                        ? null
                        : () =>
                              context.push('/call/${conversation!.id}?video=1'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Row(
    children: [
      SizedBox(
        width: 100,
        child: Text(label, style: const TextStyle(color: Color(0xFF777777))),
      ),
      Expanded(child: Text(value)),
    ],
  );
}

class _ProfileAction extends StatelessWidget {
  const _ProfileAction({required this.icon, required this.label, this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: onTap,
    style: TextButton.styleFrom(foregroundColor: const Color(0xFF365996)),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 27),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(fontSize: 13)),
      ],
    ),
  );
}
