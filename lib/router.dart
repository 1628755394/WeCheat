import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'features/call/call_page.dart';
import 'features/chat/chat_info_page.dart';
import 'features/chat/chat_page.dart';
import 'features/contact/contact_page.dart';
import 'features/conversation/conversation_page.dart';
import 'features/discover/discover_page.dart';
import 'features/discover/moments_page.dart';
import 'features/home/home_shell.dart';
import 'features/mine/mine_page.dart';
import 'features/mine/profile_page.dart';

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
            ChatPage(conversationId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: '/chat/:id/info',
        builder: (context, state) =>
            ChatInfoPage(conversationId: state.pathParameters['id']!),
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
    ],
  ),
);
