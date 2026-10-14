import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/contact.dart';
import '../services/repetition_policy.dart';
import '../models/ai_profile.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/mood_state.dart';
import '../services/mood_policy.dart';
import '../repositories/message_repository.dart';
import '../services/ai_prompt.dart';
import '../services/llm_service.dart';
import '../services/ollama_service.dart';
import '../services/remote_llm_service.dart';
import '../services/stt_service.dart';
import '../services/tts_service.dart';
import '../services/voice_api_client.dart';
import '../services/voice_service.dart';
import 'ai_profile_provider.dart';
import 'mood_provider.dart';
import 'output_mode_provider.dart';
import 'conversation_provider.dart';

final messageRepositoryProvider = Provider<MessageRepository>(
  (ref) => MessageRepository(),
);

final ollamaServiceProvider = Provider<OllamaService>((ref) => OllamaService());

final remoteLlmServiceProvider = Provider<RemoteLlmService>(
  (ref) => RemoteLlmService(),
);

/// 统一入口：按 AI 资料的 provider 分发 Ollama / 远程接口
final llmServiceProvider = Provider<LlmService>(
  (ref) => LlmService(
    ref.read(ollamaServiceProvider),
    ref.read(remoteLlmServiceProvider),
  ),
);

/// 聊天页状态：消息列表 + AI 是否正在生成 + 当前发言的成员名（群聊用）
class ChatState {
  final List<Message> messages;
  final bool generating;
  final String? speakerName;

  const ChatState({
    this.messages = const [],
    this.generating = false,
    this.speakerName,
  });

  ChatState copyWith({
    List<Message>? messages,
    bool? generating,
    String? speakerName,
  }) => ChatState(
    messages: messages ?? this.messages,
    generating: generating ?? this.generating,
    speakerName: speakerName ?? this.speakerName,
  );
}

/// 单个会话的消息控制器（family 按 conversationId 区分，autoDispose 退出即释放）
class ChatMessages extends AsyncNotifier<ChatState> {
  ChatMessages(this.conversationId);

  final String conversationId;
  static int _seq = 0;
  bool _disposed = false;
  bool _refreshingRecentState = false;
  Future<void> _replyQueue = Future<void>.value();

  final VoiceService _voiceService = VoiceService();
  final TtsService _ttsService = TtsService();
  bool _ttsReady = false;
  int _playbackGeneration = 0;

  MessageRepository get _repo => ref.read(messageRepositoryProvider);

  @override
  Future<ChatState> build() async {
    ref.onDispose(() {
      _disposed = true;
      _voiceService.dispose();
      _ttsService.dispose();
      if (activeConversationId == conversationId) {
        activeConversationId = null;
      }
    });
    // 标记本会话正在前台展示（退出后 AI 消息会计入未读）
    activeConversationId = conversationId;
    await _repo.init();
    // 预载本会话的 AI 资料，保证第一条消息就能带上人设/知识库
    await ref.read(aiProfileProvider(conversationId).notifier).ensureLoaded();
    var messages = _repo.loadByConversation(conversationId);
    if (messages.isEmpty) {
      // 猫箱式开场白：空会话自动发第一句
      final greeting = await _seedGreeting();
      if (greeting != null) messages = [greeting];
    }
    // 猫箱式主动问候：超过 30 分钟没动静，打开会话时 AI 主动来找你
    if (messages.isNotEmpty) {
      final last = messages.last;
      final conv = _conversation;
      if (DateTime.now().difference(last.createdAt).inMinutes >= 30 &&
          conv != null) {
        Contact? proactor;
        if (conv.contact.isGroup) {
          // 群聊：随机一个 AI 成员冒泡
          final ai = conv.members.where((m) => m.isAi).toList();
          if (ai.isNotEmpty) {
            proactor = ai[DateTime.now().microsecond % ai.length];
          }
        } else if (conv.contact.isAi) {
          proactor = conv.contact;
        }
        if (proactor != null && !generatingIds.contains(conversationId)) {
          if (!last.isMe && last.senderId == proactor.id) {
            final mood = ref.read(
              moodProvider(_profileKeyOf(proactor)).notifier,
            );
            await mood.ensureLoaded();
            await mood.onEvent('已读不回');
          }
          generatingIds.add(conversationId);
          try {
            final full = await _streamReply(
              proactor,
              messages,
              '[系统提示：对方很久没回你消息了，你主动发一条消息找TA——可以是关心、'
                  '分享日常或找个话题，符合你的人设，像微信里主动戳一下对方]',
              'proactive_${_newId()}',
            );
            if (full.isNotEmpty &&
                !full.startsWith('远程接口调用失败') &&
                full != '（未返回内容）' &&
                !full.contains('暂时不可用')) {
              final msg = Message(
                id: _newId(),
                conversationId: conversationId,
                senderId: proactor.id,
                isMe: false,
                type: MessageType.text,
                content: full,
                createdAt: DateTime.now(),
              );
              await _repo.save(msg);
              _syncConversation(msg, senderName: proactor.displayName);
              messages = [...messages, msg];
            }
          } finally {
            generatingIds.remove(conversationId);
          }
        }
      }
    }
    return ChatState(messages: messages);
  }

  /// AI 单聊还没有消息时，把人设里的开场白作为第一条消息落库
  Future<Message?> _seedGreeting() async {
    await ref.read(conversationListProvider.future);
    final conv = _conversation;
    final profile = ref.read(aiProfileProvider(conversationId));
    if (conv == null || conv.contact.isGroup || !conv.contact.isAi) {
      return null;
    }
    if (profile.greeting.isEmpty) return null;
    // 好感度低时不用预设的热情开场白，让 AI 按当前态度生成（<0 只会回一个字）
    var text = profile.greeting;
    if (profile.affinity < 20) {
      final gen = await _streamReply(
        conv.contact,
        const [],
        '[系统提示：你们刚开始聊天，你先开口说第一句话，符合你对TA当前的态度]',
        'greeting_${_newId()}',
      );
      if (gen.isNotEmpty && !gen.startsWith('远程接口调用失败') && gen != '（未返回内容）') {
        text = gen;
      }
    }
    final msg = Message(
      id: _newId(),
      conversationId: conversationId,
      senderId: conv.contact.id,
      isMe: false,
      type: MessageType.text,
      content: text,
      createdAt: DateTime.now(),
    );
    await _repo.save(msg);
    _syncConversation(msg);
    return msg;
  }

  Conversation? get _conversation => ref
      .read(conversationListProvider)
      .value
      ?.where((c) => c.id == conversationId)
      .firstOrNull;

  /// 需要自动回复的 AI 成员：单聊 = 会话联系人本人；群聊 = members 里所有 AI 好友
  List<Contact> get _aiMembers {
    final conv = _conversation;
    if (conv == null) return const [];
    if (conv.contact.isGroup) {
      return [
        for (final m in conv.members)
          if (m.isAi) m,
      ];
    }
    return conv.contact.isAi ? [conv.contact] : const [];
  }

