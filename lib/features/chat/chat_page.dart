import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/utils/time_utils.dart';
import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/user_provider.dart';
import '../../repositories/mock_data.dart';

/// 聊天页：消息气泡 + 时间分组 + 输入框 + AI 流式回复
class ChatPage extends ConsumerStatefulWidget {
  final String conversationId;

  const ChatPage({super.key, required this.conversationId});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  bool _hasText = false;
  bool _nearBottom = true;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final pos = _scrollController.position;
      _nearBottom = pos.maxScrollExtent - pos.pixels < 120;
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _send() {
    if (_inputController.text.trim().isEmpty) return;
    ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .send(_inputController.text);
    _inputController.clear();
    setState(() {
      _hasText = false;
      _nearBottom = true;
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// 输入栏 + 号面板：相册/拍摄/语音通话/视频通话等
  void _showAddPanel() {
    FocusScope.of(context).unfocus();
    showModalBottomSheet(
      context: context,
      backgroundColor: AppColors.navBarBg,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            mainAxisSpacing: 20,
            children: [
              _PanelItem(icon: Icons.photo, label: '相册', onTap: () => _todo(sheetContext)),
              _PanelItem(icon: Icons.photo_camera, label: '拍摄', onTap: () => _todo(sheetContext)),
              _PanelItem(
                icon: Icons.call,
                label: '语音通话',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/call/${widget.conversationId}?video=0');
                },
              ),
              _PanelItem(
                icon: Icons.videocam,
                label: '视频通话',
                onTap: () {
                  Navigator.pop(sheetContext);
                  context.push('/call/${widget.conversationId}?video=1');
                },
              ),
              _PanelItem(icon: Icons.location_on, label: '位置', onTap: () => _todo(sheetContext)),
              _PanelItem(icon: Icons.card_giftcard, label: '红包', onTap: () => _todo(sheetContext)),
              _PanelItem(icon: Icons.person_pin, label: '名片', onTap: () => _todo(sheetContext)),
              _PanelItem(icon: Icons.folder, label: '文件', onTap: () => _todo(sheetContext)),
            ],
          ),
        ),
      ),
    );
  }

  void _todo(BuildContext context) {
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('功能开发中'), duration: Duration(seconds: 1)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final conversation = ref
        .watch(resolvedConversationListProvider)
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final chatAsync = ref.watch(chatMessagesProvider(widget.conversationId));

    // 新消息到达必滚到底；流式更新中仅在用户本就在底部时跟随
    ref.listen(chatMessagesProvider(widget.conversationId), (prev, next) {
      final prevCount = prev?.value?.messages.length ?? 0;
      final nextCount = next.value?.messages.length ?? 0;
      if (nextCount > prevCount || _nearBottom) _scrollToBottom();
    });

    final generating = chatAsync.value?.generating ?? false;
    final isAi = conversation?.contact.isAi ?? false;
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.chatBg,
      appBar: AppBar(
        title: Text(
          generating && isAi ? '对方正在输入…' : (conversation?.contact.displayName ?? '聊天'),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.more_horiz),
            onPressed: () =>
                context.push('/chat/${widget.conversationId}/info'),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () => FocusScope.of(context).unfocus(),
              child: chatAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(child: Text('加载失败：$e')),
                data: (state) => state.messages.isEmpty
                    ? const Center(
                        child: Text('暂无消息',
                            style: TextStyle(color: AppColors.textSecondary)))
                    : _MessageList(
                        messages: state.messages,
                        conversation: conversation,
                        generating: state.generating,
                        scrollController: _scrollController,
                        me: me,
                      ),
              ),
            ),
          ),
          _InputBar(
            controller: _inputController,
            hasText: _hasText,
            onChanged: (v) => setState(() => _hasText = v.trim().isNotEmpty),
            onSend: _send,
            onAdd: _showAddPanel,
          ),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<Message> messages;
  final Conversation? conversation;
  final bool generating;
  final ScrollController scrollController;
  final Contact me;

  const _MessageList({
    required this.messages,
    required this.conversation,
    required this.generating,
    required this.scrollController,
    required this.me,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scrollController,
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: messages.length,
      itemBuilder: (context, index) {
        final msg = messages[index];
        final showTime = index == 0 ||
            msg.createdAt
                    .difference(messages[index - 1].createdAt)
                    .inMinutes
                    .abs() >=
                5;
        final streaming =
            generating && index == messages.length - 1 && !msg.isMe;
        return Column(
          children: [
            if (showTime) _TimeLabel(time: msg.createdAt),
            _MessageRow(
              message: msg,
              conversation: conversation,
              streaming: streaming,
              me: me,
            ),
          ],
        );
      },
    );
  }
}

