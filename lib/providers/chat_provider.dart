import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/message.dart';
import '../repositories/message_repository.dart';
import '../services/ai_prompt.dart';
import '../services/ollama_service.dart';
import 'ai_profile_provider.dart';
import 'conversation_provider.dart';

final messageRepositoryProvider =
    Provider<MessageRepository>((ref) => MessageRepository());

final ollamaServiceProvider =
    Provider<OllamaService>((ref) => OllamaService());

/// 聊天页状态：消息列表 + AI 是否正在生成
class ChatState {
  final List<Message> messages;
  final bool generating;

  const ChatState({this.messages = const [], this.generating = false});

  ChatState copyWith({List<Message>? messages, bool? generating}) => ChatState(
        messages: messages ?? this.messages,
        generating: generating ?? this.generating,
      );
}

/// 单个会话的消息控制器（family 按 conversationId 区分，autoDispose 退出即释放）
class ChatMessages extends AsyncNotifier<ChatState> {
  ChatMessages(this.conversationId);

  final String conversationId;
  static int _seq = 0;

  MessageRepository get _repo => ref.read(messageRepositoryProvider);

  @override
  Future<ChatState> build() async {
    await _repo.init();
    // 预载 AI 资料，保证第一条消息就能带上人设/知识库
    await ref.read(aiProfileProvider.notifier).ensureLoaded();
    return ChatState(messages: _repo.loadByConversation(conversationId));
  }

  bool get _isAiConversation {
    final list = ref.read(conversationListProvider).value;
    return list
            ?.where((c) => c.id == conversationId)
            .firstOrNull
            ?.contact
            .isAi ??
        false;
  }

  Future<void> send(String text) async {
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
      createdAt: DateTime.now(),
    );
    await _repo.save(userMsg);
    final messages = [...current.messages, userMsg];
    state = AsyncData(current.copyWith(messages: messages));
    _syncConversation(userMsg);

    if (_isAiConversation) unawaited(_generateReply(messages, content));
  }

  /// 把最近上下文发给 Ollama，流式增量写入 AI 气泡
  Future<void> _generateReply(List<Message> context, String userText) async {
    final aiMsg = Message(
      id: _newId(),
      conversationId: conversationId,
      senderId: 'ai_assistant',
      isMe: false,
      type: MessageType.text,
      content: '',
      createdAt: DateTime.now(),
    );
    state = AsyncData(ChatState(
      messages: [...context, aiMsg],
      generating: true,
    ));

    final history = [
      for (final m in context.where((m) => m.type == MessageType.text))
        (role: m.isMe ? 'user' : 'assistant', content: m.content),
    ].reversed.take(20).toList().reversed.toList();

    // 人设 + 按当前提问检索知识库 + 聊天记录风格样本 + 模型选择
    final profile = ref.read(aiProfileProvider);
    final systemPrompt =
        buildAiSystemPrompt(profile, userText: userText);
    assert(() {
      debugPrint('[AI] model=${profile.model} systemPrompt:\n$systemPrompt');
      return true;
    }());

    var full = '';
    try {
      await for (final chunk in ref.read(ollamaServiceProvider).chat(
        history,
        systemPrompt: systemPrompt,
        model: profile.model,
      )) {
        full += chunk;
        _patch(aiMsg.id, full);
      }
    } catch (_) {
      full = 'AI 助手暂时不可用，请确认本地 Ollama 服务已启动（127.0.0.1:11434）';
      _patch(aiMsg.id, full);
    }
    if (full.isEmpty) full = '（未返回内容）';

    final done = aiMsg.copyWith(content: full);
    await _repo.save(done);
    _syncConversation(done);
    state = AsyncData(state.value!.copyWith(generating: false));
  }

  void _patch(String id, String content) {
    final current = state.value;
    if (current == null) return;
    state = AsyncData(current.copyWith(messages: [
      for (final m in current.messages)
        m.id == id ? m.copyWith(content: content) : m,
    ]));
  }

  void _syncConversation(Message msg) {
    unawaited(ref
        .read(conversationListProvider.notifier)
        .updateLastMessage(conversationId, msg.content, msg.createdAt));
  }

  String _newId() =>
      'm${DateTime.now().microsecondsSinceEpoch}_${_seq++}';
}

final chatMessagesProvider = AsyncNotifierProvider.autoDispose
    .family<ChatMessages, ChatState, String>(ChatMessages.new);
