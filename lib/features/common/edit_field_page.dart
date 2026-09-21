import 'package:flutter/material.dart';

import '../../core/constants.dart';

/// 通用单字段编辑页：标题 + 输入框 + 完成按钮，pop 返回输入值
class EditFieldPage extends StatefulWidget {
  final String title;
  final String initial;
  final String hint;

  const EditFieldPage({
    super.key,
    required this.title,
    this.initial = '',
    this.hint = '',
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
          maxLength: 24,
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
