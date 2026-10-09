import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/llm_service.dart';
import '../../services/writing_draft.dart';

class WritingAssistantPage extends ConsumerStatefulWidget {
  const WritingAssistantPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<WritingAssistantPage> createState() =>
      _WritingAssistantPageState();
}

class _WritingAssistantPageState extends ConsumerState<WritingAssistantPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  final _messages = <({bool isMe, String text})>[];
  WritingDraft? _draft;
  Box? _box;
  bool _busy = false;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    await ref
        .read(aiProfileProvider(widget.conversationId).notifier)
        .ensureLoaded();
    final box = await Hive.openBox('writing_assistant');
    final saved = box.get(widget.conversationId);
    if (!mounted) return;
    setState(() {
      _box = box;
      _draft = saved is Map && saved['dirty'] == true && saved['draft'] is Map
          ? WritingDraft.fromMap(saved['draft'] as Map)
          : WritingDraft.fromProfile(
              ref.read(aiProfileProvider(widget.conversationId)),
            );
      if (saved is Map && saved['messages'] is List) {
        for (final item in saved['messages'] as List) {
          if (item is Map && item['text'] is String) {
            _messages.add((
              isMe: item['isMe'] == true,
              text: item['text'] as String,
            ));
          }
        }
      }
      _dirty = saved is Map && saved['dirty'] == true;
    });
  }

  Future<void> _save() async {
    final box = _box;
    final draft = _draft;
    if (box == null || draft == null) return;
    await box.put(widget.conversationId, {
      'draft': draft.toMap(),
      'dirty': _dirty,
      'messages': [
        for (final message in _messages)
          {'isMe': message.isMe, 'text': message.text},
      ],
    });
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final draft = _draft;
    if (text.isEmpty || draft == null || _busy) return;
    _input.clear();
    setState(() {
      _messages.add((isMe: true, text: text));
      _busy = true;
    });
    _scrollToEnd();
    await _save();
    try {
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      final history = [
        for (final message in _messages.reversed.take(12).toList().reversed)
          (role: message.isMe ? 'user' : 'assistant', content: message.text),
      ];
      final result = StringBuffer();
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(
                profile,
                history,
                systemPrompt: writingAssistantPrompt(draft),
              )) {
        result.write(chunk);
      }
      final parsed = parseWritingReply(result.toString(), draft);
      if (!mounted) return;
      setState(() {
        _draft = parsed.draft;
        _dirty = true;
        _messages.add((isMe: false, text: parsed.reply));
      });
      await _save();
      _scrollToEnd();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is FormatException
                ? error.message
                : LlmService.friendlyError(error),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    final draft = _draft;
    if (draft == null || !_dirty || _busy) return;
    await ref
        .read(aiProfileProvider(widget.conversationId).notifier)
        .importWriting(
          persona: draft.persona,
          greeting: draft.greeting,
          chatLog: draft.chatLog,
          rules: draft.rules,
        );
    if (!mounted) return;
    setState(() => _dirty = false);
    await _save();
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('已导入到此角色')));
    }
  }

  @override
  void dispose() {
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    return Scaffold(
      backgroundColor: AppColors.chatBg,
      appBar: AppBar(title: const Text('人设创作助手')),
      body: draft == null
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Material(
                  color: Colors.white,
                  child: ExpansionTile(
                    initiallyExpanded: _dirty,
                    leading: const Icon(Icons.description_outlined),
                    title: const Text('待导入草稿'),
                    subtitle: Text(
                      _dirty ? '有未导入的修改' : '当前角色资料',
                      style: const TextStyle(fontSize: 12),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      _draftField('人设', draft.persona),
                      _draftField('开场白', draft.greeting),
                      _draftField('对话样本', draft.chatLog),
                      _draftField('自定义规则', draft.rules.join('\n')),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.icon(
                          onPressed: _dirty && !_busy ? _import : null,
                          icon: const Icon(Icons.download_done, size: 18),
                          label: const Text('导入到此角色'),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_busy ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length) {
                        return const Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          ),
                        );
                      }
                      final message = _messages[index];
                      return Align(
                        alignment: message.isMe
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          constraints: const BoxConstraints(maxWidth: 520),
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: message.isMe
                                ? AppColors.bubbleMe
                                : Colors.white,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(message.text),
                        ),
                      );
                    },
                  ),
                ),
                SafeArea(
                  top: false,
                  child: Container(
                    color: Colors.white,
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _input,
                            enabled: !_busy,
                            minLines: 1,
                            maxLines: 4,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) => _send(),
                            decoration: const InputDecoration(
                              hintText: '描述想要的角色或修改要求',
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: '发送',
                          onPressed: _busy ? null : _send,
                          icon: const Icon(Icons.send),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _draftField(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Align(
      alignment: Alignment.centerLeft,
      child: Text(
        '$label：${value.isEmpty ? '未设置' : value}',
        maxLines: 5,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
    ),
  );
}
