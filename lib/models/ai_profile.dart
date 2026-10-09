import 'dart:typed_data';

import 'expression_profile.dart';

/// AI 资料：人设 / 知识库 / 聊天记录风格样本 / 模型 / 音色 / 重点记忆
/// 存 Hive，key 为会话 id
class AiProfile {
  /// 人设描述：名字、身份、性格、说话风格等
  final String persona;

  /// 知识库条目（本地简单检索，取相关条目注入 prompt）
  final List<String> knowledge;

  /// 聊天记录原文样本：AI 会模仿其中人物的语气
  final String chatLog;

  /// Additional instructions applied to every reply.
  final List<String> customRules;

  /// Send normal AI replies as playable voice messages.
  final bool autoVoiceMessages;

  final ExpressionProfile expressionProfile;

  /// 模型名（本地 Ollama 模型或远程接口模型），空 = 默认
  final String model;

  /// 模型来源：''/'ollama' = 本地 Ollama；'anthropic'/'openai' = 远程兼容接口
  final String provider;

  /// 远程接口地址（provider 非本地时必填）
  final String baseUrl;

  /// 远程接口密钥
  final String apiKey;

  /// 来源显示名（cc-switch 服务商名等），仅用于 UI 展示
  final String providerName;

  /// 回复与语音使用的语言代码：zh-CN / ja-JP / en-US
  final String language;

  /// 开场白：会话为空时自动作为第一条 AI 消息发出（猫箱式角色开场）
  final String greeting;

  /// 重点记忆：用户从聊天记录里标记的重要内容，全量注入 prompt 永不截断
  final List<String> memories;

  /// 导入的参考音色音频（~30 秒清晰人声），用于本地克隆 TTS
  final Uint8List? voiceBytes;

  /// 音色文件名（UI 展示用）
  final String voiceName;

  /// 语音克隆服务地址（GPT-SoVITS api_v2 兼容，默认 127.0.0.1:9880/tts）
  final String voiceEndpoint;
  final String transcriptionEndpoint;
  final String voiceApiBaseUrl;
  final String voiceCloneProfileId;

  /// 参考音频对应的台词文本（提升克隆质量，可选）
  final String voicePrompt;

  /// 好感度 -100~100：聊到喜好/心愿才上涨，影响关系阶段和语气
  final int affinity;

  /// 喜好与心愿清单：用户消息命中这些话题才涨好感度（仿 1999 好感机制）
  final List<String> likes;

  /// 我的人设卡：告诉 AI"你是谁"（猫箱式"我的设定"），注入 prompt
  final String userPersona;

  /// 和 TA 的关系与共同经历（点自己头像设定），注入 prompt
  final String relationship;

  /// 厌恶词清单：用户消息命中这些话题好感度会下降，过低触发冷暴力
  final List<String> dislikes;

  /// 回复里允许（）动作/神态描写；默认关 = 像正常人发微信只说人话
  final bool allowActions;
  final bool allowActionsCustomized;
  final bool alwaysComply;

  /// 剧情场景卡（猫箱式多剧情）：name/desc/greeting
  final List<AiScene> scenes;

  /// 当前场景下标；-1 = 未进入任何剧情
  final int sceneIndex;

  /// AI 日记：'yyyy-MM-dd HH:mm|内容' 格式，用户触发生成
  final List<String> diaries;
  final String recentState;
  final int recentStateMessageCount;

  const AiProfile({
    this.persona = '',
    this.knowledge = const [],
    this.chatLog = '',
    this.customRules = const [],
    this.autoVoiceMessages = false,
    this.expressionProfile = const ExpressionProfile(),
    this.model = '',
    this.provider = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.providerName = '',
    this.language = 'zh-CN',
    this.greeting = '',
    this.memories = const [],
    this.voiceBytes,
    this.voiceName = '',
    this.voiceEndpoint = '',
    this.transcriptionEndpoint = '',
    this.voiceApiBaseUrl = '',
    this.voiceCloneProfileId = '',
    this.voicePrompt = '',
    this.affinity = 0,
    this.likes = const [],
    this.userPersona = '',
    this.relationship = '',
    this.dislikes = const [],
    this.allowActions = false,
    this.allowActionsCustomized = false,
    this.alwaysComply = false,
    this.scenes = const [],
    this.sceneIndex = -1,
    this.diaries = const [],
    this.recentState = '',
    this.recentStateMessageCount = 0,
  });

