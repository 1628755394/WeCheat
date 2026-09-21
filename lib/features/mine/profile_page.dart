import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../providers/user_provider.dart';

/// 个人信息页：换头像、改昵称/地区（持久化到 Hive，全局生效）
class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  /// 内置头像候选（assets/avatars 下全部图片）
  static const _assetChoices = [
    'assets/avatars/me.jpg',
    'assets/avatars/c1.jpg',
    'assets/avatars/c2.jpg',
    'assets/avatars/c5.jpg',
    'assets/avatars/c6.jpg',
    'assets/avatars/c8.jpg',
    'assets/avatars/c9.jpg',
    'assets/avatars/c10.jpg',
    'assets/avatars/c11.jpg',
    'assets/avatars/c13.jpg',
    'assets/avatars/c14.jpg',
    'assets/avatars/moments_cover.jpg',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(currentUserProvider);

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('个人信息')),
      body: ListView(
        children: [
          Material(
            color: Colors.white,
            child: Column(
              children: [
                ListTile(
                  title: const Text('头像'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AppAvatar(contact: me, size: 56),
                      const SizedBox(width: 8),
                      const Icon(Icons.chevron_right,
                          color: AppColors.textSecondary),
                    ],
                  ),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  onTap: () => _pickAvatar(context, ref),
                ),
                const Divider(indent: 16),
                ListTile(
                  title: const Text('名字'),
                  trailing: _valueWithChevron(me.name),
                  onTap: () => _editField(
                      context, ref, '名字', me.name,
                      (v) => ref.read(currentUserProvider.notifier).setName(v)),
                ),
                const Divider(indent: 16),
                ListTile(
                  title: const Text('微信号'),
                  trailing: Text(me.wechatId,
                      style: const TextStyle(
                          color: AppColors.textSecondary, fontSize: 15)),
                ),
                const Divider(indent: 16),
                ListTile(
                  title: const Text('二维码名片'),
                  trailing: _valueWithChevron('', icon: Icons.qr_code_2),
                  onTap: () => _todo(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Material(
            color: Colors.white,
            child: Column(
              children: [
                const ListTile(
                  title: Text('更多信息'),
                  trailing: Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                ),
                const Divider(indent: 16),
                ListTile(
                  title: const Text('地区'),
                  trailing:
                      _valueWithChevron(me.region.isEmpty ? '未设置' : me.region),
                  onTap: () => _editField(
                      context, ref, '地区', me.region,
                      (v) => ref.read(currentUserProvider.notifier).setRegion(v)),
                ),
              ],
            ),
          ),
        ],
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
          Text(value,
              style: const TextStyle(
                  color: AppColors.textSecondary, fontSize: 15)),
        const SizedBox(width: 4),
        const Icon(Icons.chevron_right, color: AppColors.textSecondary),
      ],
    );
  }

  /// 头像底部弹窗：相册选择 或 内置头像网格
  void _pickAvatar(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: const Center(child: Text('从相册选择')),
              onTap: () async {
                Navigator.pop(sheetContext);
                final picked = await ImagePicker()
                    .pickImage(source: ImageSource.gallery, maxWidth: 512);
                if (picked == null) return;
                final bytes = await picked.readAsBytes();
                await ref
                    .read(currentUserProvider.notifier)
                    .setAvatarBytes(bytes);
              },
            ),
            const Divider(height: 1),
            ListTile(
              title: const Center(child: Text('选择内置头像')),
              onTap: () {
                Navigator.pop(sheetContext);
                _pickBuiltinAvatar(context, ref);
              },
            ),
            const Divider(height: 1),
            ListTile(
              title: const Center(
                  child: Text('取消', style: TextStyle(color: Colors.grey))),
              onTap: () => Navigator.pop(sheetContext),
            ),
          ],
        ),
      ),
    );
  }

  void _pickBuiltinAvatar(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: GridView.count(
          crossAxisCount: 4,
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          mainAxisSpacing: 12,
          crossAxisSpacing: 12,
          children: [
            for (final asset in _assetChoices)
              GestureDetector(
                onTap: () {
                  Navigator.pop(sheetContext);
                  ref
                      .read(currentUserProvider.notifier)
                      .setAvatarAsset(asset);
                },
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(AppDimens.avatarRadius),
                  child:
                      Image.asset(asset, fit: BoxFit.cover),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// 单行文本编辑页，返回保存的值
  Future<void> _editField(BuildContext context, WidgetRef ref, String title,
      String initial, Future<void> Function(String) onSave) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
          builder: (_) => _EditFieldPage(title: title, initial: initial)),
    );
    if (result != null && result.trim().isNotEmpty) {
      await onSave(result.trim());
    }
  }

  void _todo(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('功能开发中'), duration: Duration(seconds: 1)),
    );
  }
}

/// 通用单字段编辑页
class _EditFieldPage extends StatefulWidget {
  final String title;
  final String initial;

  const _EditFieldPage({required this.title, required this.initial});

  @override
  State<_EditFieldPage> createState() => _EditFieldPageState();
}

class _EditFieldPageState extends State<_EditFieldPage> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_controller.text.trim()),
            child: const Text('完成',
                style: TextStyle(color: AppColors.primary, fontSize: 16)),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: _controller,
          autofocus: true,
          maxLength: 24,
          decoration: InputDecoration(
            hintText: '请输入${widget.title}',
            filled: true,
            fillColor: AppColors.searchBg,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide.none,
            ),
          ),
          onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
        ),
      ),
    );
  }
}
