import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';
import 'package:live2d_flutter/live2d_flutter.dart';
import 'package:wecheat/features/call/call_page.dart';
import 'package:wecheat/features/call/live2d_actor.dart';
import 'package:wecheat/services/virtual_actor.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/contact.dart';
import 'package:wecheat/models/conversation.dart';
import 'package:wecheat/models/message.dart';
import 'package:wecheat/models/live2d_model_config.dart';
import 'package:wecheat/providers/ai_profile_provider.dart';
import 'package:wecheat/providers/chat_provider.dart';
import 'package:wecheat/providers/conversation_provider.dart';
import 'package:wecheat/providers/output_mode_provider.dart';
import 'package:wecheat/services/llm_service.dart';
import 'package:wecheat/services/ollama_service.dart';
import 'package:wecheat/services/remote_llm_service.dart';
import 'package:wecheat/services/tts_service.dart';
import 'package:wecheat/services/voice_api_client.dart';
import 'package:wecheat/services/live2d_import_io.dart';
import 'package:wecheat/providers/call_performance_provider.dart';
import 'package:wecheat/features/call/call_waiting_view.dart';
import 'package:wecheat/core/theme.dart';

class _CallLlm extends LlmService {
  _CallLlm() : super(OllamaService(), RemoteLlmService());
  Completer<void>? continueReply;
  int requests = 0;

  @override
  Stream<String> chat(
    AiProfile profile,
    List<({String role, String content})> history, {
    String? systemPrompt,
  }) async* {
    requests++;
    yield '你好，这是通话语音测试。';
    if (continueReply != null) await continueReply!.future;
    yield '现在挂断通话后，应用应当继续正常运行。';
  }
}

class _TestPerformance extends CallPerformanceNotifier {
  @override
  void reduceEffects() {}
}

Future<void> _snapshot(WidgetTester tester, GlobalKey key, String name) async {
  final boundary =
      key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    final output = Directory(
      p.join(p.dirname(Platform.resolvedExecutable), 'call_previews'),
    );
    await output.create(recursive: true);
    await File(p.join(output.path, '$name.png'))
        .writeAsBytes(bytes!.buffer.asUint8List());
    image.dispose();
  });
}

