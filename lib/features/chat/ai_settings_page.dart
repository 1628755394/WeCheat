import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/ai_prompt.dart';
import '../../services/ollama_service.dart';
import '../common/edit_field_page.dart';

/// AI 设置页：角色人设 / 知识库 / 聊天记录样本（风格模仿）
class AiSettingsPage extends ConsumerWidget {
  final String conversationId;

  const AiSettingsPage({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(aiProfileProvider(conversationId));
    final notifier = ref.read(aiProfileProvider(conversationId).notifier);

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
            child: Column(
              children: [
                ListTile(
                  title: const Text('聊天记录样本',
                      style: TextStyle(fontSize: 16)),
                  subtitle: Text(
                    profile.chatLog.isEmpty
                        ? '带发言人名字的记录会解析成真实对话，效果更好'
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
                    hint: 'PC微信：右键消息→多选→勾选→复制，粘贴到这里即可\n也支持"名字: 内容"单行格式\n只贴目标人物一人的台词也行',
                    onSave: notifier.setChatLog,
                  ),
                ),
                // 解析状态反馈：让用户知道记录是否真的被读懂
                if (profile.chatLog.isNotEmpty) _parseStatus(profile.chatLog),
              ],
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

  /// 聊天记录解析状态：识别出对话轮次显示模仿对象，否则提示格式问题
  Widget _parseStatus(String chatLog) {
    final parsed = parseChatLog(chatLog);
    final String text;
    final Color color;
    if (parsed.turns.isNotEmpty) {
      text = '已识别 ${parsed.turns.length} 轮对话，模仿对象：${parsed.target}';
      color = AppColors.primary;
    } else {
      text = '未识别发言人名字，整段仅作风格示例（建议加"名字:"前缀或"名字 时间"行）';
      color = Colors.orange;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
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
                          .read(aiProfileProvider(conversationId).notifier)
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
