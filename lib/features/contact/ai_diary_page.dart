import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/constants.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/ai_prompt.dart';

/// AI 日记页：TA 写的私密日记，可让 TA 基于最近聊天写新的一篇
/// 存 AiProfile.diaries（'yyyy-MM-dd HH:mm|内容'）
class AiDiaryPage extends ConsumerStatefulWidget {
  final String conversationId;
  final String name;

  const AiDiaryPage(
      {super.key, required this.conversationId, required this.name});

  @override
  ConsumerState<AiDiaryPage> createState() => _AiDiaryPageState();
}

class _AiDiaryPageState extends ConsumerState<AiDiaryPage> {
  bool _writing = false;

  /// 让 TA 写日记：完整人设 prompt + 日记指令 + 最近聊天上下文
  Future<void> _writeDiary() async {
    if (_writing) return;
    setState(() => _writing = true);
    try {
      final notifier =
          ref.read(aiProfileProvider(widget.conversationId).notifier);
      await notifier.ensureLoaded();
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      final repo = ref.read(messageRepositoryProvider);
      await repo.init();
      final history = [
        for (final m in repo
            .loadByConversation(widget.conversationId)
            .reversed
            .take(12))
          if (!m.recalled)
            (role: m.isMe ? 'user' : 'assistant', content: m.content),
      ].reversed.toList();
      final systemPrompt = '${buildAiSystemPrompt(profile)}'
          '\n\n【任务】以第一人称写一篇今天的日记：记录你和 TA 最近的相处、'
          '你的心情变化、以及不敢当面说出口的话。150 字以内，私密、真实，'
          '像写在只有自己能看的日记本里，不要括号动作描写。';
      var out = '';
      await for (final chunk in ref.read(llmServiceProvider).chat(
        profile,
        history,
        systemPrompt: systemPrompt,
      )) {
        out += chunk;
      }
      final text = out.trim();
      if (text.isNotEmpty) {
        final stamp = DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now());
        await notifier.addDiary('$stamp|$text');
      }
    } finally {
      if (mounted) setState(() => _writing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final diaries =
        ref.watch(aiProfileProvider(widget.conversationId)).diaries;
    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: Text('${widget.name}的日记')),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: AppColors.primary,
        onPressed: _writing ? null : _writeDiary,
        icon: _writing
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white))
            : const Icon(Icons.edit_note, color: Colors.white),
        label: Text(_writing ? '写日记中…' : '让 TA 写日记',
            style: const TextStyle(color: Colors.white)),
      ),
      body: diaries.isEmpty
          ? const Center(
              child: Text('还没有日记\n点右下角让 TA 写一篇',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: AppColors.textSecondary)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: diaries.length,
              itemBuilder: (context, i) {
                // 最新的排在前面
                final raw = diaries[diaries.length - 1 - i];
                final idx = raw.indexOf('|');
                final stamp = idx > 0 ? raw.substring(0, idx) : '';
                final text = idx > 0 ? raw.substring(idx + 1) : raw;
                return Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.book,
                              size: 16, color: AppColors.primary),
                          const SizedBox(width: 6),
                          Text(stamp,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppColors.textSecondary)),
                          const Spacer(),
                          GestureDetector(
                            onTap: () => ref
                                .read(aiProfileProvider(
                                        widget.conversationId)
                                    .notifier)
                                .removeDiaryAt(diaries.length - 1 - i),
                            child: const Icon(Icons.delete_outline,
                                size: 18, color: AppColors.textSecondary),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(text,
                          style: const TextStyle(
                              fontSize: 15, height: 1.6)),
                    ],
                  ),
                );
              },
            ),
    );
  }
}