  /// 成员人设资料的存储 key：优先复用其单聊会话的配置（人设/知识库/模型共享）
  String _profileKeyOf(Contact member) {
    for (final c in ref.read(conversationListProvider).value ?? const []) {
      if (!c.contact.isGroup && c.contact.id == member.id) return c.id;
    }
    return member.id;
  }

  /// 消息发送者昵称（群聊历史里给其他成员的消息加 "名字: " 前缀用）
  String _senderName(String senderId) {
    final conv = _conversation;
    if (conv == null) return '成员';
    if (senderId == conv.contact.id) return conv.contact.displayName;
    for (final m in conv.members) {
      if (m.id == senderId) return m.displayName;
    }
    return '成员';
  }

  String _conversationTiming(List<Message> messages) {
    if (messages.length < 2) return '';
    final gap = messages.last.createdAt.difference(
      messages[messages.length - 2].createdAt,
    );
    if (gap.inHours >= 24) return '你们隔了一天以上才继续聊天';
    if (gap.inHours >= 6) return '你们隔了几个小时才继续聊天';
    if (gap.inMinutes >= 30) return '你们隔了一阵子才继续聊天';
    return '';
  }

  /// 按 senderId 找发言成员；单聊兜底回会话联系人
  Contact? _memberOf(String senderId) {
    final conv = _conversation;
    if (conv == null) return null;
    if (senderId == conv.contact.id) return conv.contact;
    for (final m in conv.members) {
      if (m.id == senderId) return m;
    }
    return conv.contact.isGroup ? null : conv.contact;
  }

  Future<void> send(
    String text, {
    String quoteText = '',
    String quoteSender = '',
    bool voiceReply = false,
  }) async {
    final current = state.value;
    final content = text.trim();
    if (current == null || content.isEmpty) return;

    final userMsg = Message(
      id: _newId(),
      conversationId: conversationId,
      senderId: 'me',
      isMe: true,
      type: MessageType.text,
      content: content,
      quoteText: quoteText,
      quoteSender: quoteSender,
      createdAt: DateTime.now(),
    );
    await _repo.save(userMsg);
    final latest = state.value ?? current;
    final messages = [...latest.messages, userMsg];
    state = AsyncData(latest.copyWith(messages: messages));
    _syncConversation(userMsg);

    final members = _aiMembers;
    if (members.isNotEmpty) {
      unawaited(
        _generateReplies(members, messages, content, voiceReply: voiceReply),
      );
    }
  }

  /// 发送非文本类消息（图片/位置/红包/名片/文件）。
  /// replyHint 是给 AI 看的用户行为描述（如「[发来一张图片]」），为空则不触发回复
  Future<void> sendRich({
    required MessageType type,
    required String content,
    Uint8List? mediaBytes,
    Uint8List? audioBytes,
    String audioFileName = '',
    String? replyHint,
  }) async {
    final current = state.value;
    if (current == null) return;
    final msg = Message(
      id: _newId(),
      conversationId: conversationId,
      senderId: 'me',
      isMe: true,
      type: type,
      content: content,
      mediaBytes: mediaBytes,
      audioBytes: audioBytes,
      audioFileName: audioFileName,
      createdAt: DateTime.now(),
    );
    await _repo.save(msg);
    final messages = [...current.messages, msg];
    if (!_disposed) {
      state = AsyncData(current.copyWith(messages: messages));
    }
    _syncConversation(msg);

    // 转账/红包/礼物：好感度低于 30 时可以挽回（≥30 送了也不涨）
    if (type == MessageType.redPacket ||
        type == MessageType.transfer ||
        type == MessageType.gift) {
      _applyGiftAffinity(type, content);
    }

    final members = _aiMembers;
    if (members.isNotEmpty && replyHint != null && replyHint.isNotEmpty) {
      unawaited(_generateReplies(members, messages, replyHint));
    }
  }

  /// 转账/红包/礼物挽回好感度：当前好感度 <30 才生效
  /// 红包/转账按金额折算（¥20 ≈ +1，上限 +15），礼物固定 +8；群聊惠及所有 AI 成员
  void _applyGiftAffinity(MessageType type, String content) {
    final conv = _conversation;
    if (conv == null) return;
    final targets = conv.contact.isGroup
        ? conv.members.where((m) => m.isAi).toList()
        : (conv.contact.isAi ? [conv.contact] : <Contact>[]);
    if (targets.isEmpty) return;

    int gain;
    if (type == MessageType.gift) {
      gain = 8;
    } else {
      // content 格式 '祝福语|金额' 或 '金额'
      final amount = double.tryParse(content.split('|').last.trim()) ?? 0;
      gain = (amount / 20).ceil().clamp(5, 15);
    }
    for (final m in targets) {
      final key = _profileKeyOf(m);
      final cur = ref.read(aiProfileProvider(key)).affinity;
      if (cur < 30) {
        unawaited(ref.read(aiProfileProvider(key).notifier).addAffinity(gain));
      }
    }
  }

  /// 撤回：标记消息为已撤回，气泡改渲染「撤回了一条消息」
  Future<void> recallMessage(String messageId) async {
    final current = state.value;
    if (current == null) return;
    final target = current.messages.where((m) => m.id == messageId).firstOrNull;
    if (target == null || target.recalled) return;
    final done = target.copyWith(recalled: true);
    await _repo.save(done);
    if (_disposed) return;
    state = AsyncData(
      current.copyWith(
        messages: [
          for (final m in current.messages) m.id == messageId ? done : m,
        ],
      ),
    );
    if (target.isMe) {
      for (final member in _aiMembers) {
        unawaited(
          ref
              .read(moodProvider(_profileKeyOf(member)).notifier)
              .onEvent('撤回消息'),
        );
      }
    }
    unawaited(
      ref
          .read(conversationListProvider.notifier)
          .updateLastMessage(conversationId, '撤回了一条消息', target.createdAt),
    );
  }

  /// 删除：仅从本地移除（不改会话摘要，和微信一致）
  Future<void> deleteMessage(String messageId) async {
    final current = state.value;
    if (current == null) return;
    await _repo.delete(messageId);
    if (_disposed) return;
    state = AsyncData(
      current.copyWith(
        messages: [
          for (final m in current.messages)
            if (m.id != messageId) m,
        ],
      ),
    );
  }

  /// 转发到别的会话：原样复制消息（发送者变成我）
  Future<void> forwardMessage(
    String messageId,
    String targetConversationId,
  ) async {
    final current = state.value;
    final target = current?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;
    if (target == null || target.recalled) return;
    final forwarded = Message(
      id: _newId(),
      conversationId: targetConversationId,
      senderId: 'me',
      isMe: true,
      type: target.type,
      content: target.content,
      mediaBytes: target.mediaBytes,
      audioBytes: target.audioBytes,
      audioFileName: target.audioFileName,
      createdAt: DateTime.now(),
    );
    await _repo.save(forwarded);
    unawaited(
      ref
          .read(conversationListProvider.notifier)
          .updateLastMessage(
            targetConversationId,
            _summaryOf(forwarded),
            forwarded.createdAt,
          ),
    );
  }

