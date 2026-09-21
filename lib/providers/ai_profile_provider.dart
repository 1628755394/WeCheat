import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/ai_profile.dart';

/// AI 资料（人设/知识库/聊天风格样本/模型），按会话 id 存 Hive
/// 每个 AI 好友一套独立配置，互不覆盖
class AiProfileNotifier extends Notifier<AiProfile> {
  AiProfileNotifier(this.conversationId);

  final String conversationId;

  static const _boxName = 'ai_profiles';

  Box? _box;
  Future<void>? _loading;

  @override
  AiProfile build() {
    _loading ??= _load();
    return const AiProfile();
  }

  /// 确保 Hive 数据已载入（发送消息/通话前调用，避免读到空资料）
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _box = await Hive.openBox(_boxName);
    final raw = _box!.get(conversationId);
    if (raw != null) state = AiProfile.fromMap(raw as Map);
  }

  Future<void> _save(AiProfile profile) async {
    // 先等初始加载完成，否则 _load 的 state 赋值可能覆盖刚保存的值
    await ensureLoaded();
    state = profile;
    await _box!.put(conversationId, profile.toMap());
  }

  Future<void> setPersona(String v) => _save(state.copyWith(persona: v));

  Future<void> setChatLog(String v) => _save(state.copyWith(chatLog: v));

  Future<void> setModel(String v) => _save(state.copyWith(model: v));

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

/// 按 conversationId 区分：每个 AI 会话一份资料
final aiProfileProvider =
    NotifierProvider.family<AiProfileNotifier, AiProfile, String>(
        AiProfileNotifier.new);
