import '../../core/widgets/app_page_body.dart';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' show FTile, FTileGroup;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/avatar_picker.dart';
import '../../providers/user_provider.dart';
import '../common/edit_field_page.dart';

/// 个人信息页：换头像、改昵称/地区（持久化到 Hive，全局生效）
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('个人信息')),
      body: AppPageBody(
        child: ListView(
          children: [
            FTileGroup(
              children: [
                FTile(
                  title: const Text('头像'),
                  suffix: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppAvatar(contact: me, size: 56),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.chevron_right,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  onPress: () => _pickAvatar(context, ref),
                ),
                FTile(
                  title: const Text('名字'),
                  suffix: _valueWithChevron(me.name),
                  onPress: () => _editField(
                    context,
                    ref,
                    '名字',
                    me.name,
                    (v) => ref.read(currentUserProvider.notifier).setName(v),
                  ),
                ),
                FTile(
                  title: const Text('微信号'),
                  suffix: Text(
                    me.wechatId,
                    style: const TextStyle(
                      color: AppColors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ),
                FTile(
                  title: const Text('二维码名片'),
                  suffix: _valueWithChevron('', icon: Icons.qr_code_2),
                  onPress: () => context.push('/qr-card'),
                ),
              ],
            ),
            const SizedBox(height: 8),
            FTileGroup(
              children: [
                FTile(
                  title: const Text('更多信息'),
                  suffix: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                ),
                FTile(
                  title: const Text('地区'),
                  suffix: _valueWithChevron(
                    me.region.isEmpty ? '未设置' : me.region,
                  ),
                  onPress: () => _editField(
                    context,
                    ref,
                    '地区',
                    me.region,
                    (v) =>
                        ref.read(currentUserProvider.notifier).setRegion(v),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _valueWithChevron(String value, {IconData? icon}) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (icon != null)
          const Icon(Icons.qr_code_2, size: 20, color: AppColors.textSecondary)
        else
          Text(
            value,
            style: const TextStyle(
              color: AppColors.textSecondary,
              fontSize: 15,
            ),
          ),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      ],
    );
  }

  /// 头像底部弹窗：相册选择 或 内置头像网格
  void _pickAvatar(BuildContext context, WidgetRef ref) {
    showAvatarPicker(
      context,
      onBytes: (bytes) =>
          ref.read(currentUserProvider.notifier).setAvatarBytes(bytes),
      onAsset: (asset) =>
          ref.read(currentUserProvider.notifier).setAvatarAsset(asset),
    );
  }

  /// 单行文本编辑页，返回保存的值
  Future<void> _editField(
    BuildContext context,
    WidgetRef ref,
    String title,
    String initial,
    Future<void> Function(String) onSave,
  ) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldPage(title: title, initial: initial),
      ),
    );
    if (result != null && result.trim().isNotEmpty) {
      await onSave(result.trim());
    }
  }
}
