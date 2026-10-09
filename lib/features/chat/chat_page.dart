import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/utils/time_utils.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/output_mode_button.dart';
import '../../providers/output_mode_provider.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../providers/chat_provider.dart';
import '../../providers/contact_override_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/user_provider.dart';
import '../../repositories/mock_data.dart';
import '../../services/voice_recorder.dart';
import '../conversation/conversation_page.dart';
import '../home/side_rail.dart';
import 'my_persona_page.dart';

/// 聊天路由入口：窄屏直接聊天页；宽屏 = PC 三栏（导航栏 + 会话列表 + 聊天区）
class ResponsiveChatPage extends StatelessWidget {
  final String conversationId;

  const ResponsiveChatPage({super.key, required this.conversationId});

  static const _tabPaths = ['/conversation', '/contact', '/discover', '/mine'];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < AppDimens.desktopBreakpoint) {
          return ChatPage(conversationId: conversationId);
        }
        return Scaffold(
          body: Row(
            children: [
              SideRail(
                selectedIndex: 0,
                onSelect: (i) => context.go(_tabPaths[i]),
              ),
              const VerticalDivider(width: 0.5, color: AppColors.divider),
              SizedBox(
                width: AppDimens.listPaneWidth,
                child: ConversationListPane(selectedId: conversationId),
              ),
              const VerticalDivider(width: 0.5, color: AppColors.divider),
              Expanded(child: ChatPage(conversationId: conversationId)),
            ],
          ),
        );
      },
    );
  }
}

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
  final _recorder = VoiceRecorderImpl();
  final _recordWatch = Stopwatch();
  bool _hasText = false;
  bool _nearBottom = true;
  bool _showEmoji = false;
  bool _recording = false;
  bool _voiceMode = false;
  final Set<String> _transcribingVoiceIds = {};
  List<String> _suggestions = const [];
  bool _suggesting = false;
  Message? _quoted;

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
    if (ChatMessages.audibleConversationId == widget.conversationId) {
      ChatMessages.audibleConversationId = null;
    }
    _inputController.dispose();
    _scrollController.dispose();
    _recorder.dispose();
    super.dispose();
  }

  void _send() {
    if (_inputController.text.trim().isEmpty) return;
    final quoted = _quoted;
    ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .send(
          _inputController.text,
          quoteText: quoted == null ? '' : _quoteTextOf(quoted),
          quoteSender: quoted == null ? '' : _senderNameOf(quoted),
        );
    _inputController.clear();
    setState(() {
      _hasText = false;
      _nearBottom = true;
      _quoted = null;
    });
    _scrollToBottom();
  }

  /// 被引用消息的发送者名（群聊按 senderId 找成员）
  String _senderNameOf(Message m) {
    if (m.isMe) return '我';
    final conv = ref
        .read(resolvedConversationListProvider)
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    if (conv == null) return '对方';
    for (final member in conv.members) {
      if (member.id == m.senderId) return member.displayName;
    }
    return conv.contact.displayName;
  }

  /// 被引用消息的摘要文本（图片/语音等显示占位）
  String _quoteTextOf(Message m) {
    switch (m.type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.voice:
        return m.content.trim().isEmpty ? '[语音]' : '语音：${m.content}';
      case MessageType.location:
        return '[位置] ${m.content.split('|').first}';
      case MessageType.redPacket:
        return '[红包] ${m.content.split('|').first}';
      case MessageType.transfer:
        return '[转账] ¥${m.content}';
      case MessageType.gift:
        return '[礼物] ${m.content}';
      case MessageType.contact:
        return '[名片] ${m.content.split('|').last}';
      case MessageType.file:
        return '[文件] ${m.content.split('|').first}';
      case MessageType.system:
      case MessageType.text:
        return m.content;
    }
  }

  /// 长按消息：复制 / 转发 / 标记记忆 / 朗读 / 撤回 / 删除
  void _onMessageLongPress(Message message) {
    if (message.recalled) return;
    final conversation = ref
        .read(resolvedConversationListProvider)
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final isAiConv =
        (conversation?.contact.isAi ?? false) ||
        (conversation?.contact.isGroup ?? false);
    final notifier = ref.read(
      chatMessagesProvider(widget.conversationId).notifier,
    );
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (message.type == MessageType.text)
              ListTile(
                leading: const Icon(Icons.copy),
                title: const Text('复制'),
                onTap: () {
                  Clipboard.setData(ClipboardData(text: message.content));
                  Navigator.pop(ctx);
                },
              ),
            ListTile(
              leading: const Icon(Icons.format_quote),
              title: const Text('引用'),
              onTap: () {
                Navigator.pop(ctx);
                setState(() => _quoted = message);
              },
            ),
            ListTile(
              leading: const Icon(Icons.shortcut),
              title: const Text('转发'),
              onTap: () {
                Navigator.pop(ctx);
                _forwardMessage(message);
              },
            ),
            if (isAiConv && message.type == MessageType.text)
              ListTile(
                leading: Icon(
                  message.isMemory ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                title: Text(message.isMemory ? '取消记忆标记' : '标记为记忆'),
                subtitle: const Text(
                  '重点记忆会永久进入该 AI 的上下文，不再遗忘',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.toggleMemory(message.id);
                },
              ),
            if (isAiConv && !message.isMe)
              ListTile(
                leading: const Icon(Icons.volume_up),
                title: const Text('朗读'),
                subtitle: const Text(
                  '用该 AI 导入的音色播放；未导入则用系统语音',
                  style: TextStyle(fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.speakMessage(message.id);
                },
              ),
            if (message.isMe)
              ListTile(
                leading: const Icon(Icons.undo),
                title: const Text('撤回'),
                onTap: () {
                  Navigator.pop(ctx);
                  notifier.recallMessage(message.id);
                },
              ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('删除', style: TextStyle(color: Colors.red)),
              onTap: () {
                Navigator.pop(ctx);
                notifier.deleteMessage(message.id);
              },
            ),
          ],
        ),
      ),
    );
  }

  /// 转发：选一个会话，把消息原样发过去
  Future<void> _forwardMessage(Message message) async {
    final list = await ref.read(conversationListProvider.future);
    if (!mounted) return;
    final target = await showModalBottomSheet<Conversation>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '转发到',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in list)
                    if (c.id != widget.conversationId)
                      ListTile(
                        leading: AppAvatar(contact: c.contact, size: 40),
                        title: Text(c.contact.displayName),
                        onTap: () => Navigator.pop(ctx, c),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (target == null || !mounted) return;
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .forwardMessage(message.id, target.id);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已转发给 ${target.contact.displayName}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
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
              _PanelItem(
                icon: Icons.photo,
                label: '相册',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndSendImage(ImageSource.gallery);
                },
              ),
              _PanelItem(
                icon: Icons.photo_camera,
                label: '拍摄',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _pickAndSendImage(ImageSource.camera);
                },
              ),
              _PanelItem(
                icon: Icons.call,
                label: '语音通话',
                onTap: () => _startCall(sheetContext, video: false),
              ),
              _PanelItem(
                icon: Icons.videocam,
                label: '视频通话',
                onTap: () => _startCall(sheetContext, video: true),
              ),
              _PanelItem(
                icon: Icons.record_voice_over,
                label: '语音消息',
                onTap: () {
                  // 仅 AI 会话可用：让对方用克隆音色发一条语音
                  if (!_isAi && !_isGroup) {
                    Navigator.pop(sheetContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('仅 AI 会话可请求语音消息'),
                        duration: Duration(seconds: 1),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(sheetContext);
                  ref
                      .read(
                        chatMessagesProvider(widget.conversationId).notifier,
                      )
                      .requestVoiceReply();
                },
              ),
              _PanelItem(
                icon: Icons.location_on,
                label: '位置',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendLocation();
                },
              ),
              _PanelItem(
                icon: Icons.card_giftcard,
                label: '红包',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendRedPacket();
                },
              ),
              _PanelItem(
                icon: Icons.currency_exchange,
                label: '转账',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendTransfer();
                },
              ),
              _PanelItem(
                icon: Icons.redeem,
                label: '礼物',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendGift();
                },
              ),
              _PanelItem(
                icon: Icons.person_pin,
                label: '名片',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendContactCard();
                },
              ),
              _PanelItem(
                icon: Icons.audio_file,
                label: '文件/语音',
                onTap: () {
                  Navigator.pop(sheetContext);
                  _sendFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _transcribeVoice(String messageId) async {
    if (!_transcribingVoiceIds.add(messageId)) return;
    setState(() {});
    try {
      final text = await ref
          .read(chatMessagesProvider(widget.conversationId).notifier)
          .transcribeVoice(messageId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(text == null || text.isEmpty ? '未识别出语音内容' : '已转为文字'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('转写失败，请检查本地 Whisper 服务、接口地址和 CORS')),
      );
    } finally {
      if (mounted) setState(() => _transcribingVoiceIds.remove(messageId));
    }
  }

  /// 按住说话：开始录音
  Future<void> _micStart() async {
    if (_recording) return;
    final ok = await _recorder.start();
    if (!ok) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('无法录音：请检查麦克风权限'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }
    _recordWatch
      ..reset()
      ..start();
    setState(() => _recording = true);
  }

  /// 松手：停止录音，≥1 秒才发成语音消息
  Future<void> _micEnd() async {
    if (!_recording) return;
    setState(() => _recording = false);
    _recordWatch.stop();
    final bytes = await _recorder.stop();
    if (!mounted) return;
    if (bytes == null || _recordWatch.elapsedMilliseconds < 800) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('说话时间太短'), duration: Duration(seconds: 1)),
      );
      return;
    }
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendRich(
          type: MessageType.voice,
          content: '',
          audioBytes: bytes,
          audioFileName: kIsWeb ? 'recording.webm' : 'recording.m4a',
          replyHint: '[发来一条语音消息]',
        );
    _scrollToBottom();
  }

  /// ✨ 智能回复建议：AI 生成 3 条候选回复，点选直接发送
  Future<void> _suggest() async {
    if (_suggesting) return;
    setState(() {
      _suggesting = true;
      _suggestions = const [];
    });
    final list = await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .suggestReplies();
    if (mounted) {
      setState(() {
        _suggesting = false;
        _suggestions = list;
      });
    }
  }

  void _sendSuggestion(String text) {
    setState(() => _suggestions = const []);
    ref.read(chatMessagesProvider(widget.conversationId).notifier).send(text);
    _scrollToBottom();
  }

  void _insertEmoji(String emoji) {
    final sel = _inputController.selection;
    final text = _inputController.text;
    final pos = sel.isValid && sel.start >= 0 ? sel.start : text.length;
    final next = text.substring(0, pos) + emoji + text.substring(pos);
    _inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: pos + emoji.length),
    );
    setState(() => _hasText = next.trim().isNotEmpty);
  }

  /// 相册/拍摄 → 图片消息（字节存 Hive，桌面/Web 通用）
  Future<void> _pickAndSendImage(ImageSource source) async {
    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        maxWidth: 1600,
        imageQuality: 80,
      );
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await ref
          .read(chatMessagesProvider(widget.conversationId).notifier)
          .sendRich(
            type: MessageType.image,
            content: '',
            mediaBytes: bytes,
            replyHint: '[发来一张图片]',
          );
      _scrollToBottom();
    } catch (_) {}
  }

  /// 位置消息：Mock 一个当前位置（接真定位需要平台插件+权限）
  Future<void> _sendLocation() async {
    const spots = [
      ('人民广场', '上海市黄浦区人民大道100号'),
      ('世纪公园', '上海市浦东新区锦绣路1001号'),
      ('外滩', '上海市黄浦区中山东一路'),
      ('陆家嘴中心绿地', '上海市浦东新区陆家嘴环路717号'),
    ];
    final picked = await showModalBottomSheet<(String, String)>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '发送位置',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final s in spots)
              ListTile(
                leading: const Icon(Icons.location_on, color: Colors.red),
                title: Text(s.$1),
                subtitle: Text(s.$2, style: const TextStyle(fontSize: 12)),
                onTap: () => Navigator.pop(ctx, s),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendRich(
          type: MessageType.location,
          content: '${picked.$1}|${picked.$2}',
          replyHint: '[发来位置：${picked.$1}]',
        );
    _scrollToBottom();
  }

  /// 红包：输入金额/祝福语 → 红色卡片气泡
  Future<void> _sendRedPacket() async {
    final amountCtl = TextEditingController(text: '8.88');
    final wishCtl = TextEditingController(text: '恭喜发财，大吉大利');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('发红包'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: wishCtl,
              decoration: const InputDecoration(labelText: '祝福语'),
            ),
            TextField(
              controller: amountCtl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: '金额（元）'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('塞钱进红包'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(amountCtl.text) ?? 8.88;
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendRich(
          type: MessageType.redPacket,
          content: '${wishCtl.text.trim()}|${amount.toStringAsFixed(2)}',
          replyHint: '[发来一个红包]',
        );
    _scrollToBottom();
  }

  /// 转账：输入金额 → 橙色卡片气泡；好感度 <30 时可挽回
  Future<void> _sendTransfer() async {
    final amountCtl = TextEditingController(text: '52.00');
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('转账'),
        content: TextField(
          controller: amountCtl,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: '金额（元）',
            prefixText: '¥',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('转账'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final amount = double.tryParse(amountCtl.text) ?? 52.0;
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendRich(
          type: MessageType.transfer,
          content: amount.toStringAsFixed(2),
          replyHint: '[给你转账 ¥${amount.toStringAsFixed(2)}]',
        );
    _scrollToBottom();
  }

  /// 送礼：选一件礼物送出去；好感度 <30 时可挽回
  Future<void> _sendGift() async {
    const gifts = [
      ('奶茶', '🧋'),
      ('花束', '💐'),
      ('口红', '💄'),
      ('球鞋', '👟'),
      ('手办', '🎎'),
      ('蛋糕', '🎂'),
      ('围巾', '🧣'),
      ('游戏机', '🎮'),
    ];
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GridView.count(
            crossAxisCount: 4,
            shrinkWrap: true,
            children: [
              for (final g in gifts)
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => Navigator.pop(ctx, g.$1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(g.$2, style: const TextStyle(fontSize: 30)),
                      const SizedBox(height: 4),
                      Text(g.$1, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null) return;
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendRich(
          type: MessageType.gift,
          content: picked,
          replyHint: '[送来一份礼物：$picked]',
        );
    _scrollToBottom();
  }

  /// 名片：从联系人里选一个发出去
  Future<void> _sendContactCard() async {
    final overrides = ref.read(contactOverridesProvider);
    final contacts = [
      for (final c in MockData.contacts)
        if (!c.isGroup) resolveContact(overrides, c),
      for (final conv
          in ref.read(resolvedConversationListProvider).value ?? const [])
        if (!conv.contact.isGroup && conv.contact.id != _conversationContactId)
          conv.contact,
    ];
    // 去重
    final seen = <String>{};
    contacts.retainWhere((c) => seen.add(c.id));
    if (!mounted) return;
    final picked = await showModalBottomSheet<Contact>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '发送名片',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final c in contacts)
                    ListTile(
                      leading: AppAvatar(contact: c, size: 40),
                      title: Text(c.displayName),
                      onTap: () => Navigator.pop(ctx, c),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    await ref
        .read(chatMessagesProvider(widget.conversationId).notifier)
        .sendRich(
          type: MessageType.contact,
          content: '${picked.id}|${picked.displayName}',
          replyHint: '[发来名片：${picked.displayName}]',
        );
    _scrollToBottom();
  }

  /// 导入音频发送为语音气泡，其他文件仍发送文件卡片
  Future<void> _sendFile() async {
    try {
      final result = await FilePicker.pickFiles();
      if (!mounted) return;
      if (result.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('没有选择文件')));
        return;
      }
      final file = result.first;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      if (bytes.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件内容为空，无法发送')));
        return;
      }
      const audioExtensions = {
        '3g2',
        '3gp',
        '3gpp',
        'aac',
        'aiff',
        'amr',
        'caf',
        'flac',
        'm4a',
        'm4b',
        'mka',
        'mp3',
        'mpga',
        'oga',
        'ogg',
        'opus',
        'wav',
        'weba',
        'webm',
        'wma',
      };
      final isAudio = audioExtensions.contains(file.extension?.toLowerCase());
      await ref
          .read(chatMessagesProvider(widget.conversationId).notifier)
          .sendRich(
            type: isAudio ? MessageType.voice : MessageType.file,
            content: isAudio ? '' : '${file.name}|${bytes.length}',
            audioBytes: isAudio ? bytes : null,
            audioFileName: isAudio ? file.name : '',
            mediaBytes: isAudio ? null : bytes,
            replyHint: isAudio ? '[发来一条语音消息]' : '[发来文件：${file.name}]',
          );
      _scrollToBottom();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isAudio ? '语音消息已发送，点击气泡播放' : '文件已发送'),
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('文件导入失败，请重试')));
      }
    }
  }

  /// 通话入口：单聊直接打；群聊先选成员（打给她的单聊会话）
  void _startCall(BuildContext sheetContext, {required bool video}) {
    if (!_isGroup) {
      Navigator.pop(sheetContext);
      context.push('/call/${widget.conversationId}?video=${video ? 1 : 0}');
      return;
    }
    final conv = ref
        .read(resolvedConversationListProvider)
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final members = [
      for (final m in conv?.members ?? const <Contact>[])
        if (m.isAi) m,
    ];
    Navigator.pop(sheetContext);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                '选择通话成员',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
            ),
            for (final m in members)
              ListTile(
                leading: AppAvatar(contact: m, size: 40),
                title: Text(m.displayName),
                onTap: () {
                  Navigator.pop(ctx);
                  final convId = _oneOnOneConvId(m);
                  if (convId != null) {
                    context.push('/call/$convId?video=${video ? 1 : 0}');
                  }
                },
              ),
          ],
        ),
      ),
    );
  }

  /// 成员 → 其单聊会话 id（通话/资料共享用）
  String? _oneOnOneConvId(Contact member) {
    for (final c in ref.read(conversationListProvider).value ?? const []) {
      if (!c.contact.isGroup && c.contact.id == member.id) return c.id;
    }
    return null;
  }

  String? get _conversationContactId => ref
      .read(resolvedConversationListProvider)
      .value
      ?.where((c) => c.id == widget.conversationId)
      .firstOrNull
      ?.contact
      .id;

  bool get _isAi =>
      ref
          .read(resolvedConversationListProvider)
          .value
          ?.where((c) => c.id == widget.conversationId)
          .firstOrNull
          ?.contact
          .isAi ??
      false;

  bool get _isGroup =>
      ref
          .read(resolvedConversationListProvider)
          .value
          ?.where((c) => c.id == widget.conversationId)
          .firstOrNull
          ?.contact
          .isGroup ??
      false;

  @override
  Widget build(BuildContext context) {
    final conversation = ref
        .watch(resolvedConversationListProvider)
        .value
        ?.where((c) => c.id == widget.conversationId)
        .firstOrNull;
    final chatAsync = ref.watch(chatMessagesProvider(widget.conversationId));
    final chatBackground = ref.watch(
      chatBackgroundProvider(widget.conversationId),
    );
    final chatAreaDecoration = BoxDecoration(
      color: chatBackground.imageBytes == null
          ? (chatBackground.colorValue == null
                ? AppColors.chatBg
                : Color(chatBackground.colorValue!))
          : null,
      image: chatBackground.imageBytes == null
          ? null
          : DecorationImage(
              image: MemoryImage(chatBackground.imageBytes!),
              fit: BoxFit.cover,
            ),
    );

    // 新消息到达必滚到底；流式更新中仅在用户本就在底部时跟随
    ref.listen(chatMessagesProvider(widget.conversationId), (prev, next) {
      final prevCount = prev?.value?.messages.length ?? 0;
      final nextCount = next.value?.messages.length ?? 0;
      if (nextCount > prevCount || _nearBottom) _scrollToBottom();
    });
    ref.listen(outputModeProvider, (previous, next) {
      if (!next.speaks) {
        ref
            .read(chatMessagesProvider(widget.conversationId).notifier)
            .stopPlayback();
      }
    });

    if (ModalRoute.of(context)?.isCurrent ?? true) {
      ChatMessages.audibleConversationId = widget.conversationId;
    } else if (ChatMessages.audibleConversationId == widget.conversationId) {
      ChatMessages.audibleConversationId = null;
      ref
          .read(chatMessagesProvider(widget.conversationId).notifier)
          .stopPlayback();
    }

    final generating = chatAsync.value?.generating ?? false;
    final speaker = chatAsync.value?.speakerName;
    final contact = conversation?.contact;
    final isAi = contact?.isAi ?? false;
    final isGroup = contact?.isGroup ?? false;
    final me = ref.watch(currentUserProvider);

    // 群聊标题带人数；生成中显示「xx 正在输入…」
    final baseTitle = contact == null
        ? '聊天'
        : isGroup && conversation!.members.isNotEmpty
        ? '${contact.displayName}(${conversation.members.length + 1})'
        : contact.displayName;
    // 生成中：单聊显示「对方正在输入…」，群聊显示具体成员名
    final title = generating && (isAi || isGroup)
        ? (isGroup && (speaker?.isNotEmpty ?? false)
              ? '$speaker 正在输入…'
              : '对方正在输入…')
        : baseTitle;

    return Scaffold(
      backgroundColor: AppColors.chatBg,
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          const OutputModeButton(),
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
            child: Container(
              decoration: chatAreaDecoration,
              child: GestureDetector(
                onTap: () => FocusScope.of(context).unfocus(),
                child: chatAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text('加载失败：$e')),
                  data: (state) => state.messages.isEmpty
                      ? const Center(
                          child: Text(
                            '暂无消息',
                            style: TextStyle(color: AppColors.textSecondary),
                          ),
                        )
                      : _MessageList(
                          messages: state.messages,
                          conversation: conversation,
                          generating: state.generating,
                          transcribingVoiceIds: _transcribingVoiceIds,
                          scrollController: _scrollController,
                          me: me,
                          onRegenerate: (id) => ref
                              .read(
                                chatMessagesProvider(widget.conversationId)
                                    .notifier,
                              )
                              .regenerate(id),
                          onSwitchVariant: (id, d) => ref
                              .read(
                                chatMessagesProvider(widget.conversationId)
                                    .notifier,
                              )
                              .switchVariant(id, d),
                          onLongPress: _onMessageLongPress,
                          onPlayVoice: (id) => ref
                              .read(
                                chatMessagesProvider(widget.conversationId)
                                    .notifier,
                              )
                              .speakMessage(id),
                          onTranscribeVoice: _transcribeVoice,
                        ),
                ),
              ),
            ),
          ),
          // 引用预览条（微信式：输入框上方显示被引用内容）
          if (_quoted != null)
            Container(
              color: AppColors.navBarBg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  const Icon(
                    Icons.format_quote,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '引用 ${_senderNameOf(_quoted!)}：${_quoteTextOf(_quoted!)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => setState(() => _quoted = null),
                    child: const Icon(
                      Icons.close,
                      size: 18,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          // 智能回复建议 chips（✨ 生成）
          if (_suggesting || _suggestions.isNotEmpty)
            Container(
              color: AppColors.navBarBg,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: [
                  if (_suggesting)
                    const Padding(
                      padding: EdgeInsets.only(right: 8),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final s in _suggestions)
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: Text(
                                  s,
                                  style: const TextStyle(fontSize: 13),
                                ),
                                backgroundColor: Colors.white,
                                onPressed: () => _sendSuggestion(s),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  if (_suggestions.isNotEmpty)
                    GestureDetector(
                      onTap: () => setState(() => _suggestions = const []),
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: AppColors.textSecondary,
                      ),
                    ),
                ],
              ),
            ),
          _InputBar(
            controller: _inputController,
            hasText: _hasText,
            recording: _recording,
            voiceMode: _voiceMode,
            emojiOn: _showEmoji,
            onChanged: (v) => setState(() => _hasText = v.trim().isNotEmpty),
            onSend: _send,
            onAdd: _showAddPanel,
            onMicStart: _micStart,
            onMicEnd: _micEnd,
            onVoiceMode: () => setState(() => _voiceMode = !_voiceMode),
            onEmoji: () => setState(() => _showEmoji = !_showEmoji),
            onSuggest: _suggest,
          ),
          if (_showEmoji) _EmojiPanel(onPick: _insertEmoji),
        ],
      ),
    );
  }
}

