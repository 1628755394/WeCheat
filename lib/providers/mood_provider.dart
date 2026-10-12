import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/mood_state.dart';
import '../services/mood_policy.dart';

class MoodNotifier extends Notifier<MoodState> {
  MoodNotifier(this.profileId);
  final String profileId;
  Box? _box;
  Future<void>? _loading;

  @override
  MoodState build() {
    _loading ??= _load();
    return MoodState();
  }

  Future<void> _load() async {
    _box = await Hive.openBox('mood_states');
    final raw = _box!.get(profileId);
    if (raw is Map) {
      state = decayMood(MoodState.fromMap(raw), DateTime.now());
      await _box!.put(profileId, state.toMap());
    }
  }

  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _save(MoodState value) async {
    await ensureLoaded();
    state = value;
    await _box!.put(profileId, value.toMap());
  }

  Future<void> onUserMessage({required bool negative, DateTime? now}) async {
    await ensureLoaded();
    await _save(
      applyMoodEvent(state, negative ? '厌恶词' : '普通消息', now ?? DateTime.now()),
    );
  }

  Future<void> onEvent(String event, {DateTime? now}) async {
    await ensureLoaded();
    await _save(applyMoodEvent(state, event, now ?? DateTime.now()));
  }

  Future<void> onReply(int affinity, {DateTime? now}) async {
    await ensureLoaded();
    await _save(afterMoodReply(state, affinity, now ?? DateTime.now()));
  }

  Future<void> preview(double valence, double arousal) async {
    await ensureLoaded();
    await _save(
      state.copyWith(valence: valence, arousal: arousal, lastEvent: '调试预览'),
    );
  }
}

final moodProvider = NotifierProvider.family<MoodNotifier, MoodState, String>(
  MoodNotifier.new,
);