  /// 会话摘要文案：非文本消息显示类型占位
  static String _summaryOf(Message m) {
    switch (m.type) {
      case MessageType.image:
        return '[图片]';
      case MessageType.voice:
        return m.content.trim().isEmpty ? '[语音]' : '语音：${m.content}';
      case MessageType.location:
        return '[位置]';
      case MessageType.redPacket:
        return '[红包]';
      case MessageType.transfer:
        return '[转账]';
      case MessageType.gift:
        return '[礼物]';
      case MessageType.contact:
        return '[名片]';
      case MessageType.file:
        return '[文件]';
      case MessageType.system:
      case MessageType.text:
        return m.content;
    }
  }

  /// + 面板「语音消息」：AI 回复直接生成语音气泡（用克隆音色合成）
  Future<void> requestVoiceReply() async {
    final current = state.value;
    if (current == null || current.generating || _disposed) return;
    final members = _aiMembers;
    if (members.isEmpty) return;
    final lastUser = current.messages
        .where((m) => m.isMe && m.type == MessageType.text)
        .lastOrNull;
    await _generateReplies(
      members,
      current.messages,
      lastUser?.content ?? '',
      voiceReply: true,
    );
  }

  Future<Uint8List?> _synthesizeClone(AiProfile profile, String text) async {
    final token = VoiceApiRuntime.bearerToken;
    if (!profile.hasSoulNexusVoice ||
        profile.voiceApiBaseUrl.isEmpty ||
        token.isEmpty) {
      return null;
    }
    final api = VoiceApiClient(baseUrl: profile.voiceApiBaseUrl, token: token);
    try {
      return await api.synthesizeVoice(profile.voiceCloneProfileId, text);
    } catch (_) {
      return null;
    } finally {
      api.close();
    }
  }

  /// 播放语音消息 / 朗读文本消息：有克隆音色走 SoulNexus，否则回退系统 TTS
  Future<void> speakMessage(String messageId, {bool automatic = false}) async {
    final generation = _playbackGeneration;
    bool canPlay() =>
        !_disposed &&
        generation == _playbackGeneration &&
        (!automatic ||
            (audibleConversationId == conversationId &&
                ref.read(outputModeProvider).speaks));
    if (!canPlay()) return;
    final target = state.value?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;
    if (target == null) return;
    if (target.audioBytes != null) {
      await _voiceService.playAndWait(
        target.audioBytes!,
        mimeType: target.audioFileName.endsWith('.wav') ? 'audio/wav' : null,
      );
      return;
    }
    final member = _memberOf(target.senderId);
    final key = member == null ? conversationId : _profileKeyOf(member);
    await ref.read(aiProfileProvider(key).notifier).ensureLoaded();
    if (!canPlay()) return;
    final profile = ref.read(aiProfileProvider(key));
    final spoken = stripActions(target.content);
    final bytes = spoken.isEmpty ? null : await _synthesizeClone(profile, spoken);
    if (!canPlay()) return;
    if (bytes != null) {
      if (target.type == MessageType.voice) {
        final done = target.copyWith(
          audioBytes: bytes,
          audioFileName: 'voice.wav',
        );
        await _repo.save(done);
        final current = state.value;
        if (current != null && !_disposed) {
          state = AsyncData(
            current.copyWith(
              messages: [
                for (final m in current.messages) m.id == messageId ? done : m,
              ],
            ),
          );
        }
      }
      if (!canPlay()) return;
      await _voiceService.playAndWait(bytes, mimeType: 'audio/wav');
      return;
    }
    if (!_ttsReady) {
      await _ttsService.init();
      _ttsReady = true;
    }
    if (canPlay()) {
      await _ttsService.speak(
        stripActions(target.content),
        language: profile.language,
      );
    }
  }

  Future<void> stopPlayback() async {
    _playbackGeneration++;
    await _ttsService.stop();
    await _voiceService.stop();
  }

  Future<void> _autoSpeakReply(Message message) async {
    if (_disposed || audibleConversationId != conversationId) return;
    await ref.read(outputModeProvider.notifier).ensureLoaded();
    if (_disposed ||
        !ref.read(outputModeProvider).speaks ||
        audibleConversationId != conversationId) {
      return;
    }
    await speakMessage(message.id, automatic: true);
  }

  Future<String?> transcribeVoice(String messageId) async {
    final target = state.value?.messages
        .where((m) => m.id == messageId)
        .firstOrNull;
    if (target?.type != MessageType.voice || target?.audioBytes == null) {
      return null;
    }
    if (target!.content.trim().isNotEmpty) return target.content;

    await ref.read(aiProfileProvider(conversationId).notifier).ensureLoaded();
    final profile = ref.read(aiProfileProvider(conversationId));
    final text = await SttService.transcribeAudio(
      target.audioBytes!,
      endpoint: profile.transcriptionEndpoint.isEmpty
          ? SttService.defaultTranscriptionEndpoint
          : profile.transcriptionEndpoint,
      fileName: target.audioFileName.isEmpty
          ? 'voice.wav'
          : target.audioFileName,
    );
    if (text == null || text.isEmpty) return null;

    final done = target.copyWith(content: text);
    await _repo.save(done);
    _syncConversation(done);
    final current = state.value;
    if (current != null && !_disposed) {
      state = AsyncData(
        current.copyWith(
          messages: [
            for (final m in current.messages) m.id == messageId ? done : m,
          ],
        ),
      );
    }
    return text;
  }

  /// 群聊多 agent：成员按顺序轮流生成回复，后者能看到前者的发言
  /// voiceReply = true 时回复生成语音消息（克隆音色合成）
  Future<void> _generateReplies(
    List<Contact> members,
    List<Message> baseContext,
    String userText, {
    bool voiceReply = false,
  }) {
    final keepAlive = ref.keepAlive();
    final next = _replyQueue.catchError((Object _) {}).then((_) async {
      if (_disposed) return;
      await _performReplies(
        members,
        state.value?.messages ?? baseContext,
        userText,
        voiceReply: voiceReply,
      );
    });
    _replyQueue = next.whenComplete(keepAlive.close);
    return _replyQueue;
  }

  Future<void> _performReplies(
    List<Contact> members,
    List<Message> baseContext,
    String userText, {
    bool voiceReply = false,
  }) async {
    // 已有生成在跑（主动问候/巡检补回等）→ 跳过，避免一条消息多个回复
    if (!generatingIds.add(conversationId)) return;
    final keepAlive = ref.keepAlive();
    try {
      var context = baseContext;
      for (var i = 0; i < members.length; i++) {
        if (_disposed) return;
        final done = await _generateReply(
          members[i],
          context,
          userText,
          voiceReply,
        );
        context = [...context, done];
        if (i < members.length - 1) {
          await Future.delayed(const Duration(milliseconds: 600));
        }
      }
      unawaited(_refreshRecentState(members, context));
      if (!_disposed) {
        state = AsyncData(
          ChatState(messages: state.value?.messages ?? context),
        );
      }
    } finally {
      generatingIds.remove(conversationId);
      keepAlive.close();
    }
  }

