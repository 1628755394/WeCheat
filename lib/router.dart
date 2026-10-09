import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/call/call_page.dart';
import 'features/chat/ai_settings_page.dart';
import 'features/chat/chat_info_page.dart';
import 'features/chat/chat_page.dart';
import 'features/contact/contact_page.dart';
import 'features/conversation/conversation_page.dart';
import 'features/discover/character_feed_page.dart';
import 'features/discover/discover_misc_pages.dart';
import 'features/discover/discover_page.dart';
import 'features/discover/moments_page.dart';
import 'features/discover/scan_page.dart';
import 'features/home/home_shell.dart';
import 'features/mine/mine_misc_pages.dart';
import 'features/mine/mine_page.dart';
import 'features/mine/pay_page.dart';
import 'features/mine/profile_page.dart';
import 'features/mine/settings_page.dart';

/// 声明式路由：
/// - StatefulShellRoute 管理底部 4 个 Tab（各自独立的导航栈）
/// - /chat/:id 为全屏页面，不显示底部导航
final routerProvider = Provider<GoRouter>(
  (ref) => GoRouter(
    initialLocation: '/conversation',
    routes: [
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/conversation',
                builder: (context, state) => const ConversationPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/contact',
                builder: (context, state) => const ContactPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/discover',
                builder: (context, state) => const DiscoverPage(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/mine',
                builder: (context, state) => const MinePage(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/chat/:id',
        builder: (context, state) =>
            ResponsiveChatPage(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chat/:id/info',
        builder: (context, state) =>
            ChatInfoPage(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chat/:id/ai',
        builder: (context, state) =>
            AiSettingsPage(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/moments',
        builder: (context, state) => const MomentsPage(),
      ),
      GoRoute(
        path: '/profile',
        builder: (context, state) => const ProfilePage(),
      ),
      GoRoute(
        path: '/call/:id',
        builder: (context, state) => CallPage(
          conversationId: state.pathParameters['id']!,
          isVideo: state.uri.queryParameters['video'] == '1',
        ),
      ),
      // 功能页
      GoRoute(path: '/scan', builder: (context, state) => const ScanPage()),
      GoRoute(path: '/pay', builder: (context, state) => const PayPage()),
      GoRoute(
        path: '/qr-card',
        builder: (context, state) => const QrCardPage(),
      ),
      GoRoute(
        path: '/favorites',
        builder: (context, state) => const FavoritesPage(),
      ),
      GoRoute(
        path: '/settings',
        builder: (context, state) => const SettingsPage(),
      ),
      GoRoute(
        path: '/emoji',
        builder: (context, state) => const EmojiStorePage(),
      ),
      // 发现页二级页
      GoRoute(
        path: '/discover/cards',
        builder: (context, state) => const CharacterFeedPage(),
      ),
      GoRoute(
        path: '/discover/shake',
        builder: (context, state) => const ShakePage(),
      ),
      GoRoute(
        path: '/discover/look',
        builder: (context, state) => const LookPage(),
      ),
      GoRoute(
        path: '/discover/search',
        builder: (context, state) => const GlobalSearchPage(),
      ),
    ],
  ),
);
