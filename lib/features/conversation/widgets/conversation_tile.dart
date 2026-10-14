import 'package:flutter/material.dart';

import '../../../core/constants.dart';
import '../../../core/utils/time_utils.dart';
import '../../../core/widgets/app_avatar.dart';
import '../../../models/conversation.dart';

/// 会话列表行：头像 + 未读角标 / 昵称 / 最新摘要 / 时间 / 免打扰
class ConversationTile extends StatelessWidget {
  final Conversation conversation;
  final VoidCallback onTap;

  /// 宽屏布局下当前打开的会话：整行绿色高亮（仿微信 PC）
  final bool selected;

  const ConversationTile({
    super.key,
    required this.conversation,
    required this.onTap,
    this.selected = false,
  });

  Widget _avatarWithBadge() {
    final avatar = AppAvatar(contact: conversation.contact);
    final unread = conversation.unreadCount;
    if (unread <= 0) return avatar;

    // 免打扰会话：只显示小红点，不显示数字
    if (conversation.muted) {
      return Badge(
        smallSize: 9,
        backgroundColor: AppColors.badge,
        child: avatar,
      );
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
    final desktop =
        MediaQuery.sizeOf(context).width >= AppDimens.desktopBreakpoint;
    final nameColor = AppColors.ink;
    final subColor = AppColors.textSecondary;

    final row = Container(
      height: desktop ? 72 : 72,
      color: desktop
          ? selected
                ? AppColors.desktopSelected
                : AppColors.desktopList
          : conversation.pinned
          ? const Color(0xFFEDEDED)
          : Colors.white,
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 12 : 13,
        vertical: desktop ? 10 : 10,
      ),
      child: Row(
        children: [
          SizedBox(
            width: desktop ? 44 : 48,
            height: desktop ? 44 : 48,
            child: _avatarWithBadge(),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  conversation.contact.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: desktop ? 14 : 16,
                    color: nameColor,
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  conversation.lastMessage,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: desktop ? 12 : 13,
                    color: subColor,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 5),
          Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                TimeUtils.formatConversationTime(conversation.lastMessageTime),
                style: TextStyle(fontSize: desktop ? 10 : 11, color: subColor),
              ),
              const SizedBox(height: 7),
              if (conversation.muted)
                Icon(Icons.volume_off_outlined, size: 14, color: subColor)
              else
                const SizedBox(height: 14),
            ],
          ),
        ],
      ),
    );
    return InkWell(onTap: onTap, child: row);
  }
}
