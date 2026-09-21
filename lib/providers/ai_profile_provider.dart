import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/ai_profile.dart';

/// AI 助手资料（人设/知识库/聊天风格样本），按会话存 Hive
/// 当前只有 conv_ai，用单例即可
class AiProfileNotifier extends Notifier<AiProfile> {
  static const _boxName = 'ai_profiles';
  static const _key = 'conv_ai';

  Box? _box;

  @override
  AiProfile build() {
    _load();
    return const AiProfile();
  }

  Future<void> _load() async {
    _box = await Hive.openBox(_boxName);
    final raw = _box!.get(_key);
    if (raw != null) state = AiProfile.fromMap(raw as Map);
  }

  Future<void> _save(AiProfile profile) async {
    state = profile;
    _box ??= await Hive.openBox(_boxName);
    await _box!.put(_key, profile.toMap());
  }

  Future<void> setPersona(String v) => _save(state.copyWith(persona: v));

  Future<void> setChatLog(String v) => _save(state.copyWith(chatLog: v));

  Future<void> addKnowledge(String entry) =>
      _save(state.copyWith(knowledge: [...state.knowledge, entry]));

  Future<void> updateKnowledge(int index, String entry) {
    final next = [...state.knowledge]..[index] = entry;
    return _save(state.copyWith(knowledge: next));
  }

  Future<void> removeKnowledge(int index) {
    final next = [...state.knowledge]..removeAt(index);
    return _save(state.copyWith(knowledge: next));
  }
}

final aiProfileProvider =
    NotifierProvider<AiProfileNotifier, AiProfile>(AiProfileNotifier.new);
