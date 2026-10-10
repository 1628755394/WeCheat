import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/ai_profile_provider.dart';
import '../../services/live2d_import_service.dart';

class Live2DModelTile extends ConsumerStatefulWidget {
  const Live2DModelTile({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<Live2DModelTile> createState() => _Live2DModelTileState();
}

class _Live2DModelTileState extends ConsumerState<Live2DModelTile> {
  bool _busy = false;

  Future<void> _import() async {
    setState(() => _busy = true);
    final notifier = ref.read(
      aiProfileProvider(widget.conversationId).notifier,
    );
    try {
      final model = await pickLive2dModel();
      if (model != null) await notifier.setLive2dModel(model);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$error')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final model = ref
        .watch(aiProfileProvider(widget.conversationId))
        .live2dModel;
    return ListTile(
      leading: const Icon(Icons.accessibility_new),
      title: const Text('视频通话模型'),
      subtitle: Text(_busy ? '正在导入…' : (model?.name ?? '未导入 · 使用头像')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (model != null)
            IconButton(
              tooltip: '移除模型',
              icon: const Icon(Icons.delete_outline),
              onPressed: _busy
                  ? null
                  : () => ref
                        .read(aiProfileProvider(widget.conversationId).notifier)
                        .setLive2dModel(null),
            ),
          IconButton(
            tooltip: '导入模型',
            icon: const Icon(Icons.file_upload_outlined),
            onPressed: _busy ? null : _import,
          ),
        ],
      ),
      onTap: _busy ? null : _import,
    );
  }
}