class _MessageList extends StatelessWidget {
  final List<Message> messages;
  final Conversation? conversation;
  final bool generating;
  final Set<String> transcribingVoiceIds;
  final ScrollController scrollController;
  final Contact me;
  final void Function(String messageId) onRegenerate;
  final void Function(String messageId, int delta) onSwitchVariant;
  final void Function(Message message) onLongPress;
  final void Function(String messageId) onPlayVoice;
  final Future<void> Function(String messageId) onTranscribeVoice;

  const _MessageList({
    required this.messages,
    required this.conversation,
    required this.generating,
    required this.transcribingVoiceIds,
    required this.scrollController,
    required this.me,
    required this.onRegenerate,
    required this.onSwitchVariant,
    required this.onLongPress,
    required this.onPlayVoice,
    required this.onTranscribeVoice,
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
        final showTime =
            index == 0 ||
            msg.createdAt
                    .difference(messages[index - 1].createdAt)
                    .inMinutes
                    .abs() >=
                5;
        final streaming =
            generating && index == messages.length - 1 && !msg.isMe;
        // 最后一条 AI 文本消息才显示「换一换」控件
        final canRetry =
            !generating &&
            index == messages.length - 1 &&
            !msg.isMe &&
            msg.type == MessageType.text &&
            ((conversation?.contact.isAi ?? false) ||
                (conversation?.contact.isGroup ?? false));
        // 撤回消息渲染成居中的系统提示
        final recallLabel = msg.recalled
            ? (msg.isMe ? '你撤回了一条消息' : '对方撤回了一条消息')
            : null;
        return Column(
          children: [
            if (showTime) _TimeLabel(time: msg.createdAt),
            if (recallLabel != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  recallLabel,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              )
            else
              _MessageRow(
                message: msg,
                conversation: conversation,
                streaming: streaming,
                me: me,
                isTranscribingVoice: transcribingVoiceIds.contains(msg.id),
                showVariantBar: canRetry,
                onRegenerate: () => onRegenerate(msg.id),
                onSwitchVariant: (d) => onSwitchVariant(msg.id, d),
                onLongPress: () => onLongPress(msg),
                onPlayVoice: () => onPlayVoice(msg.id),
                onTranscribeVoice: () => onTranscribeVoice(msg.id),
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
  final bool isTranscribingVoice;

  /// 最后一条 AI 消息：气泡下方显示「换一换」+ 版本切换
  final bool showVariantBar;
  final VoidCallback? onRegenerate;
  final void Function(int delta)? onSwitchVariant;
  final VoidCallback? onLongPress;
  final VoidCallback? onPlayVoice;
  final VoidCallback? onTranscribeVoice;

  const _MessageRow({
    required this.message,
    required this.conversation,
    required this.streaming,
    required this.me,
    required this.isTranscribingVoice,
    this.showVariantBar = false,
    this.onRegenerate,
    this.onSwitchVariant,
    this.onLongPress,
    this.onPlayVoice,
    this.onTranscribeVoice,
  });

  @override
  Widget build(BuildContext context) {
    // 群聊里按 senderId 找出发言成员；找不到时回退会话头像
    Contact? sender;
    if (!message.isMe && (conversation?.contact.isGroup ?? false)) {
      for (final m in conversation!.members) {
        if (m.id == message.senderId) {
          sender = m;
          break;
        }
      }
    }
    final face = sender ?? conversation?.contact ?? MockData.aiAssistant;

    final bubble = Flexible(
      child: Column(
        crossAxisAlignment: message.isMe
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          // 群聊里在别人气泡上方显示昵称（仿微信）
          if (sender != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                sender.displayName,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              GestureDetector(
                onLongPress: onLongPress,
                onTap: message.type == MessageType.voice ? onPlayVoice : null,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: message.isMe ? AppColors.bubbleMe : Colors.white,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: streaming && message.content.isEmpty
                      ? const _TypingDots()
                      : _bubbleContent(context),
                ),
              ),
              // 记忆星标：被标记为重点记忆的消息右上角显示小星星
              if (message.isMemory)
                const Positioned(
                  top: -7,
                  right: -7,
                  child: Icon(Icons.star, size: 14, color: Colors.amber),
                ),
            ],
          ),
          // 「换一换」控件：左右箭头切版本 + 点击重生成（猫箱式）
          if (showVariantBar && !streaming)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _VariantArrow(
                    icon: Icons.chevron_left,
                    enabled: message.variantIndex > 0,
                    onTap: () => onSwitchVariant?.call(-1),
                  ),
                  GestureDetector(
                    onTap: onRegenerate,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                      child: Text(
                        '换一换',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  if (message.variants.length > 1)
                    Text(
                      '${message.variantIndex + 1}/${message.variants.length}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  _VariantArrow(
                    icon: Icons.chevron_right,
                    enabled: message.variantIndex < message.variants.length - 1,
                    onTap: () => onSwitchVariant?.call(1),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        mainAxisAlignment: message.isMe
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: message.isMe
            ? [
                bubble,
                const SizedBox(width: 8),
                // 点自己头像 →「我与 TA」：人设/关系/喜好词/厌恶词
                GestureDetector(
                  onTap: conversation == null
                      ? null
                      : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) =>
                                MyPersonaPage(conversationId: conversation!.id),
                          ),
                        ),
                  child: AppAvatar(contact: me, size: 40),
                ),
              ]
            : [
                AppAvatar(contact: face, size: 40),
                const SizedBox(width: 8),
                bubble,
              ],
      ),
    );
  }

  /// 按消息类型渲染气泡内容
  Widget _bubbleContent(BuildContext context) {
    switch (message.type) {
      case MessageType.voice:
        return _voiceBubble();
      case MessageType.image:
        return _imageBubble(context);
      case MessageType.location:
        return _locationBubble();
      case MessageType.redPacket:
        return _redPacketBubble(context);
      case MessageType.transfer:
        return _transferBubble(context);
      case MessageType.gift:
        return _giftBubble();
      case MessageType.contact:
        return _contactBubble();
      case MessageType.file:
        return _fileBubble();
      case MessageType.system:
      case MessageType.text:
        final body = Text.rich(
          TextSpan(
            style: const TextStyle(fontSize: 16, height: 1.4),
            children: _richSpans(message.content),
          ),
        );
        // 引用块：正文上方一行灰底引文（微信式）
        if (message.quoteText.isNotEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '${message.quoteSender}：${message.quoteText}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
              const SizedBox(height: 5),
              body,
            ],
          );
        }
        return body;
    }
  }

  /// 图片消息：缩略图 + 点击全屏预览
  Widget _imageBubble(BuildContext context) {
    final bytes = message.mediaBytes;
    if (bytes == null) return const Text('[图片]');
    return GestureDetector(
      onTap: () => showDialog(
        context: context,
        builder: (_) => Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.black,
          child: GestureDetector(
            onTap: () => Navigator.pop(context),
            child: InteractiveViewer(child: Image.memory(bytes)),
          ),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: Image.memory(bytes, width: 160, height: 160, fit: BoxFit.cover),
      ),
    );
  }

  /// 位置消息：地图钉卡片（content = 名称|地址）
  Widget _locationBubble() {
    final parts = message.content.split('|');
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.location_on, color: Colors.red, size: 28),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              parts.isNotEmpty ? parts[0] : '位置',
              style: const TextStyle(fontSize: 15),
            ),
            if (parts.length > 1)
              Text(
                parts[1],
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
          ],
        ),
      ],
    );
  }

  /// 红包卡片：红包皮样式 + 点击提示已领取（content = 祝福语|金额）
  Widget _redPacketBubble(BuildContext context) {
    final parts = message.content.split('|');
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已领取 ¥${parts.length > 1 ? parts[1] : '0.00'}'),
          duration: const Duration(seconds: 1),
        ),
      ),
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFA9D3B),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.card_giftcard, color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    parts.isNotEmpty && parts[0].isNotEmpty
                        ? parts[0]
                        : '恭喜发财，大吉大利',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const Text(
                    '微信红包',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 转账卡片：橙色卡片 + ¥金额 + 点击收款（content = 金额）
  Widget _transferBubble(BuildContext context) {
    return GestureDetector(
      onTap: () => ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已收款 ¥${message.content}'),
          duration: const Duration(seconds: 1),
        ),
      ),
      child: Container(
        width: 200,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFFA9D3B),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: [
            const Icon(Icons.currency_exchange, color: Colors.white, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '¥${message.content}',
                    style: const TextStyle(color: Colors.white, fontSize: 15),
                  ),
                  const Text(
                    '转账给你',
                    style: TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 礼物卡片：🎁 + 礼物名 + 粉色卡片（content = 礼物名）
  Widget _giftBubble() {
    return Container(
      width: 200,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFF6B81),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          const Icon(Icons.redeem, color: Colors.white, size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '送你一份${message.content}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 15),
                ),
                const Text(
                  '礼物',
                  style: TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 名片卡片：头像 + 名字（content = contactId|名字）
  Widget _contactBubble() {
    final parts = message.content.split('|');
    final name = parts.length > 1 ? parts[1] : '联系人';
    return Container(
      width: 200,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 18,
                child: Text(name.isEmpty ? '?' : name.characters.first),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 15),
                ),
              ),
            ],
          ),
          const Divider(height: 14),
          const Text(
            '个人名片',
            style: TextStyle(fontSize: 11, color: AppColors.textSecondary),
          ),
        ],
      ),
    );
  }

  /// 文件卡片：图标 + 文件名 + 大小（content = 文件名|字节数）
  Widget _fileBubble() {
    final parts = message.content.split('|');
    final name = parts.isNotEmpty ? parts[0] : '文件';
    final size = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
    String sizeText;
    if (size >= 1048576) {
      sizeText = '${(size / 1048576).toStringAsFixed(1)} MB';
    } else if (size >= 1024) {
      sizeText = '${(size / 1024).toStringAsFixed(1)} KB';
    } else {
      sizeText = '$size B';
    }
    return Container(
      width: 220,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: AppColors.divider),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.insert_drive_file,
            color: Color(0xFF3D8BFD),
            size: 34,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                Text(
                  sizeText,
                  style: const TextStyle(
                    fontSize: 11,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 语音消息气泡：喇叭 + 时长 + 文字稿，点击播放克隆音色
  Widget _voiceBubble() {
    final hasAudio = message.audioBytes != null;
    // 粗估时长：RIFF/WAV ≈32KB/s，AAC/m4a ≈16KB/s
    int seconds = 0;
    if (hasAudio) {
      final b = message.audioBytes!;
      final isWav = b.length > 12 && b[0] == 0x52 && b[1] == 0x49;
      seconds = (b.length / (isWav ? 32000 : 16000)).ceil();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasAudio ? Icons.volume_up : Icons.graphic_eq,
              size: 20,
              color: message.isMe ? Colors.black87 : AppColors.primary,
            ),
            const SizedBox(width: 8),
            Text(
              streaming
                  ? '语音合成中…'
                  : hasAudio
                  ? '语音 $seconds″'
                  : '语音（点击播放）',
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
        if (message.content.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              message.content,
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
                height: 1.4,
              ),
            ),
          )
        else if (hasAudio)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: TextButton.icon(
              onPressed: isTranscribingVoice ? null : onTranscribeVoice,
              icon: isTranscribingVoice
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.translate, size: 16),
              label: Text(isTranscribingVoice ? '转写中…' : '转文字'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 30),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                foregroundColor: AppColors.textSecondary,
              ),
            ),
          ),
      ],
    );
  }

  /// （动作/神态）段灰色小字渲染，猫箱式沉浸描写
  static List<TextSpan> _richSpans(String content) {
    final spans = <TextSpan>[];
    final reg = RegExp(r'[（(][^（）()\n]{1,60}[）)]');
    var last = 0;
    for (final m in reg.allMatches(content)) {
      if (m.start > last) {
        spans.add(TextSpan(text: content.substring(last, m.start)));
      }
      spans.add(
        TextSpan(
          text: m.group(0),
          style: const TextStyle(fontSize: 14, color: AppColors.textSecondary),
        ),
      );
      last = m.end;
    }
    if (last < content.length) {
      spans.add(TextSpan(text: content.substring(last)));
    }
    return spans;
  }
}

