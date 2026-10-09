import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

enum OutputMode {
  text('文字'),
  speechAndText('语音 + 文字');

  const OutputMode(this.label);
  final String label;
  bool get speaks => this == speechAndText;
}

class OutputModeNotifier extends Notifier<OutputMode> {
  Box? _box;
  Future<void>? _loading;

  @override
  OutputMode build() {
    _loading ??= _load();
    return OutputMode.speechAndText;
  }

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _box = await Hive.openBox('app_settings');
    final saved = _box!.get('outputMode');
    state =
        OutputMode.values.where((mode) => mode.name == saved).firstOrNull ??
        OutputMode.speechAndText;
  }

  Future<void> select(OutputMode mode) async {
    state = mode;
    await ensureLoaded();
    await _box!.put('outputMode', mode.name);
  }
}

final outputModeProvider = NotifierProvider<OutputModeNotifier, OutputMode>(
  OutputModeNotifier.new,
);
