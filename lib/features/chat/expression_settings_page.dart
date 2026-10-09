import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../models/expression_profile.dart';
import '../../providers/ai_profile_provider.dart';

class ExpressionSettingsPage extends ConsumerWidget {
  const ExpressionSettingsPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref
        .watch(aiProfileProvider(conversationId))
        .expressionProfile;
    final notifier = ref.read(aiProfileProvider(conversationId).notifier);
    void update(ExpressionProfile value) =>
        notifier.setExpressionProfile(value);

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('虚拟演员')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          Material(
            color: Colors.white,
            child: SwitchListTile(
              title: const Text('通话动画'),
              value: config.animationEnabled,
              onChanged: (value) =>
                  update(config.copyWith(animationEnabled: value)),
            ),
          ),
          if (config.animationEnabled) ...[
            const SizedBox(height: 8),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  _slider(
                    '情绪敏感度',
                    config.emotionSensitivity,
                    (value) =>
                        update(config.copyWith(emotionSensitivity: value)),
                  ),
                  _slider(
                    '反应速度',
                    config.reactionSpeed,
                    (value) => update(config.copyWith(reactionSpeed: value)),
                  ),
                  _slider(
                    '眨眼频率',
                    config.blinkBaseRate,
                    (value) => update(config.copyWith(blinkBaseRate: value)),
                  ),
                  _slider(
                    '呼吸速度',
                    config.breathSpeedBase,
                    (value) => update(config.copyWith(breathSpeedBase: value)),
                  ),
                  _slider(
                    '视线漂移',
                    config.gazeWanderAmount,
                    (value) => update(config.copyWith(gazeWanderAmount: value)),
                  ),
                  _slider(
                    '动作幅度',
                    config.bodyMovementIntensity,
                    (value) =>
                        update(config.copyWith(bodyMovementIntensity: value)),
                  ),
                  SwitchListTile(
                    title: const Text('记忆触发情绪'),
                    value: config.memoryEmotionTrigger,
                    onChanged: (value) =>
                        update(config.copyWith(memoryEmotionTrigger: value)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _slider(String title, double value, ValueChanged<double> onChanged) =>
      ListTile(
        title: Text(title),
        trailing: SizedBox(
          width: 160,
          child: Slider(value: value, onChanged: onChanged),
        ),
      );
}
