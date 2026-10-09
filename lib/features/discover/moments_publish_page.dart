import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/constants.dart';
import '../../providers/moments_provider.dart';

/// 发朋友圈：文字 + 最多 9 张图
class MomentsPublishPage extends ConsumerStatefulWidget {
  const MomentsPublishPage({super.key});

  @override
  ConsumerState<MomentsPublishPage> createState() =>
      _MomentsPublishPageState();
}

class _MomentsPublishPageState extends ConsumerState<MomentsPublishPage> {
  final _controller = TextEditingController();
  final List<Uint8List> _images = [];
  bool _publishing = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    try {
      final picked = await ImagePicker().pickMultiImage(
          maxWidth: 1600, imageQuality: 80);
      for (final f in picked) {
        if (_images.length >= 9) break;
        _images.add(await f.readAsBytes());
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _publish() async {
    if (_controller.text.trim().isEmpty && _images.isEmpty) return;
    setState(() => _publishing = true);
    await ref
        .read(momentsProvider.notifier)
        .publish(_controller.text.trim(), List.of(_images));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final canPublish =
        _controller.text.trim().isNotEmpty || _images.isNotEmpty;
    return Scaffold(
      appBar: AppBar(
        title: const Text('发朋友圈'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.primary,
                disabledBackgroundColor: AppColors.divider,
              ),
              onPressed:
                  canPublish && !_publishing ? _publish : null,
              child: Text(_publishing ? '发表中…' : '发表'),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _controller,
            maxLines: 6,
            minLines: 4,
            decoration: const InputDecoration(
              hintText: '这一刻的想法…',
              border: InputBorder.none,
            ),
            onChanged: (_) => setState(() {}),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (var i = 0; i < _images.length; i++)
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: Image.memory(_images[i],
                          width: 90, height: 90, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 0,
                      right: 0,
                      child: GestureDetector(
                        onTap: () => setState(() => _images.removeAt(i)),
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Colors.black54,
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close,
                              size: 16, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                ),
              if (_images.length < 9)
                GestureDetector(
                  onTap: _pick,
                  child: Container(
                    width: 90,
                    height: 90,
                    color: AppColors.searchBg,
                    child: const Icon(Icons.add,
                        size: 36, color: AppColors.textSecondary),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
