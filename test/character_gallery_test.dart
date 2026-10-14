import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:forui/forui.dart';
import 'package:go_router/go_router.dart';
import 'package:wecheat/core/theme.dart';
import 'package:wecheat/features/discover/character_feed_page.dart';
import 'package:wecheat/features/discover/character_gallery_widgets.dart';
import 'package:wecheat/features/discover/discover_page.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/contact.dart';
import 'package:wecheat/providers/ai_profile_provider.dart';
import 'package:wecheat/providers/contact_override_provider.dart';
import 'package:wecheat/repositories/ai_characters.dart';

class _Profiles extends AiProfileNotifier {
  _Profiles(super.conversationId);

  @override
  AiProfile build() => conversationId == 'conv_char_fengbaobao'
      ? const AiProfile(persona: '喜欢吃火锅的宝儿姐', greeting: '走，吃火锅去。')
      : const AiProfile();
}

class _Contacts extends ContactOverrides {
  @override
  Map<String, Contact> build() => {
    'char_fengbaobao': const Contact(
      id: 'char_fengbaobao',
      name: '冯宝宝',
      remark: '宝儿姐',
      isAi: true,
    ),
  };
}

Widget _app(Widget home, {double scale = 1, GoRouter? router}) {
  Widget builder(BuildContext context, Widget? child) => FTheme(
    data: appForuiTheme,
    child: MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
  );
  return ProviderScope(
    overrides: [
      for (final character in AiCharacters.all)
        aiProfileProvider(character.conversationId)
            .overrideWith(() => _Profiles(character.conversationId)),
      contactOverridesProvider.overrideWith(_Contacts.new),
    ],
    child: router == null
        ? MaterialApp(theme: buildAppTheme(), builder: builder, home: home)
        : MaterialApp.router(
            theme: buildAppTheme(),
            builder: builder,
            routerConfig: router,
          ),
  );
}

void main() {
  testWidgets('gallery and discover fit mobile, desktop and larger text', (
    tester,
  ) async {
    addTearDown(() => tester.binding.setSurfaceSize(null));
    for (final size in [
      const Size(320, 568),
      const Size(390, 844),
      const Size(1280, 800),
    ]) {
      await tester.binding.setSurfaceSize(size);
      for (final page in [const DiscoverPage(), const CharacterFeedPage()]) {
        await tester.pumpWidget(_app(page));
        await tester.pumpAndSettle();
        expect(find.text('宝儿姐'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    }
    await tester.binding.setSurfaceSize(const Size(320, 568));
    await tester.pumpWidget(_app(const CharacterFeedPage(), scale: 2));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('search and source filters combine and use edited profiles', (
    tester,
  ) async {
    await tester.pumpWidget(_app(const CharacterFeedPage()));
    await tester.pumpAndSettle();
    expect(
      find.byType(CharacterGalleryCard),
      findsNWidgets(AiCharacters.all.length),
    );
    await tester.enterText(find.byType(TextField), '火锅');
    await tester.pumpAndSettle();
    expect(find.byType(CharacterGalleryCard), findsOneWidget);
    expect(find.text('走，吃火锅去。'), findsOneWidget);
    await tester.tap(find.widgetWithText(ChoiceChip, 'OVERLORD'));
    await tester.pumpAndSettle();
    expect(find.text('暂时没有找到这个角色'), findsOneWidget);
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.byType(CharacterGalleryCard), findsNWidgets(2));
    await tester.tap(find.widgetWithText(ChoiceChip, '全部'));
    await tester.enterText(find.byType(TextField), '冯宝宝');
    await tester.pumpAndSettle();
    expect(find.text('宝儿姐'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery actions keep the character chat and call destinations', (
    tester,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, _) => const CharacterFeedPage()),
        GoRoute(
          path: '/chat/:id',
          builder: (_, state) =>
              Scaffold(body: Text('chat:${state.pathParameters['id']}')),
        ),
        GoRoute(
          path: '/call/:id',
          builder: (_, state) => Scaffold(
            body: Text(
              'call:${state.pathParameters['id']}:${state.uri.queryParameters['video']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(_app(const CharacterFeedPage(), router: router));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '冯宝宝');
    await tester.pumpAndSettle();
    final chat = find.widgetWithText(FButton, '开始聊天');
    await tester.ensureVisible(chat);
    await tester.pumpAndSettle();
    await tester.tap(chat);
    await tester.pumpAndSettle();
    expect(find.text('chat:conv_char_fengbaobao'), findsOneWidget);
    router.pop();
    await tester.pumpAndSettle();
    final call = find.byIcon(Icons.call_outlined);
    await tester.ensureVisible(call);
    await tester.pumpAndSettle();
    await tester.tap(call);
    await tester.pumpAndSettle();
    expect(find.text('call:conv_char_fengbaobao:0'), findsOneWidget);
  });
}