/// 「换一换」两侧的版本切换箭头
class _VariantArrow extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _VariantArrow({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(
          icon,
          size: 18,
          color: enabled ? Colors.black54 : AppColors.divider,
        ),
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
                opacity:
                    0.25 +
                    0.75 *
                        (0.5 +
                            0.5 *
                                math.sin(
                                  2 * math.pi * (_controller.value - i * 0.2),
                                )),
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
          Text(
            label,
            style: const TextStyle(
              fontSize: 12,
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部输入栏：语音/表情/加号面板 + 输入框 + 发送按钮
class _InputBar extends StatelessWidget {
  final TextEditingController controller;
  final bool hasText;
  final bool recording;
  final bool voiceMode;
  final bool emojiOn;
  final ValueChanged<String> onChanged;
  final VoidCallback onSend;
  final VoidCallback onAdd;
  final VoidCallback onMicStart;
  final VoidCallback onMicEnd;
  final VoidCallback onVoiceMode;
  final VoidCallback onEmoji;
  final VoidCallback onSuggest;

  const _InputBar({
    required this.controller,
    required this.hasText,
    required this.recording,
    required this.voiceMode,
    required this.emojiOn,
    required this.onChanged,
    required this.onSend,
    required this.onAdd,
    required this.onMicStart,
    required this.onMicEnd,
    required this.onVoiceMode,
    required this.onEmoji,
    required this.onSuggest,
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
              icon: Icon(voiceMode ? Icons.keyboard : Icons.mic_none, size: 26),
              onPressed: onVoiceMode,
              tooltip: voiceMode ? '切回键盘' : '语音输入',
            ),
            Expanded(
              // 语音模式：整栏「按住 说话」按钮；否则文本输入框
              child: voiceMode
                  ? GestureDetector(
                      onLongPressStart: (_) => onMicStart(),
                      onLongPressEnd: (_) => onMicEnd(),
                      onLongPressCancel: onMicEnd,
                      child: Container(
                        height: 40,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: recording ? AppColors.primary : Colors.white,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          recording ? '松开 发送' : '按住 说话',
                          style: TextStyle(
                            fontSize: 15,
                            color: recording ? Colors.white : Colors.black87,
                          ),
                        ),
                      ),
                    )
                  : Focus(
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
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 9,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(
                Icons.emoji_emotions_outlined,
                size: 26,
                color: emojiOn ? AppColors.primary : null,
              ),
              onPressed: onEmoji,
            ),
            IconButton(
              icon: const Icon(Icons.auto_awesome, size: 24),
              onPressed: onSuggest,
              tooltip: '帮我想一句',
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
                      borderRadius: BorderRadius.circular(6),
                    ),
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

/// 表情面板：常用 emoji 宫格，点击插入输入框
class _EmojiPanel extends StatelessWidget {
  final ValueChanged<String> onPick;

  const _EmojiPanel({required this.onPick});

  static const _emojis = [
    '😀',
    '😂',
    '🤣',
    '😊',
    '😍',
    '🥰',
    '😘',
    '😜',
    '🤔',
    '😅',
    '😭',
    '😤',
    '🥺',
    '😴',
    '🤗',
    '😎',
    '🤯',
    '😳',
    '🙄',
    '😇',
    '👍',
    '👎',
    '👏',
    '🙏',
    '💪',
    '🤝',
    '👌',
    '✌️',
    '🫶',
    '💕',
    '❤️',
    '💔',
    '💯',
    '🔥',
    '✨',
    '🎉',
    '🎂',
    '🌹',
    '🍀',
    '🌙',
    '☀️',
    '⭐',
    '🌈',
    '☕',
    '🍺',
    '🧋',
    '🍜',
    '🍰',
    '🐱',
    '🐶',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.navBarBg,
      height: 200,
      child: GridView.count(
        crossAxisCount: 10,
        padding: const EdgeInsets.all(8),
        children: [
          for (final e in _emojis)
            InkWell(
              onTap: () => onPick(e),
              child: Center(
                child: Text(e, style: const TextStyle(fontSize: 24)),
              ),
            ),
        ],
      ),
    );
  }
}
