import '../../core/widgets/app_page_body.dart';
import '../../core/widgets/wechat_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/avatar_picker.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../common/edit_field_page.dart';
import 'chat_search_page.dart';
import '../conversation/group_create_page.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../services/ai_prompt.dart';

/// 聊天信息页（聊天页右上角 ··· 进入）：换头像 / 置顶 / 免打扰 / 清空记录
class ChatInfoPage extends ConsumerWidget {
  static const _backgroundColors = [
    Color(0xFFEDEDED),
    Color(0xFFF4F0E8),
    Color(0xFFE8F1F5),
    Color(0xFFF5EAF0),
    Color(0xFFEAF2E7),
    Color(0xFFEFEAF5),
    Color(0xFFF4F3E9),
    Color(0xFFDDE9E5),
  ];

  final String conversationId;

  const ChatInfoPage({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversation = ref
        .watch(resolvedConversationListProvider)
        .value
        ?.where((c) => c.id == conversationId)
        .firstOrNull;
    final contact = conversation?.contact;
    final chatBackground = ref.watch(chatBackgroundProvider(conversationId));

    final isGroup = contact?.isGroup ?? false;
    final members = conversation?.members ?? const <Contact>[];
    final aiProfile = !isGroup && (contact?.isAi ?? false)
        ? ref.watch(aiProfileProvider(conversationId))
        : null;

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('聊天信息')),
      body: AppPageBody(
        child: ListView(
          children: [
            // 成员区：单聊 = 对方头像（点击换头像）；群聊 = 全部成员宫格（点击进其 AI 设置）
            Material(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Wrap(
                  spacing: 20,
                  runSpacing: 12,
                  children: [
                    if (isGroup)
                      for (final m in members)
                        _MemberCell(
                          contact: m,
                          onTap: () => _openMemberSettings(context, ref, m),
                        )
                    else if (contact != null)
                      _MemberCell(
                        contact: contact,
                        onTap: () => _changeAvatar(context, ref, contact),
                      ),
                    // 添加成员入口（仿微信 + 号格）
                    _MemberCell(
                      contact: null,
                      onTap: () => _addMember(context, contact, conversation),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 16, top: 6, bottom: 12),
              child: Text(
                isGroup ? '点成员头像可改其 AI 设置，+ 号添加成员' : '点击头像可更换',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
            // 设置项
            if (conversation != null)
              Material(
                color: Colors.white,
                child: Column(
                  children: [
                    SwitchListTile(
                      title: const Text('置顶聊天', style: TextStyle(fontSize: 16)),
                      value: conversation.pinned,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) => ref
                          .read(conversationListProvider.notifier)
                          .setFlag(conversationId, pinned: v),
                    ),
                    const Divider(indent: 16, height: 1),
                    SwitchListTile(
                      title: const Text(
                        '消息免打扰',
                        style: TextStyle(fontSize: 16),
                      ),
                      value: conversation.muted,
                      activeTrackColor: AppColors.primary,
                      onChanged: (v) => ref
                          .read(conversationListProvider.notifier)
                          .setFlag(conversationId, muted: v),
                    ),
                    const Divider(indent: 16, height: 1),
                    ListTile(
                      leading: const Icon(
                        Icons.wallpaper_outlined,
                        color: AppColors.primary,
                      ),
                      title: const Text('聊天背景', style: TextStyle(fontSize: 16)),
                      subtitle: Text(
                        chatBackground.imageBytes != null
                            ? '自定义图片'
                            : chatBackground.colorValue == null
                            ? '默认背景'
                            : '已设置预设颜色',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      trailing: const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                      onTap: () =>
                          _showBackgroundPicker(context, ref, chatBackground),
                    ),
                    if (aiProfile != null) ...[
                      const Divider(indent: 16, height: 1),
                      ListTile(
                        leading: Icon(
                          relationshipStageForUser(aiProfile) == '相爱'
                              ? Icons.favorite
                              : Icons.favorite_border,
                          color: relationshipStageForUser(aiProfile) == '相爱'
                              ? Colors.redAccent
                              : AppColors.primary,
                        ),
                        title: const Text(
                          '关系阶段',
                          style: TextStyle(fontSize: 16),
                        ),
                        subtitle: Text(
                          relationshipStageForUser(aiProfile),
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  if (contact != null)
                    ListTile(
                      title: Text(
                        isGroup ? '群聊名称' : '设置备注和标签',
                        style: const TextStyle(fontSize: 16),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            contact.remark ?? '',
                            style: const TextStyle(
                              fontSize: 15,
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.chevron_right,
                            color: AppColors.textSecondary,
                          ),
                        ],
                      ),
                      onTap: () => _editRemark(context, ref, contact),
                    ),
                  const Divider(indent: 16, height: 1),
                  ListTile(
                    title: const Text('查找聊天记录', style: TextStyle(fontSize: 16)),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) =>
                            ChatSearchPage(conversationId: conversationId),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // AI 会话专属：人设/知识库/聊天记录设置
            if (contact?.isAi ?? false) ...[
              const SizedBox(height: 8),
              Material(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(
                    Icons.smart_toy_outlined,
                    color: AppColors.primary,
                  ),
                  title: const Text('AI 设置', style: TextStyle(fontSize: 16)),
                  subtitle: const Text(
                    '人设、知识库、聊天记录风格',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onTap: () => context.push('/chat/$conversationId/ai'),
                ),
              ),
            ],
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              child: ListTile(
                title: const Center(
                  child: Text(
                    '清空聊天记录',
                    style: TextStyle(fontSize: 16, color: Colors.red),
                  ),
                ),
                onTap: () => _clearHistory(context, ref),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showBackgroundPicker(
    BuildContext context,
    WidgetRef ref,
    ChatBackground current,
  ) {
    showDialog<void>(
      context: context,
      builder: (sheetContext) => WeChatDialog(
        title: const Text('聊天背景'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            GridView.count(
              crossAxisCount: 4,
              childAspectRatio: 1.2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              children: [
                for (final color in _backgroundColors)
                  InkWell(
                    borderRadius: BorderRadius.circular(12),
                    onTap: () async {
                      await ref
                          .read(chatBackgroundProvider(conversationId).notifier)
                          .setColor(color.toARGB32());
                      if (sheetContext.mounted) {
                        Navigator.pop(sheetContext);
                      }
                    },
                    child: Container(
                      decoration: BoxDecoration(
                        color: color,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color:
                              current.imageBytes == null &&
                                  current.colorValue == color.toARGB32()
                              ? AppColors.primary
                              : AppColors.divider,
                          width:
                              current.imageBytes == null &&
                                  current.colorValue == color.toARGB32()
                              ? 2
                              : 1,
                        ),
                      ),
                      child:
                          current.imageBytes == null &&
                              current.colorValue == color.toARGB32()
                          ? const Icon(Icons.check, color: AppColors.primary)
                          : null,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () async {
                  Navigator.pop(sheetContext);
                  await _pickChatBackground(context, ref);
                },
                icon: const Icon(Icons.photo_library_outlined),
                label: const Text('从相册选择'),
              ),
            ),
            if (current.imageBytes != null || current.colorValue != null)
              Center(
                child: TextButton(
                  onPressed: () async {
                    await ref
                        .read(chatBackgroundProvider(conversationId).notifier)
                        .clear();
                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                  },
                  child: const Text('恢复默认背景'),
                ),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(sheetContext),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickChatBackground(BuildContext context, WidgetRef ref) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      if (bytes.isEmpty) return;
      await ref
          .read(chatBackgroundProvider(conversationId).notifier)
          .setImage(bytes);
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('聊天背景已更新')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('选择背景失败')));
      }
    }
  }

  /// + 号格：群聊 → 增删成员；单聊 AI → 拉 TA 一起建群；其他 → 占位
  void _addMember(
    BuildContext context,
    Contact? contact,
    Conversation? conversation,
  ) {
    if (conversation == null || contact == null) return;
    if (contact.isGroup) {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupCreatePage(existing: conversation),
        ),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => GroupCreatePage(initialSelected: [contact]),
        ),
      );
    }
  }

  /// 群成员头像 → 跳到该成员单聊会话的 AI 设置页（人设/知识库/模型共享）
  void _openMemberSettings(
    BuildContext context,
    WidgetRef ref,
    Contact member,
  ) {
    for (final c in ref.read(conversationListProvider).value ?? const []) {
      if (!c.contact.isGroup && c.contact.id == member.id) {
        context.push('/chat/${c.id}/ai');
        return;
      }
    }
  }

  /// 设置备注：空内容 = 清除备注恢复原名（群聊时即群聊名称）
  Future<void> _editRemark(
    BuildContext context,
    WidgetRef ref,
    Contact contact,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldPage(
          title: contact.isGroup ? '群聊名称' : '备注',
          initial: contact.remark ?? '',
          hint: contact.isGroup ? '输入群聊名称' : '输入备注名，留空恢复原名',
        ),
      ),
    );
    if (result != null) {
      await ref
          .read(contactOverridesProvider.notifier)
          .setRemark(contact, result);
    }
  }

  void _changeAvatar(BuildContext context, WidgetRef ref, Contact contact) {
    showAvatarPicker(
      context,
      onBytes: (bytes) => ref
          .read(contactOverridesProvider.notifier)
          .setAvatarBytes(contact, bytes),
      onAsset: (asset) => ref
          .read(contactOverridesProvider.notifier)
          .setAvatarAsset(contact, asset),
    );
  }

  Future<void> _clearHistory(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => WeChatDialog(
        title: const Text('清空聊天记录'),
        content: const Text('确定删除该会话的全部聊天记录吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('清空', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(messageRepositoryProvider).init();
    await ref.read(messageRepositoryProvider).clearConversation(conversationId);
    ref.invalidate(chatMessagesProvider(conversationId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空'), duration: Duration(seconds: 1)),
      );
    }
  }
}

/// 成员宫格单元：contact 为空时渲染 + 号格（添加成员入口）
class _MemberCell extends StatelessWidget {
  final Contact? contact;
  final VoidCallback onTap;

  const _MemberCell({required this.contact, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = contact;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          c != null
              ? AppAvatar(contact: c, size: 56)
              : Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    border: Border.all(color: AppColors.divider),
                    borderRadius: BorderRadius.circular(AppDimens.avatarRadius),
                  ),
                  child: const Icon(
                    Icons.add,
                    color: AppColors.textSecondary,
                    size: 30,
                  ),
                ),
          const SizedBox(height: 6),
          SizedBox(
            width: 60,
            child: Text(
              c?.displayName ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
