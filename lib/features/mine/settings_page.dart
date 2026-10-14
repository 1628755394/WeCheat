import '../../core/widgets/app_page_body.dart';
import '../../core/widgets/wechat_dialog.dart';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' show FTile, FTileGroup;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_visual.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../providers/call_performance_provider.dart';
import '../contact/add_ai_friend_page.dart';

/// 设置页：数据管理 + 关于
class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(title: const Text('设置')),
      body: AppPageBody(
        child: ListView(
          children: [
            const AppSectionLabel('通话偏好'),
            AppPanel(
              child: SwitchListTile(
                title: const Text('通话动画'),
                value: ref.watch(callPerformanceProvider).animationsEnabled,
                onChanged: (value) =>
                    ref.read(callPerformanceProvider.notifier).select(value),
              ),
            ),
            const AppSectionLabel('好友与数据'),
            AppPanel(
              child: FTileGroup(
                children: [
                  FTile(
                    prefix: const Icon(
                      Icons.person_add_alt_1,
                      color: AppColors.primary,
                    ),
                    title: const Text('添加 AI 好友'),
                    suffix: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onPress: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AddAiFriendPage(),
                      ),
                    ),
                  ),
                  FTile(
                    prefix: const Icon(
                      Icons.cleaning_services_outlined,
                      color: Colors.orange,
                    ),
                    title: const Text('清空全部聊天记录'),
                    subtitle: const Text(
                      '删除所有会话的消息，保留联系人与 AI 配置',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    onPress: () => _clearMessages(context, ref),
                  ),
                  FTile(
                    prefix: const Icon(Icons.restart_alt, color: Colors.red),
                    title: const Text(
                      '重置应用数据',
                      style: TextStyle(color: Colors.red),
                    ),
                    subtitle: const Text(
                      '清空 Hive 全部数据并重新播种，慎用',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    onPress: () => _resetAll(context),
                  ),
                ],
              ),
            ),
            const AppSectionLabel('关于'),
            AppPanel(
              child: FTileGroup(
                children: [
                  FTile(
                    prefix: Icon(Icons.info_outline, color: AppColors.primary),
                    title: Text('关于 WeCheat'),
                    subtitle: Text(
                      'Flutter 仿微信 · AI 角色扮演客户端',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _clearMessages(BuildContext context, WidgetRef ref) async {
    final ok = await _confirm(context, '清空全部聊天记录', '所有会话的消息将被删除');
    if (ok != true) return;
    final repo = ref.read(messageRepositoryProvider);
    await repo.init();
    await Hive.box('messages').clear();
    ref.invalidate(conversationListProvider);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已清空'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _resetAll(BuildContext context) async {
    final ok = await _confirm(
      context,
      '重置应用数据',
      '将删除全部会话、消息、AI 配置与个人信息，应用下次启动时重新播种。\n此操作不可恢复！',
    );
    if (ok != true) return;
    await Hive.openBox('chat_backgrounds');
    for (final name in const [
      'messages',
      'conversations',
      'ai_profiles',
      'chat_backgrounds',
      'contact_overrides',
      'user',
      'moments',
      'contact_tags',
    ]) {
      if (Hive.isBoxOpen(name)) await Hive.box(name).clear();
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已重置，重启应用后生效'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  Future<bool?> _confirm(BuildContext context, String title, String body) =>
      showDialog<bool>(
        context: context,
        builder: (ctx) => WeChatDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('确定', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      );
}
