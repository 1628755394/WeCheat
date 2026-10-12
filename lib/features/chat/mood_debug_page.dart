import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/mood_state.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/mood_provider.dart';
import '../../services/mood_policy.dart';

class MoodDebugPage extends ConsumerStatefulWidget {
  const MoodDebugPage({super.key, required this.conversationId});
  final String conversationId;

  @override
  ConsumerState<MoodDebugPage> createState() => _MoodDebugPageState();
}

class _MoodDebugPageState extends ConsumerState<MoodDebugPage> {
  int? _previewAffinity;

  @override
  Widget build(BuildContext context) {
    final mood = ref.watch(moodProvider(widget.conversationId));
    final affinity =
        _previewAffinity ??
        ref.watch(aiProfileProvider(widget.conversationId)).affinity;
    final zone = mood.zone(affinity);
    final instruction = getMoodInstruction(mood, affinity);
    final notifier = ref.read(moodProvider(widget.conversationId).notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('情绪调试')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('当前分区：${_zoneName(zone)} ${mood.emoji}'),
          Text('最近事件：${mood.lastEvent}'),
          Text('连续拌嘴：${mood.quarrelReplies}/2'),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              for (final event in ['厌恶词', '撤回消息', '已读不回'])
                OutlinedButton(
                  onPressed: () => notifier.onEvent(event),
                  child: Text('模拟$event'),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Text('Valence ${mood.valence.toStringAsFixed(2)}'),
          Slider(
            value: mood.valence,
            min: -1,
            max: 1,
            onChanged: (value) => notifier.preview(value, mood.arousal),
          ),
          Text('Arousal ${mood.arousal.toStringAsFixed(2)}'),
          Slider(
            value: mood.arousal,
            onChanged: (value) => notifier.preview(mood.valence, value),
          ),
          Text('预览好感度 $affinity'),
          Slider(
            value: affinity.toDouble().clamp(-100, 100),
            min: -100,
            max: 100,
            onChanged: (value) =>
                setState(() => _previewAffinity = value.round()),
          ),
          const SizedBox(height: 16),
          Text(instruction.isEmpty ? '当前无特殊负面表达规则。' : instruction),
          const SizedBox(height: 12),
          Text(
            '争吵剧情前置条件：${canEnterConflictScene(mood, affinity) ? '满足' : '未满足'}',
          ),
        ],
      ),
    );
  }

  String _zoneName(MoodZone zone) => switch (zone) {
    MoodZone.calm => '平静',
    MoodZone.mild => '轻度别扭',
    MoodZone.quarrel => '赌气拌嘴',
    MoodZone.distant => '冷淡抵触',
    MoodZone.fuse => '熔断沉默',
  };
}
