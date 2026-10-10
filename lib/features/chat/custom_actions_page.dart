import '../../core/widgets/wechat_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/live2d_model_config.dart';
import '../../providers/ai_profile_provider.dart';

class CustomActionsPage extends ConsumerWidget {
  const CustomActionsPage({super.key, required this.conversationId});
  final String conversationId;

  Future<void> _edit(
    BuildContext context,
    WidgetRef ref,
    Live2DModelConfig model, [
    CustomActorAction? action,
  ]) async {
    final result = await showDialog<CustomActorAction>(
      context: context,
      builder: (_) => _ActionEditor(model: model, action: action),
    );
    if (result == null || !context.mounted) return;
    final latest = ref.read(aiProfileProvider(conversationId)).live2dModel;
    if (latest == null || latest.directory != model.directory) return;
    await ref
        .read(aiProfileProvider(conversationId).notifier)
        .setLive2dModel(
          latest.withActions([
            for (final entry in latest.actions)
              if (entry.id != result.id) entry,
            result,
          ]),
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final model = ref.watch(aiProfileProvider(conversationId)).live2dModel;
    return Scaffold(
      appBar: AppBar(
        title: const Text('自定义动作'),
        actions: [
          IconButton(
            tooltip: '新增动作',
            icon: const Icon(Icons.add),
            onPressed: model == null || model.motions.isEmpty
                ? null
                : () => _edit(context, ref, model),
          ),
        ],
      ),
      body: model == null
          ? const Center(child: Text('未导入模型'))
          : model.motions.isEmpty
          ? const Center(child: Text('模型没有可用动画'))
          : model.actions.isEmpty
          ? const Center(child: Text('暂无自定义动作'))
          : ListView.separated(
              itemCount: model.actions.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final action = model.actions[index];
                return ListTile(
                  title: Text(action.name),
                  subtitle: Text(
                    [
                      model.motionFor(action)?.label ?? '动画已失效',
                      if (action.triggers.isNotEmpty) action.triggers.join('、'),
                      '${action.speed.toStringAsFixed(1)}×',
                    ].join('\n'),
                  ),
                  onTap: () => _edit(context, ref, model, action),
                  trailing: IconButton(
                    tooltip: '删除动作',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => ref
                        .read(aiProfileProvider(conversationId).notifier)
                        .setLive2dModel(
                          model.withActions(
                            model.actions
                                .where((entry) => entry.id != action.id)
                                .toList(),
                          ),
                        ),
                  ),
                );
              },
            ),
    );
  }
}

class _ActionEditor extends StatefulWidget {
  const _ActionEditor({required this.model, this.action});
  final Live2DModelConfig model;
  final CustomActorAction? action;
  @override
  State<_ActionEditor> createState() => _ActionEditorState();
}

class _ActionEditorState extends State<_ActionEditor> {
  final _form = GlobalKey<FormState>();
  late final _name = TextEditingController(text: widget.action?.name);
  late final _triggers = TextEditingController(
    text: widget.action?.triggers.join('、'),
  );
  late Live2DMotion _motion = widget.action == null
      ? widget.model.motions.first
      : widget.model.motionFor(widget.action!) ?? widget.model.motions.first;
  late double _speed = widget.action?.speed ?? 1;
  @override
  void dispose() {
    _name.dispose();
    _triggers.dispose();
    super.dispose();
  }

  void _save() {
    if (!_form.currentState!.validate()) return;
    Navigator.pop(
      context,
      CustomActorAction(
        id:
            widget.action?.id ??
            DateTime.now().microsecondsSinceEpoch.toString(),
        name: _name.text.trim(),
        group: _motion.group,
        index: _motion.index,
        triggers: _triggers.text
            .split(RegExp(r'[,，、;；\n]'))
            .map((word) => word.trim())
            .where((word) => word.isNotEmpty)
            .toSet()
            .toList(),
        speed: _speed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) => WeChatDialog(
    title: Text(widget.action == null ? '新增动作' : '编辑动作'),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: '动作名称'),
                maxLength: 24,
                validator: (value) {
                  final name = value?.trim() ?? '';
                  if (name.isEmpty) return '请输入名称';
                  if (RegExp(
                    r'停止|停下|别动|不要|不用|不许|stop',
                    caseSensitive: false,
                  ).hasMatch(name)) {
                    return '请避开停止或否定指令';
                  }
                  if (widget.model.actions.any(
                    (entry) =>
                        entry.id != widget.action?.id &&
                        entry.name.toLowerCase() == name.toLowerCase(),
                  )) {
                    return '名称已存在';
                  }
                  return null;
                },
              ),
              TextFormField(
                controller: _triggers,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '触发词',
                  hintText: '抱抱、拥抱',
                ),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<Live2DMotion>(
                initialValue: _motion,
                isExpanded: true,
                decoration: const InputDecoration(labelText: '模型动画'),
                items: [
                  for (final motion in widget.model.motions)
                    DropdownMenuItem(
                      value: motion,
                      child: Text(
                        motion.label,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _motion = value);
                },
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Text('播放速度'),
                  const Spacer(),
                  Text('${_speed.toStringAsFixed(1)}×'),
                ],
              ),
              Slider(
                value: _speed,
                min: 0.5,
                max: 2,
                divisions: 15,
                onChanged: (value) => setState(() => _speed = value),
              ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(onPressed: _save, child: const Text('保存')),
    ],
  );
}