  Future<void> _refreshRecentState(
    List<Contact> members,
    List<Message> messages,
  ) async {
    if (_disposed || _refreshingRecentState) return;
    _refreshingRecentState = true;
    final keepAlive = ref.keepAlive();
    try {
      for (final member in members) {
        final key = _profileKeyOf(member);
        final notifier = ref.read(aiProfileProvider(key).notifier);
        await notifier.ensureLoaded();
        final profile = ref.read(aiProfileProvider(key));
        if (messages.length < profile.recentStateMessageCount) {
          await notifier.setRecentState('', messageCount: 0);
          continue;
        }
        if (messages.length - profile.recentStateMessageCount < 8) continue;

        final eligible = messages
            .where(
              (m) =>
                  !m.recalled &&
                  m.type != MessageType.system &&
                  _summaryOf(m).trim().isNotEmpty,
            )
            .toList();
        final isGroup = _conversation?.contact.isGroup ?? false;
        var used = 0;
        final recent = <({String role, String content})>[];
        for (final message in eligible.reversed.take(24)) {
          final content = message.quoteText.isEmpty
              ? _summaryOf(message)
              : '（引用${message.quoteSender}的话「${message.quoteText}」）${_summaryOf(message)}';
          final role =
              message.isMe || (isGroup && message.senderId != member.id)
              ? 'user'
              : 'assistant';
          final text = !message.isMe && isGroup && message.senderId != member.id
              ? '${_senderName(message.senderId)}: $content'
              : content;
          if (used + text.length > 6000 && recent.isNotEmpty) break;
          recent.add((role: role, content: text));
          used += text.length;
        }
        if (recent.isEmpty) continue;

        var raw = '';
        try {
          await for (final chunk
              in ref
                  .read(llmServiceProvider)
                  .chat(
                    profile,
                    recent.reversed.toList(),
                    systemPrompt: buildRecentStateSummaryPrompt(
                      profile.recentState,
                    ),
                  )) {
            raw += chunk;
          }
        } catch (_) {
          continue;
        }
        await notifier.setRecentState(
          parseRecentStateSummary(raw),
          messageCount: messages.length,
        );
      }
    } catch (_) {
    } finally {
      _refreshingRecentState = false;
      keepAlive.close();
    }
  }

  /// 把最近上下文发给模型，流式增量写入 AI 气泡，返回最终落库的消息
  Future<Message> _generateReply(
    Contact member,
    List<Message> context,
    String userText, [
    bool asVoice = false,
  ]) async {
    final profileKey = _profileKeyOf(member);
    await ref.read(aiProfileProvider(profileKey).notifier).ensureLoaded();
    final memberMood = ref.read(moodProvider(profileKey).notifier);
    await memberMood.ensureLoaded();
    final beforeReplyProfile = ref.read(aiProfileProvider(profileKey));
    await memberMood.onUserMessage(
      negative:
          affinityGain(
            userText,
            beforeReplyProfile.likes,
            dislikes: beforeReplyProfile.dislikes,
          ) <
          0,
    );
    final sendAsVoice =
        asVoice || ref.read(aiProfileProvider(profileKey)).autoVoiceMessages;
    final aiMsg = Message(
      id: _newId(),
      conversationId: conversationId,
      senderId: member.id,
      isMe: false,
      type: sendAsVoice ? MessageType.voice : MessageType.text,
      content: '',
      createdAt: DateTime.now(),
    );
    // 以当前 state 为准追加气泡，兼容生成期间用户又发了消息的情况
    final base = _disposed ? context : (state.value?.messages ?? context);
    if (!_disposed) {
      state = AsyncData(
        ChatState(
          messages: [...base, aiMsg],
          generating: true,
          speakerName: member.displayName,
        ),
      );
    }

    final full = await _streamReply(member, base, userText, aiMsg.id);
    var done = aiMsg.copyWith(content: full);
    // 好感度：命中喜好 +6、命中厌恶词 -5（仿 1999 机制）
    final memberProfile = ref.read(aiProfileProvider(_profileKeyOf(member)));
    final gain = affinityGain(
      userText,
      memberProfile.likes,
      dislikes: memberProfile.dislikes,
    );
    final adjustedGain = adjustAffinityGain(
      gain,
      ref.read(moodProvider(profileKey)),
      memberProfile.affinity,
    );
    if (adjustedGain != 0) {
      unawaited(
        ref
            .read(aiProfileProvider(_profileKeyOf(member)).notifier)
            .addAffinity(adjustedGain),
      );
    }
    if (sendAsVoice && full.isNotEmpty) {
      final profile = ref.read(aiProfileProvider(_profileKeyOf(member)));
      final audio = await _synthesizeClone(profile, stripActions(full));
      if (audio != null) {
        done = done.copyWith(audioBytes: audio);
        final cur = state.value;
        if (cur != null && !_disposed) {
          state = AsyncData(
            cur.copyWith(
              messages: [
                for (final m in cur.messages) m.id == done.id ? done : m,
              ],
            ),
          );
        }
      }
    }
    await _repo.save(done);
    await memberMood.onReply(memberProfile.affinity);
    _syncConversation(done, senderName: member.displayName);
    await _autoSpeakReply(done);
    return done;
  }

