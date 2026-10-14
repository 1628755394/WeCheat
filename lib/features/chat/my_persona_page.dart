import '../../core/widgets/app_page_body.dart';

import 'package:flutter/material.dart';
import 'package:forui/forui.dart' show FTile, FTileGroup;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/ai_profile_provider.dart';
import '../../services/ai_prompt.dart';
import '../common/edit_field_page.dart';

/// 「我与 TA」设定页：点聊天里自己的头像进入
/// 我的人设 / 我们的关系与经历 / TA 的喜好词（涨好感）/ TA 的厌恶词（掉好感）
class MyPersonaPage extends ConsumerWidget {
  final String conversationId;

  const MyPersonaPage({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(aiProfileProvider(conversationId));
    final notifier = ref.read(aiProfileProvider(conversationId).notifier);

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('我与 TA')),
      body: AppPageBody(
        child: ListView(
          children: [
            const _Header('我是谁'),
            FTileGroup(
              children: [
                FTile(
                  title: const Text('我的人设'),
                  subtitle: Text(
                    profile.userPersona.isEmpty
                        ? '未设置：告诉 TA 你的名字、身份、习惯'
                        : profile.userPersona,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  suffix: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onPress: () => _edit(
                    context,
                    title: '我的人设',
                    initial: profile.userPersona,
                    hint: '例：我叫阿哲，计算机系大四，加班狗，爱熬夜打代码',
                    onSave: notifier.setUserPersona,
                  ),
                ),
                FTile(
                  title: const Text('我们的关系与经历'),
                  subtitle: Text(
                    profile.relationship.isEmpty
                        ? '未设置：你们怎么认识的、一起经历过什么'
                        : profile.relationship,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  suffix: const Icon(
                    Icons.chevron_right,
                    color: AppColors.textSecondary,
                  ),
                  onPress: () => _edit(
                    context,
                    title: '我们的关系与经历',
                    initial: profile.relationship,
                    hint: '例：我们是高中同桌，大学异地三年，去年她表白我拒绝了，现在是暧昧期',
                    onSave: notifier.setRelationship,
                  ),
                ),
              ],
            ),
            _Header(
              'TA 的喜好词（聊到涨好感 · 当前 ${profile.affinity}% · ${relationshipStageForUser(profile)}）',
            ),
            _WordList(
              words: profile.likes,
              hint: '例：她爱喝的奶茶、想去的地方、在乎的事',
              onAdd: notifier.addLike,
              onRemove: notifier.removeLikeAt,
              icon: Icons.favorite_border,
              color: AppColors.primary,
            ),
            const _Header('TA 的厌恶词（聊到掉好感，好感度过低会冷暴力你）'),
            _WordList(
              words: profile.dislikes,
              hint: '例：前任、放鸽子、不回复消息',
              onAdd: notifier.addDislike,
              onRemove: notifier.removeDislikeAt,
              icon: Icons.heart_broken,
              color: Colors.redAccent,
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '聊到喜好词 +6、厌恶词 -5；阶段：相离（<0）· 相遇（0–19）· 相识（20–39）· 相知（40–59）· 相爱（60+）。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(
    BuildContext context, {
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String) onSave,
  }) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldPage(
          title: title,
          initial: initial,
          hint: hint,
          maxLines: 8,
        ),
      ),
    );
    if (result != null) await onSave(result);
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 8),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    ),
  );
}

/// 词条列表 + 添加输入行
class _WordList extends ConsumerStatefulWidget {
  final List<String> words;
  final String hint;
  final ValueChanged<String> onAdd;
  final ValueChanged<int> onRemove;
  final IconData icon;
  final Color color;

  const _WordList({
    required this.words,
    required this.hint,
    required this.onAdd,
    required this.onRemove,
    required this.icon,
    required this.color,
  });

  @override
  ConsumerState<_WordList> createState() => _WordListState();
}

class _WordListState extends ConsumerState<_WordList> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      child: Column(
        children: [
          for (var i = 0; i < widget.words.length; i++) ...[
            if (i > 0) const Divider(indent: 16, height: 1),
            ListTile(
              dense: true,
              leading: Icon(widget.icon, size: 18, color: widget.color),
              title: Text(
                widget.words[i],
                style: const TextStyle(fontSize: 14),
              ),
              trailing: IconButton(
                icon: const Icon(
                  Icons.close,
                  size: 18,
                  color: AppColors.textSecondary,
                ),
                onPressed: () => widget.onRemove(i),
              ),
            ),
          ],
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    decoration: InputDecoration(
                      hintText: widget.hint,
                      hintStyle: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                      border: InputBorder.none,
                      isDense: true,
                    ),
                    onSubmitted: (_) => _add(),
                  ),
                ),
                TextButton(onPressed: _add, child: const Text('添加')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _add() {
    final v = _controller.text.trim();
    if (v.isEmpty) return;
    widget.onAdd(v);
    _controller.clear();
  }
}