  /// 是否已导入克隆音色
  bool get hasVoice => voiceBytes != null && voiceBytes!.isNotEmpty;

  bool get hasSoulNexusVoice => voiceCloneProfileId.isNotEmpty;

  /// 好感度是否达到数值上限
  bool get affinityFull => affinity >= 100;

  /// 好感度阶段名
  String get affinityStage => stageForAffinity(affinity);

  static String stageForAffinity(int value) => value < 0
      ? '相离'
      : value < 20
      ? '相遇'
      : value < 40
      ? '相识'
      : value < 60
      ? '相知'
      : '相爱';

  /// 是否走远程接口（非本地 Ollama）
  bool get isRemote =>
      provider == 'anthropic' ||
      provider == 'openai' ||
      provider == 'responses';

  /// 当前激活的剧情节景（无则 null）
  AiScene? get currentScene =>
      sceneIndex >= 0 && sceneIndex < scenes.length ? scenes[sceneIndex] : null;

  Map<String, dynamic> toMap() => {
    'persona': persona,
    'knowledge': knowledge,
    'chatLog': chatLog,
    'customRules': customRules,
    'autoVoiceMessages': autoVoiceMessages,
    'expressionProfile': expressionProfile.toMap(),
    'model': model,
    'provider': provider,
    'baseUrl': baseUrl,
    'apiKey': apiKey,
    'providerName': providerName,
    'language': language,
    'greeting': greeting,
    'memories': memories,
    'voiceBytes': voiceBytes,
    'voiceName': voiceName,
    'voiceEndpoint': voiceEndpoint,
    'transcriptionEndpoint': transcriptionEndpoint,
    'voiceApiBaseUrl': voiceApiBaseUrl,
    'voiceCloneProfileId': voiceCloneProfileId,
    'voicePrompt': voicePrompt,
    'affinity': affinity,
    'likes': likes,
    'userPersona': userPersona,
    'relationship': relationship,
    'dislikes': dislikes,
    'allowActions': allowActions,
    'allowActionsCustomized': allowActionsCustomized,
    'alwaysComply': alwaysComply,
    'scenes': [for (final s in scenes) s.toMap()],
    'sceneIndex': sceneIndex,
    'diaries': diaries,
    'recentState': recentState,
    'recentStateMessageCount': recentStateMessageCount,
  };

  factory AiProfile.fromMap(Map map) => AiProfile(
    persona: (map['persona'] as String?) ?? '',
    knowledge: (map['knowledge'] as List?)?.cast<String>() ?? const [],
    chatLog: (map['chatLog'] as String?) ?? '',
    customRules: (map['customRules'] as List?)?.cast<String>() ?? const [],
    autoVoiceMessages: (map['autoVoiceMessages'] as bool?) ?? false,
    expressionProfile: ExpressionProfile.fromMap(
      map['expressionProfile'] as Map?,
    ),
    model: (map['model'] as String?) ?? '',
    provider: (map['provider'] as String?) ?? '',
    baseUrl: (map['baseUrl'] as String?) ?? '',
    apiKey: (map['apiKey'] as String?) ?? '',
    providerName: (map['providerName'] as String?) ?? '',
    language: (map['language'] as String?) ?? 'zh-CN',
    greeting: (map['greeting'] as String?) ?? '',
    memories: (map['memories'] as List?)?.cast<String>() ?? const [],
    voiceBytes: _toBytes(map['voiceBytes']),
    voiceName: (map['voiceName'] as String?) ?? '',
    voiceEndpoint: (map['voiceEndpoint'] as String?) ?? '',
    transcriptionEndpoint: (map['transcriptionEndpoint'] as String?) ?? '',
    voiceApiBaseUrl: (map['voiceApiBaseUrl'] as String?) ?? '',
    voiceCloneProfileId: (map['voiceCloneProfileId'] as String?) ?? '',
    voicePrompt: (map['voicePrompt'] as String?) ?? '',
    affinity: (map['affinity'] as int?) ?? 0,
    likes: (map['likes'] as List?)?.cast<String>() ?? const [],
    userPersona: (map['userPersona'] as String?) ?? '',
    relationship: (map['relationship'] as String?) ?? '',
    dislikes: (map['dislikes'] as List?)?.cast<String>() ?? const [],
    allowActions: (map['allowActions'] as bool?) ?? false,
    allowActionsCustomized: (map['allowActionsCustomized'] as bool?) ?? false,
    alwaysComply: (map['alwaysComply'] as bool?) ?? false,
    scenes: [
      for (final s in (map['scenes'] as List? ?? const []))
        AiScene.fromMap(s as Map),
    ],
    sceneIndex: (map['sceneIndex'] as int?) ?? -1,
    diaries: (map['diaries'] as List?)?.cast<String>() ?? const [],
    recentState: (map['recentState'] as String?) ?? '',
    recentStateMessageCount: (map['recentStateMessageCount'] as int?) ?? 0,
  );

