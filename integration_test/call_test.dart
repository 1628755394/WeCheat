import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:wecheat/features/call/call_page.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/contact.dart';
import 'package:wecheat/models/conversation.dart';
import 'package:wecheat/models/message.dart';
import 'package:wecheat/providers/ai_profile_provider.dart';
import 'package:wecheat/providers/chat_provider.dart';
import 'package:wecheat/providers/conversation_provider.dart';
import 'package:wecheat/services/llm_service.dart';
import 'package:wecheat/services/ollama_service.dart';
import 'package:wecheat/services/remote_llm_service.dart';
import 'package:wecheat/services/tts_service.dart';
import 'package:wecheat/services/voice_api_client.dart';

class _CallLlm extends LlmService {
  _CallLlm() : super(OllamaService(), RemoteLlmService());
  Completer<void>? continueReply;

  @override
  Stream<String> chat(
    AiProfile profile,
    List<({String role, String content})> history, {
    String? systemPrompt,
  }) async* {
    yield '你好，这是通话语音测试。';
    if (continueReply != null) await continueReply!.future;
    yield '现在挂断通话后，应用应当继续正常运行。';
  }
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native Windows speech and repeated video call hangups', (
    tester,
  ) async {
    final directory = await Directory.systemTemp.createTemp(
      'wecheat_call_test_',
    );
    Hive.init(directory.path);
    await Hive.openBox('ai_profiles');
    const id = 'conv_char_baoqingfangzhu';
    final conversation = Conversation(
      id: id,
      contact: const Contact(
        id: 'char_baoqingfangzhu',
        name: '宝青坊主',
        isAi: true,
      ),
      lastMessage: '',
      lastMessageTime: DateTime.now(),
    );
    final llm = _CallLlm();
    final container = ProviderContainer(
      overrides: [
        resolvedConversationListProvider.overrideWithValue(
          AsyncData([conversation]),
        ),
        llmServiceProvider.overrideWithValue(llm),
      ],
    );
    await container.read(aiProfileProvider(id).notifier).ensureLoaded();
    final repository = container.read(messageRepositoryProvider);
    await repository.init();
    await repository.save(
      Message(
        id: 'prior_call_caption',
        conversationId: id,
        senderId: 'me',
        isMe: true,
        type: MessageType.text,
        content: '之前的聊天内容',
        createdAt: DateTime.now().subtract(const Duration(minutes: 1)),
      ),
    );
    final router = GoRouter(
      initialLocation: '/chat/$id',
      routes: [
        GoRoute(
          path: '/chat/:id',
          builder: (_, _) => const Scaffold(body: Text('Chat remains open')),
        ),
        GoRoute(
          path: '/call/:id',
          builder: (_, _) => const CallPage(conversationId: id, isVideo: true),
        ),
      ],
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp.router(routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();

    // Native completion proves Windows accepted and completed the speech output.
    final tts = TtsService();
    await tts.init();
    await tts.stop();
    expect(
      await tts.speak('正在测试中文语音播报。').timeout(const Duration(seconds: 30)),
      true,
    );
    await tts.stop();

    router.push('/call/$id?video=1');
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Chat remains open'), findsOneWidget);

    var synthesisRequests = 0;
    var sessionRequests = 0;
    final voiceServer = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    voiceServer.listen((request) async {
      if (request.uri.path.endsWith('/synthesize')) {
        synthesisRequests++;
      } else if (request.uri.path.endsWith('/voice-sessions')) {
        sessionRequests++;
      }
      request.response
        ..statusCode = HttpStatus.unprocessableEntity
        ..headers.contentType = ContentType.json
        ..write('{"msg":"pipeline voice config incomplete"}');
      await request.response.close();
    });
    await container
        .read(aiProfileProvider(id).notifier)
        .setVoiceApiProfile(
          baseUrl: 'http://127.0.0.1:${voiceServer.port}',
          cloneProfileId: 'test-clone',
        );
    VoiceApiRuntime.bearerToken = 'test-token';
    llm.continueReply = Completer<void>();

    router.push('/call/$id?video=1');
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();
    expect(find.textContaining('这是通话语音测试'), findsOneWidget);
    expect(find.textContaining('现在挂断通话后'), findsNothing);
    llm.continueReply!.complete();
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pump();
    expect(find.textContaining('现在挂断通话后'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.subtitles_outlined));
    await tester.pump();
    expect(find.text('之前的聊天内容'), findsOneWidget);
    await tester.tap(find.byIcon(Icons.subtitles));
    await tester.pump();
    expect(find.textContaining('这是通话语音测试'), findsOneWidget);
    expect(synthesisRequests, greaterThan(0));
    expect(sessionRequests, 0);
    expect(
      find.textContaining('pipeline voice config incomplete'),
      findsNothing,
    );
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Chat remains open'), findsOneWidget);
    expect(
      repository
          .loadByConversation(id)
          .any((message) => message.content.contains('这是通话语音测试')),
      isTrue,
    );
    expect(tester.takeException(), isNull);

    VoiceApiRuntime.bearerToken = '';
    await voiceServer.close(force: true);
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
}
