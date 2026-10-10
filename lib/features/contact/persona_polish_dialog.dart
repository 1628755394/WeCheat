import '../../core/widgets/wechat_dialog.dart';

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/ai_profile.dart';
import '../../providers/chat_provider.dart';
import '../../services/llm_service.dart';

String personaPolishPrompt(String name, String persona) =>
    '''
你是角色设定编辑。根据用户的润色要求，改写当前人设；人设为空时按需求创作。
保留用户指定的身份、性格、关系和说话习惯，不擅自改变核心设定。
补充可用于角色扮演的具体细节，避免空泛形容和重复，使用中文。
只输出完整人设正文，不输出解释、标题、Markdown 或开场白。
当前角色资料：${jsonEncode({'name': name, 'persona': persona})}
''';

class PersonaPolishDialog extends ConsumerStatefulWidget {
  const PersonaPolishDialog({
    super.key,
    required this.profile,
    required this.name,
    required this.persona,
  });
  final AiProfile profile;
  final String name;
  final String persona;
  @override
  ConsumerState<PersonaPolishDialog> createState() =>
      _PersonaPolishDialogState();
}

class _PersonaPolishDialogState extends ConsumerState<PersonaPolishDialog> {
  final _requirements = TextEditingController();
  final _draft = TextEditingController();
  StreamSubscription<String>? _subscription;
  Timer? _timeout;
  bool _busy = false;
  bool _ready = false;
  String? _error;

  void _cancel() {
    _timeout?.cancel();
    unawaited(_subscription?.cancel());
    _subscription = null;
    if (mounted) {
      setState(() {
        _busy = false;
        _ready = false;
      });
    }
  }

  void _generate() {
    if (_busy || _requirements.text.trim().isEmpty) return;
    setState(() {
      _busy = true;
      _ready = false;
      _error = null;
      _draft.clear();
    });
    void fail(Object error) {
      _cancel();
      if (mounted) setState(() => _error = LlmService.friendlyError(error));
    }

    _timeout = Timer(const Duration(seconds: 90), () => fail('生成超时，请重试'));
    _subscription = ref
        .read(llmServiceProvider)
        .chat(widget.profile, [
          (role: 'user', content: _requirements.text.trim()),
        ], systemPrompt: personaPolishPrompt(widget.name, widget.persona))
        .listen(
          (chunk) {
            if (!mounted) return;
            _draft.text += chunk;
          },
          onError: fail,
          onDone: () {
            _timeout?.cancel();
            _subscription = null;
            if (!mounted) return;
            setState(() {
              _busy = false;
              _ready = _draft.text.trim().isNotEmpty;
              if (!_ready) _error = '模型未返回人设，请重试';
            });
          },
          cancelOnError: true,
        );
  }

  @override
  void dispose() {
    _timeout?.cancel();
    unawaited(_subscription?.cancel());
    _requirements.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WeChatDialog(
    title: const Text('润色人设'),
    content: SizedBox(
      width: 480,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _requirements,
              enabled: !_busy,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '润色要求',
                hintText: '例如：保留温柔性格，补充职业背景，语气更自然',
              ),
            ),
            const SizedBox(height: 12),
            if (_busy) const LinearProgressIndicator(),
            TextField(
              controller: _draft,
              onChanged: (value) =>
                  setState(() => _ready = value.trim().isNotEmpty),
              readOnly: _busy,
              minLines: 5,
              maxLines: 10,
              decoration: const InputDecoration(labelText: '人设草稿'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      if (_busy)
        TextButton(onPressed: _cancel, child: const Text('停止生成'))
      else
        TextButton(onPressed: _generate, child: const Text('生成')),
      FilledButton(
        onPressed: !_busy && _ready
            ? () {
                if (_draft.text.trim().isNotEmpty) {
                  Navigator.pop(context, _draft.text.trim());
                }
              }
            : null,
        child: const Text('采用'),
      ),
    ],
  );
}
