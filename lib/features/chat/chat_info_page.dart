import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/avatar_picker.dart';
import '../../models/contact.dart';
import '../../providers/chat_provider.dart';
import '../common/edit_field_page.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/conversation_provider.dart';

/// 聊天信息页（聊天页右上角 ··· 进入）：换头像 / 置顶 / 免打扰 / 清空记录
class ChatInfoPage extends ConsumerWidget {
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

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('聊天信息')),
      body: ListView(
        children: [
          // 成员区：头像 + 昵称（点头像换头像）
          Material(
            color: Colors.white,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (contact != null)
                    GestureDetector(
                      onTap: () => _changeAvatar(context, ref, contact),
                      child: Column(
                        children: [
                          AppAvatar(contact: contact, size: 56),
                          const SizedBox(height: 6),
                          Text(
                            contact.displayName,
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(width: 20),
                  // 添加成员占位（仿微信 + 号格）
                  Column(
                    children: [
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          border: Border.all(color: AppColors.divider),
                          borderRadius:
                              BorderRadius.circular(AppDimens.avatarRadius),
                        ),
                        child: const Icon(Icons.add,
                            color: AppColors.textSecondary, size: 30),
                      ),
                      const SizedBox(height: 6),
                      const Text('',
                          style: TextStyle(
                              fontSize: 13, color: AppColors.textSecondary)),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(left: 16, top: 6, bottom: 12),
            child: Text('点击头像可更换',
                style:
                    TextStyle(fontSize: 12, color: AppColors.textSecondary)),
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
                    title:
                        const Text('消息免打扰', style: TextStyle(fontSize: 16)),
                    value: conversation.muted,
                    activeTrackColor: AppColors.primary,
                    onChanged: (v) => ref
                        .read(conversationListProvider.notifier)
                        .setFlag(conversationId, muted: v),
                  ),
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
                    title: const Text('设置备注和标签',
                        style: TextStyle(fontSize: 16)),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          contact.remark ?? '',
                          style: const TextStyle(
                              fontSize: 15, color: AppColors.textSecondary),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.chevron_right,
                            color: AppColors.textSecondary),
                      ],
                    ),
                    onTap: () => _editRemark(context, ref, contact),
                  ),
                const Divider(indent: 16, height: 1),
                ListTile(
                  title: const Text('查找聊天记录',
                      style: TextStyle(fontSize: 16)),
                  trailing: const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                  onTap: () => _todo(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.white,
            child: ListTile(
              title: const Center(
                child: Text('清空聊天记录',
                    style: TextStyle(fontSize: 16, color: Colors.red)),
              ),
              onTap: () => _clearHistory(context, ref),
            ),
          ),
        ],
      ),
    );
  }

  /// 设置备注：空内容 = 清除备注恢复原名
  Future<void> _editRemark(
      BuildContext context, WidgetRef ref, Contact contact) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldPage(
          title: '备注',
          initial: contact.remark ?? '',
          hint: '输入备注名，留空恢复原名',
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
      builder: (dialogContext) => AlertDialog(
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
    await ref
        .read(messageRepositoryProvider)
        .clearConversation(conversationId);
    ref.invalidate(chatMessagesProvider(conversationId));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('已清空'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _todo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('功能开发中'), duration: Duration(seconds: 1)),
    );
  }
}
