import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/contact.dart';
import 'package:wecheat/models/conversation.dart';
import 'package:wecheat/providers/chat_provider.dart';
import 'package:wecheat/providers/conversation_provider.dart';
import 'package:wecheat/providers/output_mode_provider.dart';
import 'package:wecheat/services/llm_service.dart';
import 'package:wecheat/services/ollama_service.dart';
import 'package:wecheat/services/remote_llm_service.dart';

class _DelayedReply extends LlmService {
  _DelayedReply() : super(OllamaService(), RemoteLlmService());
  final started = Completer<void>();
  final resume = Completer<void>();
  int requests = 0;
  @override
  Stream<String> chat(
    AiProfile profile,
    List<({String role, String content})> history, {
    String? systemPrompt,
  }) async* {
    final request = ++requests;
    if (request == 1) {
      yield '已经收到第一条';
      started.complete();
      await resume.future;
      yield '，现在回答完了。';
    } else {
      yield '第二条消息我也看到了，一起聊聊你的计划。';
    }
  }
}

void main() {
  test(
    'reply streams immediately and messages sent during generation are queued',
    () async {
      final directory = await Directory.systemTemp.createTemp('reply_queue');
      Hive.init(directory.path);
      final llm = _DelayedReply();
      final container = ProviderContainer(
        overrides: [llmServiceProvider.overrideWithValue(llm)],
      );
      const id = 'queue_test';
      try {
        await container.read(conversationListProvider.future);
        final subscription = container.listen(
          chatMessagesProvider(id),
          (_, _) {},
        );
        addTearDown(subscription.close);
        await container
            .read(outputModeProvider.notifier)
            .select(OutputMode.text);
        await container
            .read(conversationListProvider.notifier)
            .addConversation(
              Conversation(
                id: id,
                contact: const Contact(
                  id: 'queue_ai',
                  name: '测试角色',
                  isAi: true,
                ),
                lastMessage: '',
                lastMessageTime: DateTime.now(),
              ),
            );
        await container.read(chatMessagesProvider(id).future);
        final notifier = container.read(chatMessagesProvider(id).notifier);
        await notifier.send('第一条');
        await llm.started.future.timeout(const Duration(seconds: 5));
        expect(
          container.read(chatMessagesProvider(id)).value!.messages.last.content,
          '已经收到第一条',
        );
        await notifier.send('第二条');
        expect(llm.requests, 1);
        llm.resume.complete();
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          final state = container.read(chatMessagesProvider(id)).value!;
          if (state.messages.where((message) => !message.isMe).length == 2 &&
              !state.generating) {
            break;
          }
        }
        final messages = container
            .read(chatMessagesProvider(id))
            .value!
            .messages;
        expect(llm.requests, 2);
        expect(
          messages
              .where((message) => !message.isMe)
              .map((message) => message.content),
          ['已经收到第一条，现在回答完了。', '第二条消息我也看到了，一起聊聊你的计划。'],
        );
        await notifier.send('再说一遍');
        for (var attempt = 0; attempt < 100; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          final state = container.read(chatMessagesProvider(id)).value!;
          if (state.messages.where((message) => !message.isMe).length == 3 &&
              !state.generating) {
            break;
          }
        }
        expect(llm.requests, 3);
        expect(
          container.read(chatMessagesProvider(id)).value!.messages.last.content,
          '第二条消息我也看到了，一起聊聊你的计划。',
        );
      } finally {
        container.dispose();
        await Hive.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
