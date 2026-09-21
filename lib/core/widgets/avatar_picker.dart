import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../constants.dart';

/// 内置头像候选（assets/avatars 下全部图片）
const avatarChoices = [
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

/// 通用换头像弹窗：从相册选择 / 内置头像网格
Future<void> showAvatarPicker(
  BuildContext context, {
  required Future<void> Function(Uint8List bytes) onBytes,
  required Future<void> Function(String asset) onAsset,
}) {
  return showModalBottomSheet(
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
              await onBytes(await picked.readAsBytes());
            },
          ),
          const Divider(height: 1),
          ListTile(
            title: const Center(child: Text('选择内置头像')),
            onTap: () {
              Navigator.pop(sheetContext);
              _showBuiltinGrid(context, onAsset);
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

void _showBuiltinGrid(
    BuildContext context, Future<void> Function(String) onAsset) {
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
          for (final asset in avatarChoices)
            GestureDetector(
              onTap: () {
                Navigator.pop(sheetContext);
                onAsset(asset);
              },
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppDimens.avatarRadius),
                child: Image.asset(asset, fit: BoxFit.cover),
              ),
            ),
        ],
      ),
    ),
  );
}