Future<void> _waitForCall(WidgetTester tester) async {
  // Native model callbacks run in real time; do not settle repeating loading
  // dots until the native view signals that the model is ready.
  await tester.pump(const Duration(seconds: 2));
  for (var attempt = 0; attempt < 150; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();
    if (find.byType(CallWaitingView).evaluate().isEmpty) break;
  }
  expect(find.byType(CallWaitingView), findsNothing);
  await tester.pumpAndSettle();
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
        callPerformanceProvider.overrideWith(_TestPerformance.new),
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
    final screen = GlobalKey();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: RepaintBoundary(
          key: screen,
          child: MaterialApp.router(
            theme: buildAppTheme(),
            routerConfig: router,
          ),
        ),
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

    await container.read(outputModeProvider.notifier).ensureLoaded();
    await container.read(outputModeProvider.notifier).select(OutputMode.text);
    await container.read(callPerformanceProvider.notifier).ensureLoaded();
    // Deterministic integration timing: frame budget tests run separately.
    router.push('/call/$id?video=1');
    await tester.pump();
    expect(find.text('等待对方接受视频通话邀请'), findsOneWidget);
    await _snapshot(tester, screen, 'waiting_desktop');
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.byType(Live2DView), findsNothing);
    expect(find.text('动作'), findsNothing);
    expect(find.byType(CallAvatar), findsOneWidget);
    await _snapshot(tester, screen, 'avatar_desktop');
    await tester.tap(find.byIcon(Icons.call_end));
    await tester.pumpAndSettle();
    expect(find.text('Chat remains open'), findsOneWidget);
    final imported = await importLive2dModel(
      p.join(
        p.dirname(Platform.resolvedExecutable),
        'data',
        'flutter_assets',
        'assets',
        'live2d',
        'mao',
        'mao_pro.model3.json',
      ),
      p.join(directory.path, 'models'),
    );
    await container
        .read(aiProfileProvider(id).notifier)
        .setLive2dModel(
          imported.withActions([
            CustomActorAction(
              id: 'custom',
              name: '自定义动画',
              triggers: ['抱抱'],
              group: imported.motions.last.group,
              index: imported.motions.last.index,
            ),
          ]),
        );
    router.push('/call/$id?video=1');
    await tester.pump();
    expect(find.byType(CallWaitingView), findsOneWidget);
    await _waitForCall(tester);
    for (var attempt = 0; attempt < 60; attempt++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump();
      final model = tester.widget<Live2DView>(find.byType(Live2DView));
      if (model.controller!.value.isLoaded) break;
    }
    expect(
      tester
          .widget<Live2DView>(find.byType(Live2DView))
          .controller!
          .value
          .isLoaded,
      isTrue,
    );
    final actorView = tester.widget<Live2DActor>(find.byType(Live2DActor));
    final touchVersion = actorView.actor.actionVersion;
    await tester.tap(find.byType(Live2DActor));
    await tester.pump(const Duration(milliseconds: 300));
    expect(actorView.actor.actionVersion, touchVersion + 1);
    expect(actorView.actor.requestedAction, ActorAction.wink);
    final dragStart = tester.getCenter(find.byType(Live2DActor));
    final drag = await tester.startGesture(dragStart);
    await drag.moveBy(const Offset(100, 60));
    await tester.pump(const Duration(milliseconds: 300));
    await drag.up();
    await tester.pump(const Duration(milliseconds: 300));
    expect(actorView.actor.actionVersion, touchVersion + 1);
    expect(find.byType(SegmentedButton<bool>), findsNothing);
    await tester.tap(find.byIcon(Icons.keyboard));
    await tester.pumpAndSettle();
    for (final size in [
      const Size(1280, 800),
      const Size(390, 844),
      const Size(320, 568),
      const Size(844, 390),
    ]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pump(const Duration(milliseconds: 500));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 600)),
      );
      await tester.pump();
      expect(tester.takeException(), isNull);
      final field = tester.getRect(find.byType(TextField));
      expect(field.width, lessThanOrEqualTo(440));
      final toggle = tester.getRect(find.byTooltip('切换语音输入'));
      expect(toggle.right, lessThanOrEqualTo(field.left));
      expect(toggle.center.dy, closeTo(field.center.dy, 1));
      final inputGroup = toggle.expandToInclude(
        tester.getRect(find.byTooltip('发送')),
      );
      expect(inputGroup.center.dx, closeTo(size.width / 2, 1));
      await tester.tap(find.byIcon(Icons.subtitles_outlined));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final hangup = tester.getRect(find.byIcon(Icons.call_end));
      expect(hangup.bottom, lessThanOrEqualTo(size.height));
      expect(hangup.top, greaterThanOrEqualTo(0));
      expect(find.byIcon(Icons.call_end).hitTestable(), findsOneWidget);
      await tester.tap(find.byIcon(Icons.subtitles));
      await tester.pump();
      await _snapshot(tester, screen, 'actions_${size.width.toInt()}');
    }
    await tester.binding.setSurfaceSize(null);
    await tester.pump(const Duration(milliseconds: 300));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 600)),
    );
    await tester.pumpAndSettle();
    final before = llm.requests;
    final actor = tester.widget<Live2DActor>(find.byType(Live2DActor)).actor;
    for (final command in ['抱抱', '微笑', '摆手', '眨眼', '摇头', '点头', '停止']) {
      final version = actor.actionVersion;
      tester.widget<TextField>(find.byType(TextField)).controller!.text =
          command;
      await tester.tap(find.byTooltip('发送'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(actor.actionVersion, version + 1);
    }
    tester.widget<TextField>(find.byType(TextField)).controller!.text = '抬腿';
    await tester.tap(find.byTooltip('发送'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('当前模型不支持此动作'), findsOneWidget);
    expect(llm.requests, greaterThan(before));
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

    await container
        .read(outputModeProvider.notifier)
        .select(OutputMode.speechAndText);
    router.push('/call/$id?video=1');
    await _waitForCall(tester);
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
    expect(find.textContaining('这是通话语音测试'), findsOneWidget);
    expect(find.byType(Scrollbar), findsWidgets);
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
    llm.continueReply = null;
    await container.read(outputModeProvider.notifier).select(OutputMode.text);
    for (var call = 0; call < 3; call++) {
      router.push('/call/$id?video=1');
      await _waitForCall(tester);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 1)),
      );
      await tester.pump();
      await tester.tap(find.byIcon(Icons.call_end));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)),
      );
      expect(find.text('Chat remains open'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await tester.pumpWidget(const SizedBox.shrink());
    router.dispose();
    container.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });
}
