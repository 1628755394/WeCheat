import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../models/conversation.dart';

/// 会话列表卡片：头像 + 未读角标 / 昵称 / 最新摘要 / 时间 / 免打扰
class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
  });

  Widget _avatarWithBadge() {
    final avatar = AppAvatar(contact: conversation.contact);
    final unread = conversation.unreadCount;
    if (unread <= 0) return avatar;

    // 免打扰会话：只显示小红点，不显示数字
    if (conversation.muted) {
      return Badge(smallSize: 9, backgroundColor: AppColors.badge, child: avatar);
    }
    return Badge.count(
      count: unread,
      maxCount: 99,
      backgroundColor: AppColors.badge,
      textColor: Colors.white,
      child: avatar,
    );
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: conversation.pinned ? AppColors.pinnedBg : Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            _avatarWithBadge(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    conversation.contact.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 16.5,
                      color: Colors.black87,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    conversation.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  TimeUtils.formatConversationTime(
                      conversation.lastMessageTime),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                if (conversation.muted)
                  const Icon(Icons.volume_off,
                      size: 16, color: AppColors.textSecondary)
                else
                  const SizedBox(height: 16),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
