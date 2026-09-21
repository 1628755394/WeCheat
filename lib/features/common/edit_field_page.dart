import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 通用字段编辑页：标题 + 输入框 + 完成按钮，pop 返回输入值
/// maxLines > 1 时为多行输入（人设/知识库/聊天记录用）
class EditFieldPage extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;
  final int maxLines;

  const EditFieldPage({
    super.key,
    required this.title,
    this.initial = '',
    this.hint = '',
    this.maxLines = 1,
  });

  @override
  State<EditFieldPage> createState() => _EditFieldPageState();
}

class _EditFieldPageState extends State<EditFieldPage> {
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
          maxLines: widget.maxLines,
          maxLength: widget.maxLines > 1 ? 2000 : 24,
          decoration: InputDecoration(
            hintText: widget.hint.isEmpty ? '请输入${widget.title}' : widget.hint,
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
