import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart' show FTheme;
import 'package:wecheat/core/theme.dart';
import 'package:wecheat/core/widgets/wechat_dialog.dart';
import 'package:wecheat/features/chat/ai_settings_page.dart';
import 'package:wecheat/features/chat/chat_info_page.dart';
import 'package:wecheat/features/chat/chat_page.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/contact.dart';
import 'package:wecheat/models/conversation.dart';
import 'package:wecheat/models/message.dart';
import 'package:wecheat/models/mood_state.dart';
import 'package:wecheat/providers/ai_profile_provider.dart';
import 'package:wecheat/providers/chat_provider.dart';
import 'package:wecheat/providers/contact_override_provider.dart';
import 'package:wecheat/providers/conversation_provider.dart';
import 'package:wecheat/providers/output_mode_provider.dart';
import 'package:wecheat/providers/mood_provider.dart';
import 'package:wecheat/providers/user_provider.dart';
import 'package:wecheat/services/llm_service.dart';
import 'package:wecheat/services/ollama_service.dart';
import 'package:wecheat/services/remote_llm_service.dart';
import 'package:wecheat/features/chat/message_translation_dialog.dart';

Widget _foruiBuilder(BuildContext context, Widget? child) => FTheme(
  data: appForuiTheme,
  child: child ?? const SizedBox.shrink(),
);

class _Conversations extends ConversationList {
  @override
  Future<List<Conversation>> build() async => [
    for (final id in ['a', 'b'])
      Conversation(
        id: id,
        contact: Contact(id: id, name: id),
        lastMessage: '',
        lastMessageTime: DateTime.now(),
      ),
  ];
}

class _Background extends ChatBackgroundNotifier {
  _Background(super.id);
  @override
  ChatBackground build() => const ChatBackground();
}

class _Messages extends ChatMessages {
  _Messages(super.id);
  @override
  Future<ChatState> build() async => ChatState(
    messages: [
      for (var index = 0; index < 100; index++)
        Message(
          id: '$index',
          conversationId: conversationId,
          senderId: 'me',
          isMe: true,
          type: MessageType.text,
          content: '$conversationId 消息 $index',
          createdAt: DateTime(2026, 10, 10),
        ),
    ],
  );
}

class _User extends CurrentUser {
  @override
  Contact build() => const Contact(id: 'me', name: '我');
}

class _Overrides extends ContactOverrides {
  @override
  Map<String, Contact> build() => {};
}

class _Output extends OutputModeNotifier {
  @override
  OutputMode build() => OutputMode.text;
}

class _Mood extends MoodNotifier {
  _Mood(super.id);
  @override
  MoodState build() => MoodState();
}

class _Profile extends AiProfileNotifier {
  _Profile(super.id);
  int deleted = 0;
  @override
  Future<void> ensureLoaded() async {}
  @override
  AiProfile build() => AiProfile(
    voiceBytes: Uint8List.fromList([1, 2]),
    voiceName: '测试音色',
    voiceCloneProfileId: 'clone',
  );
  @override
  Future<void> clearAllVoice() async {
    deleted++;
    state = state.copyWith(clearVoice: true, clearSoulNexusVoice: true);
  }
}

class _TranslationLlm extends LlmService {
  _TranslationLlm() : super(OllamaService(), RemoteLlmService());
  final prompts = <String>[];
  @override
  Stream<String> chat(
    AiProfile profile,
    List<({String role, String content})> history, {
    String? systemPrompt,
  }) async* {
    prompts.add(systemPrompt!);
    yield systemPrompt.contains('翻译成日语') ? 'こんにちは' : 'Hello';
  }
}

ProviderContainer _container({LlmService? llm}) => ProviderContainer(
  overrides: [
    if (llm != null) llmServiceProvider.overrideWithValue(llm),
    conversationListProvider.overrideWith(_Conversations.new),
    for (final id in ['a', 'b'])
      chatBackgroundProvider(id).overrideWith(() => _Background(id)),
    for (final id in ['a', 'b'])
      chatMessagesProvider(id).overrideWith(() => _Messages(id)),
    currentUserProvider.overrideWith(_User.new),
    contactOverridesProvider.overrideWith(_Overrides.new),
    outputModeProvider.overrideWith(_Output.new),
    for (final id in ['a', 'b'])
      aiProfileProvider(id).overrideWith(() => _Profile(id)),
    for (final id in ['a', 'b']) moodProvider(id).overrideWith(() => _Mood(id)),
  ],
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('com.llfbandit.record/messages'),
          (_) async => null,
        );
  });
  testWidgets(
    'long press opens compact menu and translation language can change',
    (tester) async {
      final llm = _TranslationLlm();
      final container = _container(llm: llm);
      addTearDown(container.dispose);
      // The translation has its own scope so no real model service is contacted.
      await container.read(conversationListProvider.future);
      await tester.binding.setSurfaceSize(const Size(320, 568));
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: _foruiBuilder,
            home: const ChatPage(conversationId: 'a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.longPress(find.text('a 消息 99'));
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('翻译'), findsOneWidget);
      expect(find.text('放大阅读'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: _foruiBuilder,
            home: const Scaffold(
              body: MessageTranslationDialog(text: '你好', profileId: 'a'),
            ),
          ),
        ),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(llm.prompts, hasLength(1));
      expect(find.text('Hello'), findsOneWidget);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('日语').last);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pumpAndSettle();
      expect(find.text('こんにちは'), findsOneWidget);
      expect(llm.prompts.length, 2);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );
  testWidgets('cached chat and reused chat page open at latest message', (
    tester,
  ) async {
    final container = _container();
    addTearDown(container.dispose);
    await container.read(conversationListProvider.future);
    await container.read(chatMessagesProvider('a').future);
    await container.read(chatMessagesProvider('b').future);
    Future<void> open(String id) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: _foruiBuilder,
            home: ChatPage(conversationId: id),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<ListView>(find.byType(ListView).first).reverse,
        isFalse,
      );
      expect(find.text('$id 消息 99'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }

    await open('a');
    await tester.drag(find.byType(ListView), const Offset(0, 500));
    await tester.pumpAndSettle();
    expect(find.text('a 消息 99'), findsNothing);
    await open('b');
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'background palette is a scrollable dialog on small and landscape screens',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await container.read(conversationListProvider.future);
      for (final size in [const Size(320, 568), const Size(568, 320)]) {
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              theme: buildAppTheme(),
              builder: _foruiBuilder,
              home: const ChatInfoPage(conversationId: 'a'),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('聊天背景'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('聊天背景'));
        await tester.pumpAndSettle();
        expect(find.byType(WeChatDialog), findsOneWidget);
        expect(find.text('从相册选择'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('取消'));
        await tester.pumpAndSettle();
      }
      await tester.pumpWidget(const SizedBox());
      await tester.binding.setSurfaceSize(null);
    },
  );

  testWidgets(
    'voice is deleted only after confirmation and cancel preserves it',
    (tester) async {
      final container = _container();
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: buildAppTheme(),
            builder: _foruiBuilder,
            home: const AiSettingsPage(conversationId: 'a'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('删除当前音色'),
        400,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除当前音色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
      final profile =
          container.read(aiProfileProvider('a').notifier) as _Profile;
      expect(profile.deleted, 0);
      await tester.tap(find.text('删除当前音色'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(profile.deleted, 1);
      expect(container.read(aiProfileProvider('a')).voiceBytes, isNull);
      expect(container.read(aiProfileProvider('a')).hasSoulNexusVoice, isFalse);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
