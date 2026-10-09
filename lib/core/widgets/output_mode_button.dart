import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/output_mode_provider.dart';

class OutputModeButton extends ConsumerWidget {
  const OutputModeButton({super.key, this.dark = false});
  final bool dark;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(outputModeProvider);
    final isDark = dark || Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: PopupMenuButton<OutputMode>(
        tooltip: '全局输出模式',
        initialValue: current,
        onSelected: (mode) =>
            ref.read(outputModeProvider.notifier).select(mode),
        itemBuilder: (_) => [
          for (final mode in OutputMode.values)
            CheckedPopupMenuItem(
              key: ValueKey(mode.name),
              value: mode,
              checked: mode == current,
              child: Text(mode.label),
            ),
        ],
        child: Container(
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white12 : const Color(0xFFEEEEEE),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                current.speaks ? Icons.volume_up_outlined : Icons.text_fields,
                size: 18,
                color: isDark ? Colors.white : Colors.black87,
              ),
              const SizedBox(width: 5),
              Text(
                current.label,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
