import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/ai_profile.dart';
import '../models/expression_profile.dart';

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

  Future<void> setCustomRules(List<String> rules) =>
      _save(state.copyWith(customRules: rules));

  Future<void> setAutoVoiceMessages(bool value) =>
      _save(state.copyWith(autoVoiceMessages: value));

  Future<void> setExpressionProfile(ExpressionProfile value) =>
      _save(state.copyWith(expressionProfile: value));

  Future<void> importWriting({
    required String persona,
    required String greeting,
    required String chatLog,
    required List<String> rules,
  }) async {
    await ensureLoaded();
    await _save(
      state.copyWith(
        persona: persona,
        greeting: greeting,
        chatLog: chatLog,
        customRules: rules,
      ),
    );
  }

  Future<void> setModel(String v) => _save(state.copyWith(model: v));

  Future<void> setGreeting(String v) => _save(state.copyWith(greeting: v));

  Future<void> setLanguage(String v) => _save(state.copyWith(language: v));

  Future<void> setRecentState(String value, {int? messageCount}) => _save(
    state.copyWith(
      recentState: value,
      recentStateMessageCount: messageCount ?? state.recentStateMessageCount,
    ),
  );

  /// 重点记忆：聊天里长按消息「标记为记忆」时写入
  Future<void> addMemory(String entry) {
    if (state.memories.contains(entry)) return Future.value();
    return _save(state.copyWith(memories: [...state.memories, entry]));
  }

  Future<void> removeMemory(String entry) => _save(
    state.copyWith(memories: state.memories.where((e) => e != entry).toList()),
  );

  Future<void> removeMemoryAt(int index) {
    final next = [...state.memories]..removeAt(index);
    return _save(state.copyWith(memories: next));
  }

  /// 导入克隆音色参考音频（建议 20-30 秒清晰人声）
  Future<void> setVoice(Uint8List bytes, String name) async {
    await ensureLoaded();
    await _save(state.copyWith(voiceBytes: bytes, voiceName: name));
  }

  Future<void> clearVoice() => _save(state.copyWith(clearVoice: true));

  Future<void> setVoiceEndpoint(String v) =>
      _save(state.copyWith(voiceEndpoint: v));

  Future<void> setTranscriptionEndpoint(String v) async {
    await ensureLoaded();
    await _save(state.copyWith(transcriptionEndpoint: v));
  }

  Future<void> setVoicePrompt(String v) =>
      _save(state.copyWith(voicePrompt: v));

  Future<void> setVoiceApiProfile({
    required String baseUrl,
    required String cloneProfileId,
  }) => _save(
    state.copyWith(
      voiceApiBaseUrl: baseUrl,
      voiceCloneProfileId: cloneProfileId,
    ),
  );

  Future<void> clearVoiceApiProfile() =>
      _save(state.copyWith(clearSoulNexusVoice: true));

  /// 好感度：聊天互动涨、厌恶词/拉黑行为掉（clamp -100~100，映射到关系阶段）
  Future<void> addAffinity(int delta) => _save(
    state.copyWith(affinity: (state.affinity + delta).clamp(-100, 100)),
  );

  Future<void> setAffinity(int v) =>
      _save(state.copyWith(affinity: v.clamp(-100, 100)));

  /// 我的人设卡：告诉 AI"你是谁"
  Future<void> setUserPersona(String v) =>
      _save(state.copyWith(userPersona: v));

  /// 和 TA 的关系与共同经历
  Future<void> setRelationship(String v) =>
      _save(state.copyWith(relationship: v));

  /// 回复是否允许（）动作描写
  Future<void> setAllowActions(bool v) =>
      _save(state.copyWith(allowActions: v, allowActionsCustomized: true));

  /// 喜好词/厌恶词管理（点自己头像的「我与 TA」页编辑）
  Future<void> addLike(String v) =>
      _save(state.copyWith(likes: [...state.likes, v]));

  Future<void> removeLikeAt(int i) {
    final next = [...state.likes]..removeAt(i);
    return _save(state.copyWith(likes: next));
  }

  Future<void> addDislike(String v) =>
      _save(state.copyWith(dislikes: [...state.dislikes, v]));

  Future<void> removeDislikeAt(int i) {
    final next = [...state.dislikes]..removeAt(i);
    return _save(state.copyWith(dislikes: next));
  }

  /// 切换剧情场景（-1 = 退出剧情）
  Future<void> setSceneIndex(int v) => _save(state.copyWith(sceneIndex: v));

  /// 追加一条 AI 日记（'时间|内容'）
  Future<void> addDiary(String entry) =>
      _save(state.copyWith(diaries: [...state.diaries, entry]));

  Future<void> removeDiaryAt(int index) {
    final next = [...state.diaries]..removeAt(index);
    return _save(state.copyWith(diaries: next));
  }

  /// 整套模型配置：本地模型 / cc-switch 服务商 / 手动密钥 一次写入
  Future<void> setModelConfig({
    String provider = '',
    String baseUrl = '',
    String apiKey = '',
    String model = '',
    String providerName = '',
  }) => _save(
    state.copyWith(
      provider: provider,
      baseUrl: baseUrl,
      apiKey: apiKey,
      model: model,
      providerName: providerName,
    ),
  );

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
      AiProfileNotifier.new,
    );