  /// 组装上下文并生成最终回复；中间阶段不写入气泡
  Future<String> _streamReply(
    Contact member,
    List<Message> context,
    String userText,
    String messageId,
  ) async {
    final conv = _conversation;
    final isGroup = conv?.contact.isGroup ?? false;
    // 成员人设/知识库/模型：复用其单聊会话的资料
    final profileKey = _profileKeyOf(member);
    await ref.read(aiProfileProvider(profileKey).notifier).ensureLoaded();
    await ref.read(moodProvider(profileKey).notifier).ensureLoaded();

    final memberProfile = ref.read(aiProfileProvider(profileKey));
    var profile = memberProfile;
    if (isGroup) {
      await ref.read(aiProfileProvider(conversationId).notifier).ensureLoaded();
      final conversationProfile = ref.read(aiProfileProvider(conversationId));
      if (conversationProfile.userPersona.trim().isNotEmpty) {
        profile = memberProfile.copyWith(
          userPersona: conversationProfile.userPersona,
        );
      }
    }
    final styleTurns = relevantStyleTurns(profile.chatLog, userText);
    final allowRepetition = userRequestsExactSpeech(userText);
    bool isCharacterReply(Message message) =>
        !message.isMe &&
        message.type != MessageType.system &&
        message.content.trim().isNotEmpty &&
        (!isGroup || message.senderId == member.id);
    final previousAssistantReply = context.reversed
        .where(isCharacterReply)
        .map((m) => m.content)
        .firstOrNull;

    // 上下文窗口：few-shot 样本保底 + 最近真实消息尽量全带，
    // 按字符数预算（~1.2 万字 ≈ 8k token）截取而不是死扣条数，聊久了不忘事
    final realTurns = [
      for (final m
          in allowRepetition
              ? context.where((m) => !m.recalled)
              : _dedupeAssistant(context.where((m) => !m.recalled)))
        if (m.isMe)
          (
            role: 'user',
            content: m.quoteText.isEmpty
                ? _summaryOf(m)
                : '（引用${m.quoteSender}的话「${m.quoteText}」）${_summaryOf(m)}',
          )
        else if (!isGroup || m.senderId == member.id)
          (role: 'assistant', content: m.content)
        else
          (role: 'user', content: '${_senderName(m.senderId)}: ${m.content}'),
    ];
    const charBudget = 12000;
    var used = styleTurns.fold<int>(0, (s, t) => s + t.content.length);
    final kept = <({String role, String content})>[];
    for (final t in realTurns.reversed) {
      if (used + t.content.length > charBudget && kept.isNotEmpty) break;
      kept.add(t);
      used += t.content.length;
    }
    final history = [...styleTurns, ...kept.reversed];
    if (history.isEmpty) history.add((role: 'user', content: userText));
    final conversationTiming = _conversationTiming(context);
    // Persona and conversation context are in the prompt; generate visible text directly.

    var systemPrompt = buildAiSystemPrompt(
      profile,
      userText: userText,
      previousAssistantReply: previousAssistantReply ?? '',
      styleInHistory: styleTurns.isNotEmpty,
      suppressStyleExamples: profile.chatLog.isNotEmpty && styleTurns.isEmpty,
      conversationTiming: conversationTiming,
      groupName: isGroup ? conv!.contact.displayName : '',
      memberNames: isGroup
          ? [for (final m in conv!.members) m.displayName]
          : const [],
    );
    final moodInstruction = getMoodInstruction(
      ref.read(moodProvider(profileKey)),
      profile.affinity,
    );
    final showPartial =
        ref.read(moodProvider(profileKey)).zone(profile.affinity) ==
        MoodZone.calm;
    if (moodInstruction.isNotEmpty) {
      systemPrompt += '\n\n$moodInstruction';
    }
    systemPrompt += '\n\n【冲突表达边界】对事情可以失望或不满，但不能给用户贴人格或智力标签，不能辱骂。';
    // 预防复读最近高频表达，但不屏蔽角色名与人设中的必要称呼
    final memberRecent = [
      for (final m in context.reversed)
        if (isCharacterReply(m)) m.content,
    ].take(5).toList();
    final overused = ignoreRequiredNamesInRepeatedPhrases(
      _overusedPhrases(memberRecent),
      profile,
      characterName: member.displayName,
    );
    if (!allowRepetition && overused.isNotEmpty) {
      systemPrompt +=
          '\n\n【避免复读】你最近几轮常用这些说法：${overused.join('、')}。'
          '避免整段照搬，但若其中的普通词语是回应当前话题所必需的，可以自然使用；'
          '不要为了躲开这些词而回避问题或转移话题。';
    }
    var full = '';
    try {
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(profile, history, systemPrompt: systemPrompt)
              .timeout(const Duration(seconds: 45))) {
        full += chunk;
        if (showPartial && !containsPersonalAttack(full)) {
          var visible = full;
          if (endsWithPersonalAttackPrefix(full)) {
            final runes = full.runes.toList();
            visible = String.fromCharCodes(
              runes.take((runes.length - 1).clamp(0, runes.length)),
            );
          }
          _patch(messageId, _cleanReply(visible, member.displayName));
        }
      }
    } catch (e) {
      final detail = e.toString();
      full = profile.isRemote
          ? '远程接口调用失败：${detail.length > 120 ? detail.substring(0, 120) : detail}'
          : 'AI 助手暂时不可用，请确认本地 Ollama 服务已启动（127.0.0.1:11434）';
    }
    if (full.trim().isEmpty) full = '没有收到模型回复，请重试或检查 AI 配置中的模型服务。';

    // 清洗多余修饰：剥首尾引号、剥「角色名：/我：」前缀
    full = _cleanReply(full, member.displayName);
    // 先剥动作再比对——比的是说话内容，不是括号里的动作
    if (!profile.allowActions) {
      final stripped = stripActions(full);
      if (stripped.isNotEmpty) full = stripped;
    }
    if (containsPersonalAttack(full)) {
      try {
        var rewritten = '';
        await for (final chunk
            in ref
                .read(llmServiceProvider)
                .chat(
                  profile,
                  history,
                  systemPrompt:
                      '$systemPrompt\n\n【重新生成】上一份回复包含针对人的贬低用词。重新回答用户当前问题，只针对事情表达，不评价对方本人。',
                )
                .timeout(const Duration(seconds: 45))) {
          rewritten += chunk;
        }
        full = containsPersonalAttack(rewritten)
            ? '这件事让我有些失望，我想先缓一缓，之后再好好说。'
            : _cleanReply(rewritten, member.displayName);
      } catch (_) {
        full = '这件事让我有些失望，我想先缓一缓，之后再好好说。';
      }
    }

    // 复读自检：比较最近回复的整体相似度，并检查该角色全会话历史中的段落
    // 重复时重试并移除复用段落，最后优先保留未重复的草稿内容
    final previousReplies = [
      for (final m in context.reversed)
        if (isCharacterReply(m)) m.content,
      for (final turn in parseStyleTurns(profile.chatLog, max: 80))
        if (turn.role == 'assistant') turn.content,
    ];
    final recent = previousReplies.take(3).toList();
    final historicalParagraphs = historicalReplyParagraphs(previousReplies);
    bool hasRepeatedPhrases(String text) {
      final shared = ignoreRequiredNamesInRepeatedPhrases(
        _repeatedPhrases(text, recent),
        profile,
        characterName: member.displayName,
      );
      return shared.isNotEmpty ||
          _reusesOverusedPhrase(text, overused, userText);
    }

    if (allowRepetition ||
        (previousReplies.isEmpty &&
            repeatedReplyParagraphs(full, historicalParagraphs).isEmpty)) {
      _patch(messageId, full);
      return full;
    }