  AiProfile copyWith({
    String? persona,
    List<String>? knowledge,
    String? chatLog,
    List<String>? customRules,
    bool? autoVoiceMessages,
    ExpressionProfile? expressionProfile,
    String? model,
    String? provider,
    String? baseUrl,
    String? apiKey,
    String? providerName,
    String? language,
    String? greeting,
    List<String>? memories,
    Uint8List? voiceBytes,
    String? voiceName,
    String? voiceEndpoint,
    String? transcriptionEndpoint,
    String? voiceApiBaseUrl,
    String? voiceCloneProfileId,
    String? voicePrompt,
    int? affinity,
    List<String>? likes,
    String? userPersona,
    String? relationship,
    List<String>? dislikes,
    bool? allowActions,
    bool? allowActionsCustomized,
    bool? alwaysComply,
    List<AiScene>? scenes,
    int? sceneIndex,
    List<String>? diaries,
    String? recentState,
    int? recentStateMessageCount,
    bool clearVoice = false,
    bool clearSoulNexusVoice = false,
  }) => AiProfile(
    persona: persona ?? this.persona,
    knowledge: knowledge ?? this.knowledge,
    chatLog: chatLog ?? this.chatLog,
    customRules: customRules ?? this.customRules,
    autoVoiceMessages: autoVoiceMessages ?? this.autoVoiceMessages,
    expressionProfile: expressionProfile ?? this.expressionProfile,
    model: model ?? this.model,
    provider: provider ?? this.provider,
    baseUrl: baseUrl ?? this.baseUrl,
    apiKey: apiKey ?? this.apiKey,
    providerName: providerName ?? this.providerName,
    language: language ?? this.language,
    greeting: greeting ?? this.greeting,
    memories: memories ?? this.memories,
    voiceBytes: clearVoice ? null : voiceBytes ?? this.voiceBytes,
    voiceName: clearVoice ? '' : voiceName ?? this.voiceName,
    voiceEndpoint: voiceEndpoint ?? this.voiceEndpoint,
    transcriptionEndpoint: transcriptionEndpoint ?? this.transcriptionEndpoint,
    voiceApiBaseUrl: voiceApiBaseUrl ?? this.voiceApiBaseUrl,
    voiceCloneProfileId: clearSoulNexusVoice
        ? ''
        : voiceCloneProfileId ?? this.voiceCloneProfileId,
    voicePrompt: voicePrompt ?? this.voicePrompt,
    affinity: affinity ?? this.affinity,
    likes: likes ?? this.likes,
    userPersona: userPersona ?? this.userPersona,
    relationship: relationship ?? this.relationship,
    dislikes: dislikes ?? this.dislikes,
    allowActions: allowActions ?? this.allowActions,
    allowActionsCustomized:
        allowActionsCustomized ?? this.allowActionsCustomized,
    alwaysComply: alwaysComply ?? this.alwaysComply,
    scenes: scenes ?? this.scenes,
    sceneIndex: sceneIndex ?? this.sceneIndex,
    diaries: diaries ?? this.diaries,
    recentState: recentState ?? this.recentState,
    recentStateMessageCount:
        recentStateMessageCount ?? this.recentStateMessageCount,
  );

  static Uint8List? _toBytes(dynamic raw) {
    if (raw == null) return null;
    if (raw is Uint8List) return raw;
    return Uint8List.fromList((raw as List).cast<int>());
  }
}

/// 剧情场景卡：猫箱式多剧情——名字 / 场景描述（注入 prompt）/ 进场景开场白
class AiScene {
  final String name;
  final String desc;
  final String greeting;

  const AiScene({required this.name, this.desc = '', this.greeting = ''});

  Map<String, dynamic> toMap() => {
    'name': name,
    'desc': desc,
    'greeting': greeting,
  };

  factory AiScene.fromMap(Map map) => AiScene(
    name: (map['name'] as String?) ?? '',
    desc: (map['desc'] as String?) ?? '',
    greeting: (map['greeting'] as String?) ?? '',
  );
}
