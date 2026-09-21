import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/ollama_service.dart';
import '../common/edit_field_page.dart';

/// AI 设置页：角色人设 / 知识库 / 聊天记录样本（风格模仿）
class AiSettingsPage extends ConsumerWidget {
  final String conversationId;

  const AiSettingsPage({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(aiProfileProvider);
    final notifier = ref.read(aiProfileProvider.notifier);

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('AI 设置')),
      body: ListView(
        children: [
          const _SectionHeader('模型'),
          Material(
            color: Colors.white,
            child: ListTile(
              leading:
                  const Icon(Icons.memory, color: AppColors.primary),
              title: const Text('本地模型', style: TextStyle(fontSize: 16)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    profile.model.isEmpty
                        ? '默认 ${OllamaService.defaultModel}'
                        : profile.model,
                    style: const TextStyle(
                        fontSize: 14, color: AppColors.textSecondary),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.chevron_right,
                      color: AppColors.textSecondary),
                ],
              ),
              onTap: () => _pickModel(context, ref, profile.model),
            ),
          ),
          const _SectionHeader('角色卡'),
          Material(
            color: Colors.white,
            child: ListTile(
              title: const Text('人设', style: TextStyle(fontSize: 16)),
              subtitle: Text(
                profile.persona.isEmpty ? '未设置，默认 AI 助手' : profile.persona,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
              onTap: () => _edit(
                context,
                title: '人设',
                initial: profile.persona,
                hint: '例：你是"林晓雨"，25岁产品经理，说话温柔爱用语气词，回复简短',
                onSave: notifier.setPersona,
              ),
            ),
          ),
          const _SectionHeader('知识库（回答时自动检索相关条目）'),
          Material(
            color: Colors.white,
            child: Column(
              children: [
                for (var i = 0; i < profile.knowledge.length; i++) ...[
                  if (i > 0) const Divider(indent: 16, height: 1),
                  ListTile(
                    title: Text(
                      profile.knowledge[i],
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14),
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline,
                          color: AppColors.textSecondary, size: 20),
                      onPressed: () => notifier.removeKnowledge(i),
                    ),
                    onTap: () => _edit(
                      context,
                      title: '知识条目',
                      initial: profile.knowledge[i],
                      onSave: (v) => notifier.updateKnowledge(i, v),
                    ),
                  ),
                ],
                if (profile.knowledge.isNotEmpty)
                  const Divider(indent: 16, height: 1),
                ListTile(
                  leading: const Icon(Icons.add, color: AppColors.primary),
                  title: const Text('添加知识条目',
                      style: TextStyle(fontSize: 16, color: AppColors.primary)),
                  onTap: () => _edit(
                    context,
                    title: '知识条目',
                    hint: '例：用户叫小明，喜欢篮球，生日是3月15日',
                    onSave: notifier.addKnowledge,
                  ),
                ),
              ],
            ),
          ),
          const _SectionHeader('聊天记录（AI 会模仿其中人物的语气）'),
          Material(
            color: Colors.white,
            child: ListTile(
              title: const Text('聊天记录样本', style: TextStyle(fontSize: 16)),
              subtitle: Text(
                profile.chatLog.isEmpty
                    ? '粘贴导出的聊天记录，如微信/QQ导出的对话文本'
                    : profile.chatLog,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 13, color: AppColors.textSecondary),
              ),
              trailing: const Icon(Icons.chevron_right,
                  color: AppColors.textSecondary),
              onTap: () => _edit(
                context,
                title: '聊天记录样本',
                initial: profile.chatLog,
                hint: '粘贴聊天记录原文，如：\n林晓雨 14:20\n晚上一起吃饭吗\n我 14:21\n好啊，去哪吃',
                onSave: notifier.setChatLog,
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '说明：人设会替换默认提示词；知识库按提问相关性检索注入；聊天记录作为风格参考。内容存本地 Hive，仅发送给本地 Ollama。',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
          ),
        ],
      ),
    );
  }

  /// 模型选择：从本机 Ollama 拉已安装模型列表
  void _pickModel(BuildContext context, WidgetRef ref, String current) {
    showModalBottomSheet(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: FutureBuilder<List<String>>(
          future: ref.read(ollamaServiceProvider).listModels(),
          builder: (context, snapshot) {
            final models = snapshot.data ?? [];
            if (snapshot.hasError || models.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(
                  child: Text('无法获取模型列表，请确认 Ollama 正在运行',
                      style:
                          TextStyle(color: AppColors.textSecondary)),
                ),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final m in models)
                  ListTile(
                    title: Text(m),
                    trailing: (current.isEmpty &&
                                m == OllamaService.defaultModel) ||
                            current == m
                        ? const Icon(Icons.check, color: AppColors.primary)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      ref
                          .read(aiProfileProvider.notifier)
                          .setModel(m);
                    },
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context, {
    required String title,
    String initial = '',
    String hint = '',
    required Future<void> Function(String) onSave,
  }) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) =>
            EditFieldPage(title: title, initial: initial, hint: hint, maxLines: 8),
      ),
    );
    if (result != null) await onSave(result.trim());
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}