    final previousReply = previousAssistantReply ?? '';
    final continueInvitedTopic = isContinuationAcceptance(
      userText,
      previousReply,
    );
    final acceptedInvitation = isInvitationAcceptance(userText, previousReply);
    var attempt = 0;
    while (attempt < 1 &&
        (repeatedReplyParagraphs(full, historicalParagraphs).isNotEmpty ||
            hasRepeatedPhrases(full) ||
            _tooSimilar(full, recent) ||
            _samePattern(full, recent) ||
            _reusesOverusedPhrase(full, overused, userText) ||
            _repeatsPreviousEnding(
              full,
              previousAssistantReply ?? '',
              userText,
            ))) {
      attempt++;
      try {
        // 提取复读惯用片段（含雷同的开头动作），在纠错提示里点名禁用
        final repeatedParagraphs = repeatedReplyParagraphs(
          full,
          historicalParagraphs,
        );
        final sharedPhrases = ignoreRequiredNamesInRepeatedPhrases(
          _repeatedPhrases(full, recent),
          profile,
          characterName: member.displayName,
        );
        final banned = [
          ...repeatedParagraphs,
          ...sharedPhrases,
          ..._repeatedActions(full, recent),
        ].take(10).toList();
        final forbiddenParagraphs = historicalReplyParagraphs(
          repeatedParagraphs,
        );
        // 重试历史剔除与复读内容相似的 AI 发言，防止它自我模仿
        final retryHistory = [
          for (final h in history)
            if (!(h.role == 'assistant' &&
                (recent.contains(h.content) ||
                    _pairSimilar(h.content, full) ||
                    repeatedReplyParagraphs(
                      h.content,
                      forbiddenParagraphs,
                    ).isNotEmpty)))
              h,
        ];
        // Keep the first answer visible while attempting one corrective rewrite.
        var retry = '';
        await for (final chunk
            in ref
                .read(llmServiceProvider)
                .chat(
                  profile,
                  retryHistory,
                  systemPrompt:
                      '$systemPrompt\n\n${continueInvitedTopic
                          ? '【续讲重写】对方已接受你继续讲的邀请，直接讲出下一段具体内容，不要重述开场或再次提问。'
                          : acceptedInvitation
                          ? '【邀约接受重写】对方已接受你上一条具体邀约。直接确认原计划并自然推进，不要再问愿不愿意、不要改成别的活动、不要写成空泛的自我表态。'
                          : '【自检重写】你刚才生成的回复和历史内容或内部草稿重复。请按角色人设重新组织表达。'}'
                      '${banned.isEmpty ? '' : '避免整段复用这些表达：${banned.join('、')}。'}\n'
                      '请直接回应对方最新的那句话；不得复用会话历史中已经说过的完整句子或段落，不要为了避开相似措辞而换话题或省略关键信息。'
                      '只输出重写后的回复正文，不要解释、不要复述草稿。',
                )) {
          retry += chunk;
        }
        if (retry.isEmpty) break;
        full = _cleanReply(retry, member.displayName);
        if (!profile.allowActions) {
          final stripped = stripActions(full);
          if (stripped.isNotEmpty) full = stripped;
        }
      } catch (_) {
        break;
      }
    }

    // 最终定稿再清洗一次：重试产生的新文本可能又带（）动作/修饰
    full = _cleanReply(full, member.displayName);
    if (!profile.allowActions) {
      final stripped = stripActions(full);
      if (stripped.isNotEmpty) full = stripped;
    }
    if (repeatedReplyParagraphs(full, historicalParagraphs).isNotEmpty ||
        hasRepeatedPhrases(full)) {
      final uniqueParagraphs = removeRepeatedReplyParagraphs(
        full,
        historicalParagraphs,
      );
      final uniqueSentences = _removeRepeatedSentences(uniqueParagraphs, [
        ...overused,
        ...ignoreRequiredNamesInRepeatedPhrases(
          _repeatedPhrases(uniqueParagraphs, recent),
          profile,
          characterName: member.displayName,
        ),
      ], userText);
      if (uniqueSentences.isNotEmpty && !hasRepeatedPhrases(uniqueSentences)) {
        full = uniqueSentences;
      }
    }

    // Apply the final cleanup after streaming the answer.
    if (containsPersonalAttack(full)) {
      full = '这件事让我有些失望，我想先缓一缓，之后再好好说。';
    }
    _patch(messageId, full);
    return full;
  }

  static String _removeRepeatedSentences(
    String text,
    List<String> phrases,
    String userText,
  ) {
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?,.、~…“”「」]'), '');

    final input = normalize(userText);
    final blocked = [
      for (final phrase in phrases)
        if (normalize(phrase).runes.length >= 4 &&
            !input.contains(normalize(phrase)))
          normalize(phrase),
    ];
    if (blocked.isEmpty) return text;
    final kept = <String>[];
    for (final sentence in text.split(RegExp(r'(?<=[。！？!?])|[\r\n]+'))) {
      final normalized = normalize(sentence);
      if (!blocked.any((phrase) => normalized.contains(phrase))) {
        kept.add(sentence);
      }
    }
    return kept.join().trim();
  }

  static bool _reusesOverusedPhrase(
    String text,
    List<String> phrases,
    String userText,
  ) {
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?,.、~…"「」]'), '');
    final reply = normalize(text);
    final input = normalize(userText);
    return phrases.any((phrase) {
      final candidate = normalize(phrase);
      return candidate.runes.length >= 4 &&
          reply.contains(candidate) &&
          !input.contains(candidate);
    });
  }

  static bool _repeatsPreviousEnding(
    String text,
    String previousReply,
    String userText,
  ) {
    final endings = stripActions(previousReply)
        .trim()
        .split(RegExp(r'[。！？!?]+'))
        .where((part) => part.trim().isNotEmpty);
    final lastEnding = endings.isEmpty ? '' : endings.last.trim();
    String normalize(String value) =>
        value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?,.、~…"「」]'), '');
    final ending = normalize(lastEnding);
    return ending.runes.length >= 8 &&
        normalize(text).contains(ending) &&
        !normalize(userText).contains(ending);
  }

  /// 句式雷同检测：开头（括号动作）前 2 字 / 正文开头 3 字前缀，近 3 轮雷同 ≥2 次即套路复读
  static bool _samePattern(String text, List<String> recent) {
    final open = _openAction(text);
    var hits = 0;
    if (open != null) {
      for (final r in recent) {
        final o = _openAction(r);
        if (o != null && o.startsWith(open.substring(0, 2))) hits++;
      }
    }
    if (hits >= 2) return true;
    // 正文开头雷同：如「你他妈是不是傻」「你他妈别闹」共享「你他妈」前缀
    final head = stripActions(text).trim();
    if (head.length >= 3) {
      var headHits = 0;
      for (final r in recent) {
        final rh = stripActions(r).trim();
        if (rh.length >= 3 && rh.substring(0, 3) == head.substring(0, 3)) {
          headHits++;
        }
      }
      if (headHits >= 2) return true;
    }
    return false;
  }

  /// 清洗回复首尾的多余修饰：包裹引号、「角色名：」「我：」「回复：」前缀
  static String _cleanReply(String text, String memberName) {
    var s = text.trim();
    // 剥「名字：」前缀（含中英文冒号）
    s = s.replaceFirst(RegExp('^($memberName|我|回复|assistant)\\s*[：:]\\s*'), '');
    // 剥整段包裹的引号/书名号
    while (s.length >= 2 &&
        ((s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith('"') && s.endsWith('"')) ||
            (s.startsWith('「') && s.endsWith('」')) ||
            (s.startsWith('《') && s.endsWith('》')))) {
      s = s.substring(1, s.length - 1).trim();
    }
    return s;
  }

  /// 提取最近几条回复里被反复使用的 4 字片段（跨消息出现 ≥2 次），最多 8 个
  static List<String> _overusedPhrases(List<String> recent) {
    if (recent.length < 2) return const [];
    final counts = <String, int>{};
    for (final r in recent) {
      final t = r.replaceAll(RegExp(r'[\s，。！？!?,.、~…"「」]'), '');
      if (t.length < 4) continue;
      final seen = <String>{};
      for (var i = 0; i + 4 <= t.length; i++) {
        seen.add(t.substring(i, i + 4));
      }
      for (final g in seen) {
        counts[g] = (counts[g] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return [for (final e in sorted.take(8)) e.key];
  }

  /// 提取开头括号动作内容（最多 12 字）
  static String? _openAction(String s) =>
      RegExp(r'^[（(]([^（）()]{1,12})').firstMatch(s.trim())?.group(1);

  /// 收集近 3 轮出现过的开头动作前缀（前 2 字），重试时禁用
  static List<String> _repeatedActions(String text, List<String> recent) {
    final open = _openAction(text);
    if (open == null) return const [];
    return [
      for (final r in recent)
        if (_openAction(r)?.startsWith(open.substring(0, 2)) ?? false)
          '（${(_openAction(r))}）',
    ];
  }

  /// 提取新回复与近期回复共有的 ≥6 字片段（复读惯用语），最多 8 个
  static List<String> _repeatedPhrases(String text, List<String> recent) {
    final x = text.replaceAll(RegExp(r'\s'), '');
    const w = 6;
    final seen = <String>{};
    for (var i = 0; i + w <= x.length; i++) {
      final gram = x.substring(i, i + w);
      if (seen.contains(gram)) continue;
      for (final r in recent) {
        if (r.replaceAll(RegExp(r'\s'), '').contains(gram)) {
          seen.add(gram);
          break;
        }
      }
      if (seen.length >= 8) break;
    }
    return seen.toList();
  }

  /// 历史去重：同一发送者的 AI 消息若与更晚的一条几乎重复（bigram>0.45），
  /// 丢弃旧的那条——防止复读消息留在上下文里被模型当成模仿样本越学越像
  static List<Message> _dedupeAssistant(Iterable<Message> messages) {
    final list = messages.toList();
    final keep = List<bool>.filled(list.length, true);
    for (var i = 0; i < list.length; i++) {
      final a = list[i];
      if (a.isMe || a.type != MessageType.text) continue;
      for (var j = i + 1; j < list.length; j++) {
        final b = list[j];
        if (b.isMe || b.senderId != a.senderId) continue;
        if (_pairSimilar(a.content, b.content)) {
          keep[i] = false; // 丢旧的，留新的
          break;
        }
      }
    }
    return [
      for (var i = 0; i < list.length; i++)
        if (keep[i]) list[i],
    ];
  }

  static bool _pairSimilar(String a, String b) {
    final ga = _bigrams(a);
    final gb = _bigrams(b);
    if (ga.isEmpty || gb.isEmpty) return false;
    final inter = ga.intersection(gb).length;
    final union = ga.union(gb).length;
    return union > 0 && inter / union > 0.45;
  }

  /// 复读判定：与近期回复的字符 bigram 重叠率（Jaccard）> 0.4 即算复读
  static bool _tooSimilar(String a, List<String> recent) {
    final ga = _bigrams(a);
    if (ga.isEmpty) return false;
    for (final b in recent) {
      final gb = _bigrams(b);
      if (gb.isEmpty) continue;
      final inter = ga.intersection(gb).length;
      final union = ga.union(gb).length;
      if (union > 0 && inter / union > 0.4) return true;
    }
    return false;
  }

  static Set<String> _bigrams(String s) {
    final x = s.replaceAll(RegExp(r'\s'), '');
    if (x.length < 2) return const {};
    return {for (var i = 0; i < x.length - 1; i++) x.substring(i, i + 2)};
  }

  /// 「换一换」：对最后一条 AI 消息重新生成，旧版本进 variants 可左右切换
  Future<void> regenerate(String messageId) async {
    final current = state.value;
    if (current == null || current.generating || _disposed) return;
    final index = current.messages.indexWhere((m) => m.id == messageId);
    if (index < 0 || index != current.messages.length - 1) return;
    final target = current.messages[index];
    if (target.isMe || target.type != MessageType.text) return;

    final conv = _conversation;
    final member = _memberOf(target.senderId);
    if (conv == null || member == null || !member.isAi) return;

    final contextMsgs = current.messages.sublist(0, index);
    final lastUser = contextMsgs.lastWhere((m) => m.isMe, orElse: () => target);
    final oldContent = target.content;

    // 清空气泡重新流式生成
    state = AsyncData(
      current.copyWith(
        generating: true,
        speakerName: member.displayName,
        messages: [
          for (final m in current.messages)
            m.id == messageId ? m.copyWith(content: '') : m,
        ],
      ),
    );

    final full = await _streamReply(
      member,
      contextMsgs,
      lastUser.content,
      messageId,
    );
    final text = full.isEmpty ? oldContent : full;
    final variants = target.variants.isEmpty
        ? [oldContent, text]
        : [...target.variants, text];
    final done = target.copyWith(
      content: text,
      variants: variants,
      variantIndex: variants.length - 1,
    );
    await _repo.save(done);
    if (_disposed) return;
    state = AsyncData(
      ChatState(
        messages: [
          for (final m in state.value?.messages ?? current.messages)
            m.id == messageId ? done : m,
        ],
      ),
    );
    _syncConversation(done, senderName: member.displayName);
    await _autoSpeakReply(done);
  }

  /// 长按消息「标记为记忆」：内容写入该成员资料的重点记忆，永久注入 prompt
  Future<void> toggleMemory(String messageId) async {
    final current = state.value;
    if (current == null) return;
    final target = current.messages.where((m) => m.id == messageId).firstOrNull;
    if (target == null || target.type != MessageType.text) return;

    final member = _memberOf(target.senderId);
    final key = member == null ? conversationId : _profileKeyOf(member);
    final notifier = ref.read(aiProfileProvider(key).notifier);
    await notifier.ensureLoaded();

    final name = target.isMe ? '我' : (member?.displayName ?? '对方');
    final entry = '$name: ${target.content}';
    if (target.isMemory) {
      await notifier.removeMemory(entry);
    } else {
      await notifier.addMemory(entry);
    }

    final done = target.copyWith(isMemory: !target.isMemory);
    await _repo.save(done);
    if (_disposed) return;
    state = AsyncData(
      current.copyWith(
        messages: [
          for (final m in current.messages) m.id == messageId ? done : m,
        ],
      ),
    );
  }

  /// 左右切换「换一换」的历史版本
  Future<void> switchVariant(String messageId, int delta) async {
    final current = state.value;
    if (current == null || current.generating) return;
    final target = current.messages.where((m) => m.id == messageId).firstOrNull;
    if (target == null || target.variants.isEmpty) return;
    final next = target.variantIndex + delta;
    if (next < 0 || next >= target.variants.length) return;
    final done = target.copyWith(
      content: target.variants[next],
      variantIndex: next,
    );
    await _repo.save(done);
    if (_disposed) return;
    state = AsyncData(
      current.copyWith(
        messages: [
          for (final m in current.messages) m.id == messageId ? done : m,
        ],
      ),
    );
    _syncConversation(done);
  }

  /// 进入剧情场景：写一条「剧情切换」系统消息 + 场景开场白（没有开场白则让 AI 入戏生成）
  Future<void> enterScene(int index) async {
    await _repo.init();
    await ref.read(aiProfileProvider(conversationId).notifier).ensureLoaded();
    final profile = ref.read(aiProfileProvider(conversationId));
    if (index < -1 || index >= profile.scenes.length) return;
    if (index >= 0 && profile.scenes[index].name.contains('争吵')) {
      await ref.read(moodProvider(conversationId).notifier).ensureLoaded();
      if (!canEnterConflictScene(
        ref.read(moodProvider(conversationId)),
        profile.affinity,
      )) {
        return;
      }
    }
    await ref
        .read(aiProfileProvider(conversationId).notifier)
        .setSceneIndex(index);

    final conv = _conversation;
    final member = conv == null
        ? null
        : (conv.contact.isGroup
              ? conv.members.where((m) => m.isAi).firstOrNull
              : conv.contact);
    if (member == null || !member.isAi) return;

    var messages =
        state.value?.messages ?? _repo.loadByConversation(conversationId);
    if (index == -1) {
      // 退出剧情：只插系统提示
      final sys = Message(
        id: _newId(),
        conversationId: conversationId,
        senderId: 'system',
        isMe: false,
        type: MessageType.system,
        content: '剧情结束，回到日常',
        createdAt: DateTime.now(),
      );
      await _repo.save(sys);
      messages = [...messages, sys];
      if (!_disposed) {
        state = AsyncData(ChatState(messages: messages));
      }
      _syncConversation(sys);
      return;
    }

    final scene = profile.scenes[index];
    final sys = Message(
      id: _newId(),
      conversationId: conversationId,
      senderId: 'system',
      isMe: false,
      type: MessageType.system,
      content: '剧情开始：${scene.name}',
      createdAt: DateTime.now(),
    );
    await _repo.save(sys);
    messages = [...messages, sys];
    if (!_disposed) {
      state = AsyncData(ChatState(messages: messages));
    }
    _syncConversation(sys);

    // 场景开场白：预设优先，否则让 AI 按场景描述入戏生成
    if (scene.greeting.isNotEmpty) {
      final msg = Message(
        id: _newId(),
        conversationId: conversationId,
        senderId: member.id,
        isMe: false,
        type: MessageType.text,
        content: scene.greeting,
        createdAt: DateTime.now(),
      );
      await _repo.save(msg);
      messages = [...messages, msg];
      if (!_disposed) {
        state = AsyncData(ChatState(messages: messages));
      }
      _syncConversation(msg, senderName: member.displayName);
    } else {
      await _generateReply(
        member,
        messages,
        '[系统提示：剧情切换到「${scene.name}」。${scene.desc}请直接进入角色，发一条入场的消息]',
        false,
      );
    }
  }

  /// 智能回复建议（猫箱式）：让 AI 站在用户角度生成 3 条可直接发送的候选回复
  Future<List<String>> suggestReplies() async {
    final current = state.value;
    final conv = _conversation;
    if (current == null || conv == null) return const [];
    final member = conv.contact.isGroup
        ? conv.members.where((m) => m.isAi).firstOrNull
        : conv.contact;
    if (member == null || !member.isAi) return const [];
    final profileKey = _profileKeyOf(member);
    await ref.read(aiProfileProvider(profileKey).notifier).ensureLoaded();
    final profile = ref.read(aiProfileProvider(profileKey));
    final history = [
      for (final m in current.messages.reversed.take(12).toList().reversed)
        if (!m.recalled)
          (
            role: m.isMe ? 'user' : 'assistant',
            content: m.type == MessageType.text ? m.content : _summaryOf(m),
          ),
    ];
    var out = '';
    try {
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(
                profile,
                history,
                systemPrompt:
                    '你正在帮用户想回复。根据对话记录，生成 3 条用户（我）可以直接发出去的回复选项：'
                    '口语化、像微信消息、每条不超过 30 字；三条风格各异——一条顺着接话、一条调侃打趣、一条推进话题。'
                    '每行一条，不要编号、不要引号、不要任何解释。',
              )) {
        out += chunk;
      }
    } catch (_) {}
    return [
      for (final l in out.split('\n'))
        if (l.trim().isNotEmpty)
          l.trim().replaceAll(RegExp(r'^\d+[.、\)]?\s*'), ''),
    ].take(3).toList();
  }

  void _patch(String id, String content) {
    if (_disposed) return;
    final current = state.value;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        messages: [
          for (final m in current.messages)
            m.id == id ? m.copyWith(content: content) : m,
        ],
      ),
    );
  }

  /// 当前打开的聊天会话 id（收到的 AI 消息若不在前台则记未读）
  static String? activeConversationId;
  static String? audibleConversationId;

  /// 正在生成回复的会话 id 集合（后台巡检跳过生成中的会话）
  static final Set<String> generatingIds = {};

  /// 后台巡检：最后一条消息是我发的但 AI 还没回 → 补回一条
  /// 群聊只随机挑一个成员冒泡，不刷屏
  Future<void> chaseReply() async {
    final conv = _conversation;
    if (conv == null || generatingIds.contains(conversationId)) return;
    final msgs = _repo.loadByConversation(conversationId);
    final last = msgs.lastOrNull;
    if (last == null ||
        !last.isMe ||
        last.recalled ||
        last.type == MessageType.system) {
      return;
    }
    final member = conv.contact.isGroup
        ? (conv.members.where((m) => m.isAi).toList()..shuffle()).firstOrNull
        : (conv.contact.isAi ? conv.contact : null);
    if (member == null) return;
    if (!generatingIds.add(conversationId)) return;
    try {
      await _generateReply(member, msgs, last.content);
    } finally {
      generatingIds.remove(conversationId);
    }
  }

  void _syncConversation(Message msg, {String senderName = ''}) {
    // 群聊摘要仿微信带发言者前缀："名字: 内容"
    var text = _summaryOf(msg);
    if (!msg.isMe &&
        senderName.isNotEmpty &&
        (_conversation?.contact.isGroup ?? false)) {
      text = '$senderName: $text';
    }
    // 对方的消息且会话没在前台 → 未读 +1（微信式角标）
    final bump =
        !msg.isMe &&
        msg.type != MessageType.system &&
        activeConversationId != conversationId;
    unawaited(
      ref
          .read(conversationListProvider.notifier)
          .updateLastMessage(
            conversationId,
            text,
            msg.createdAt,
            bumpUnread: bump,
          ),
    );
  }

  String _newId() => 'm${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}

final chatMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ChatMessages, ChatState, String>(ChatMessages.new);