class _TimeLabel extends StatelessWidget {
  final DateTime time;

  const _TimeLabel({required this.time});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(
        TimeUtils.formatMessageGroupTime(time),
        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
      ),
    );
  }
}

class _MessageRow extends StatelessWidget {
  final Message message;
  final Conversation? conversation;
  final bool streaming;
  final Contact me;

  const _MessageRow({
    required this.message,
    required this.conversation,
    required this.streaming,
    required this.me,
  });

  @override
  Widget build(BuildContext context) {
    final bubble = Flexible(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: message.isMe ? AppColors.bubbleMe : Colors.white,
          borderRadius: BorderRadius.circular(5),
        ),
        child: streaming && message.content.isEmpty
            ? const _TypingDots()
            : Text(message.content,
                style: const TextStyle(fontSize: 16, height: 1.4)),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment:
            message.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: message.isMe
            ? [
                bubble,
                const SizedBox(width: 8),
                AppAvatar(contact: me, size: 40),
              ]
            : [
                AppAvatar(
                    contact: conversation?.contact ?? MockData.aiAssistant,
                    size: 40),
                const SizedBox(width: 8),
                bubble,
              ],
      ),
    );
  }
}

/// AI 生成中的三点动画
class _TypingDots extends StatefulWidget {
  const _TypingDots();

  @override
  State<_TypingDots> createState() => _TypingDotsState();
}

class _TypingDotsState extends State<_TypingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2),
              child: Opacity(
                opacity: 0.25 +
                    0.75 *
                        (0.5 +
                            0.5 *
                                math.sin(
                                    2 * math.pi * (_controller.value - i * 0.2))),
                child: const _Dot(),
              ),
            ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 7,
      height: 7,
      decoration: const BoxDecoration(
        color: AppColors.textSecondary,
        shape: BoxShape.circle,
      ),
    );
  }
}

/// + 号面板格子
class _PanelItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _PanelItem({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 28, color: Colors.black87),
          ),
          const SizedBox(height: 6),
          Text(label,
              style:
                  const TextStyle(fontSize: 12, color: AppColors.textSecondary)),
        ],
      ),
    );
  }
}

/// 底部输入栏：语音/表情/加号面板 + 输入框 + 发送按钮
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAdd;

  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.onChanged,
    required this.onSend,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        color: AppColors.navBarBg,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            IconButton(
              icon: const Icon(Icons.mic_none, size: 26),
              onPressed: () {},
            ),
            Expanded(
              child: Focus(
                // 桌面/Web 上 Enter 发送，Shift+Enter 换行
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      event.logicalKey == LogicalKeyboardKey.enter &&
                      !HardwareKeyboard.instance.isShiftPressed) {
                    onSend();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 5,
                    onChanged: onChanged,
                    decoration: const InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.emoji_emotions_outlined, size: 26),
              onPressed: () {},
            ),
            if (hasText)
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    minimumSize: const Size(56, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6)),
                  ),
                  onPressed: onSend,
                  child: const Text('发送'),
                ),
              )
            else
              IconButton(
                icon: const Icon(Icons.add_circle_outline, size: 26),
                onPressed: onAdd,
              ),
          ],
        ),
      ),
    );
  }
}
