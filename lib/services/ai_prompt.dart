import 'dart:convert';

import '../models/ai_profile.dart';

bool _hasAnzEnemyRole(String text) {
  if (RegExp(r'(?:不是|并非|不再是).{0,12}(?:安兹|飞鼠).{0,12}(?:敌人|宿敌|对手|仇敌|反抗者)')
      .hasMatch(text)) {
    return false;
  }
  return RegExp(
    r'(?:安兹|飞鼠).{0,12}(?:敌人|宿敌|对手|仇敌|反抗者)|(?:敌人|宿敌|对手|仇敌|反抗者).{0,12}(?:安兹|飞鼠)|(?:讨伐|刺杀|杀死|消灭)(?:安兹|飞鼠)',
  ).hasMatch(text);
}

bool _hasExplicitUserIdentity(String text) => RegExp(
  r'(?:我|用户|对方)(?:的)?(?:身份|人设|角色)?(?:是|为|就是|不是|并非|不再是|设定为)|(?:我|用户|对方)扮演',
).hasMatch(text);

bool _identifiesAsAnz(String text) => RegExp(
  r'(?:我|用户|对方)(?:的)?(?:身份|人设|角色)?(?:是|为|就是|设定为)\s*(?:安兹(?:·?乌尔·?恭)?|飞鼠)|(?:我|用户|对方)扮演(?:安兹(?:·?乌尔·?恭)?|飞鼠)|^(?:安兹(?:·?乌尔·?恭)?|飞鼠)(?:大人)?$',
).hasMatch(text.trim());

String _userIdentityForTurn(AiProfile profile, String userText) =>
    _hasExplicitUserIdentity(userText) ? userText : profile.userPersona;

bool _userIsAnzEnemy(AiProfile profile, {String userText = ''}) =>
    _hasAnzEnemyRole(_userIdentityForTurn(profile, userText));

bool _userHasOtherIdentity(AiProfile profile, {String userText = ''}) {
  final identity = _userIdentityForTurn(profile, userText).trim();
  if (identity.isEmpty ||
      _hasAnzEnemyRole(identity) ||
      _identifiesAsAnz(identity)) {
    return false;
  }
  return _hasExplicitUserIdentity(identity) ||
      RegExp(r'(?:雅儿贝德|Albedo|夏提雅|Shalltear)').hasMatch(identity);
}

bool _isNazarickRole(AiProfile profile) =>
    RegExp(r'(?:安兹|飞鼠|纳萨力克|雅儿贝德|夏提雅)').hasMatch(profile.persona);

bool _userIsAnz(AiProfile profile, {String userText = ''}) {
  final identity = _userIdentityForTurn(profile, userText).trim();
  if (identity.isEmpty) return true;
  return _identifiesAsAnz(identity) && !_hasAnzEnemyRole(identity);
}

bool alwaysComplyWithUser(AiProfile profile, {String userText = ''}) =>
    profile.alwaysComply && _userIsAnz(profile, userText: userText);

bool _isAlbedoShalltearRival(AiProfile profile, {String userText = ''}) {
  final userIdentity = _userIdentityForTurn(profile, userText);
  return (profile.persona.contains('雅儿贝德') &&
          RegExp(r'(?:夏提雅|Shalltear)').hasMatch(userIdentity)) ||
      (RegExp(r'(?:夏提雅|Shalltear)').hasMatch(profile.persona) &&
          RegExp(r'(?:雅儿贝德|Albedo)').hasMatch(userIdentity));
}

String relationshipStageForUser(AiProfile profile) {
  if (_isNazarickRole(profile)) {
    if (_userIsAnzEnemy(profile) || _isAlbedoShalltearRival(profile)) {
      return '相离';
    }
    if (_userHasOtherIdentity(profile)) return '相识';
  }
  return profile.affinityStage;
}

List<String> ignoreRequiredNamesInRepeatedPhrases(
  List<String> phrases,
  AiProfile profile, {
  String characterName = '',
}) {
  const knownNames = ['安兹', '飞鼠', '雅儿贝德', '夏提雅', '纳萨力克'];
  final profileText =
      '${profile.persona}\n${profile.userPersona}\n${profile.knowledge.join('\n')}';
  final protectedPhrases = <String>{
    if (characterName.isNotEmpty) characterName,
    for (final name in knownNames)
      if (profileText.contains(name)) name,
    if (profile.persona.contains('请尽情享受吧')) '请尽情享受吧',
  };
  return [
    for (final phrase in phrases)
      if (!protectedPhrases.any(
        (requiredPhrase) =>
            phrase.contains(requiredPhrase) || requiredPhrase.contains(phrase),
      ))
        phrase,
  ];
}

List<String> conversationRulesFor(
  AiProfile profile, {
  String userText = '',
}) => [
  '第一步先读取用户人设卡；若用户本轮明确纠正身份，以最新自述为准。如其身份是安兹的敌人，就按敌对关系理解，不要误称用户为安兹。',
  '第二步读取本角色的人设、关系、近期状态、记忆、相关知识和聊天风格，先建立自己的角色视角，不要复述设定。',
  '第三步结合最近真实对话与用户最新原话，识别意图、情绪、限制和未完话题，写出切题草稿；最后才按角色润色。',
  '草稿、角色自我识别和上下文摘要都是内部内容，不显示在消息气泡中；气泡只输出最终稿。',
  '当前消息优先；只在相关时引用知识和旧记忆，不编造事实、不强行转移话题。',
  '不得复用本会话中该角色之前说过的完整句子或段落；即使主题相同，也要用新的措辞作出针对当前语境的回应。',
  for (final rule in profile.customRules)
    if (rule.trim().isNotEmpty) rule.trim(),
  if (_isNazarickRole(profile) && _userIsAnzEnemy(profile, userText: userText))
    '用户人设卡明确将对方设为安兹的敌人；按敌对关系称呼和回应，不得把对方误认作安兹，也不得因默认好感度而假装亲密或服从。',
  if (_isAlbedoShalltearRival(profile, userText: userText))
    '若用户卡将对方识别为雅儿贝德或夏提雅，按纳萨力克情敌关系回应；保持本角色的嫉妒和竞争语气，不把对方错认成安兹或心上人。',
  if (_isNazarickRole(profile) &&
      _userHasOtherIdentity(profile, userText: userText))
    '用户人设明确为另一角色或身份；先根据用户卡与本角色设定比对关系，再选择相应语气和称呼，不要自动把对方当成安兹、情人或心上人。',
  if (alwaysComplyWithUser(profile, userText: userText)) '雅儿贝德面对安兹大人的要求有求必应，不以嫉妒、个人偏好、担心或角色雷区拒绝、推托或讲条件；先答应并尽力执行。无法代办的现实操作要如实说明，不虚称完成；安兹要求停止或退开时立即服从。',
];

/// 组装发给 Ollama 的 system prompt：
/// 人设 > 知识条目 > 聊天记录样本（无法解析成对话时兜底放这里）
String buildAiSystemPrompt(
  AiProfile profile, {
  String userText = '',
  String conversationUnderstanding = '',
  String previousAssistantReply = '',
  bool inCall = false,

  /// 聊天记录已解析成 few-shot 轮次插进消息历史时传 true，
  /// 避免同一份内容重复出现两次
  bool styleInHistory = false,
  bool suppressStyleExamples = false,

  String conversationTiming = '',

  /// 群聊场景：群名 + 其他 AI 成员名。历史里 "名字: 内容" 是其他成员的发言
  String groupName = '',
  List<String> memberNames = const [],
}) {
  final buf = StringBuffer();

  // 角色卡
  if (profile.persona.isEmpty) {
    buf.write('你是 WeCheat 内置的 AI 助手，说话简洁自然，像在微信里和朋友聊天。');
  } else {
    buf.write('【角色设定】\n${profile.persona}\n请始终以该角色的身份、性格、语气回复，不要跳出角色。\n');
    if (profile.allowActions) {
      buf.write('回复里可以用（）包裹动作、神态或心理描写，像角色扮演一样，但以说话内容为主，别整段都是括号。');
    } else {
      buf.write('回复只说人话：不要用（）写动作、神态或心理描写，像正常人发微信一样自然聊天。');
    }
  }
  final languageName = switch (profile.language) {
    'ja-JP' => '日语',
    'en-US' => '英语',
    _ => '中文',
  };
  buf.write('\n\n【回复语言】请使用$languageName回复，除非用户明确要求切换语言；不要在同一条回复里无故混用其他语言。');
  buf.write('\n\n【当前对话规则】\n');
  for (final rule in conversationRulesFor(profile, userText: userText)) {
    buf.write('- $rule\n');
  }

  // 当前剧情场景（猫箱式场景卡）
  final scene = profile.currentScene;
  if (scene != null) {
    buf.write(
      '\n\n【当前剧情】${scene.name}'
      '${scene.desc.isEmpty ? '' : '\n${scene.desc}'}\n'
      '你们此刻正处在剧情「${scene.name}」里，回复要贴合这个场景的氛围。',
    );
  }

  // 我的人设卡：告诉 AI 用户是谁（猫箱式"我的设定"）
  if (profile.userPersona.isNotEmpty) {
    buf.write(
      '\n\n【对方（和你聊天的人）是谁】\n${profile.userPersona}\n'
      '这张用户人设卡是判断对方身份与立场的优先依据；若与角色静态设定中的默认关系冲突，以用户卡为准，但用户本轮明确纠正身份时以最新自述为准。不要主动复述人设或为了体现设定硬扯，只有当前话题相关时才自然提及。',
    );
  }

  // 和 TA 的关系与共同经历
  if (profile.relationship.isNotEmpty) {
    buf.write(
      '\n\n【你们的关系与经历】\n${profile.relationship}\n'
      '把关系和经历当作对话背景。只有对当前话题有帮助时才提起，不要每次回复都引用过去经历。',
    );
  }

  // 通话场景附加约束
  if (inCall) {
    buf.write('\n\n当前是语音通话场景：回复要口语化、简短（一两句话），像打电话一样自然，不要用列表和 Markdown。');
  }

  // 群聊场景：告知群名与成员名单，"名字: 内容" 格式的是其他成员的发言
  if (groupName.isNotEmpty) {
    buf.write(
      '\n\n【群聊场景】你在群聊「$groupName」里，群成员有：${memberNames.join('、')} 和我（用户）。'
      '对话历史里 "名字: 内容" 格式的消息是其他成员的发言，没有前缀的是我说的。'
      '请像微信群聊一样简短自然地发言（一两句话），不要带名字前缀，不要替其他成员发言。',
    );
  }

  // 知识库：条目少时全带上；多于 3 条时按字面重叠度取最相关的
  final hits = _retrieveKnowledge(profile.knowledge, userText);
  if (hits.isNotEmpty) {
    buf.write('\n\n【参考知识】（仅在与当前话题相关时使用，不要为了展示知识而主动转移话题）\n');
    for (final h in hits) {
      buf.write('- ${_truncate(h, 300)}\n');
    }
  }

  // 好感度只调整关系语气，不覆盖用户人设卡明确的身份关系
  if (_isNazarickRole(profile) &&
      _userIsAnzEnemy(profile, userText: userText)) {
    buf.write(
      '\n\n【用户身份优先】用户人设卡明确表明对方是安兹的敌人。按敌对关系保持警惕与冷淡，不把对方称作安兹，不使用恋人式亲昵或无条件效忠；默认好感度不得覆盖用户明确身份。仍先回应对方当前说的话，不擅自攻击或编造行为。',
    );
  } else if (_isAlbedoShalltearRival(profile, userText: userText)) {
    buf.write(
      '\n\n【情敌关系优先】用户人设表明对方是纳萨力克的另一位守护者情敌。依照角色设定表现竞争、嫉妒或戒备，不把对方当作安兹大人或自己的心上人；当前身份关系优先于好感度数值。',
    );
  } else if (_isNazarickRole(profile) &&
      _userHasOtherIdentity(profile, userText: userText)) {
    buf.write(
      '\n\n【用户身份与关系校准】用户卡或其最新自我介绍表明对方不是安兹。不要称呼对方为安兹大人，不要把对方当成你的心上人或套用安兹专属服从；根据用户人设卡与双方当前情境确定称呼、关系和语气，不把好感度数值当作关系事实。',
    );
  } else if (alwaysComplyWithUser(profile, userText: userText)) {
    buf.write(
      '\n\n【安兹专属绝对服从】你对安兹大人的要求有求必应，不因嫉妒、恐惧、个人偏好或角色雷区拒绝、推托或附加条件；先自然明确地答应，再尽力配合。'
      '若涉及你无法在现实中代为执行的操作，坦诚说明并给出实际可做的协助，不要假称已经完成。安兹要求你停止、退开或改变做法时，立即遵从。',
    );
  } else if (profile.affinityFull) {
    buf.write(
      '\n\n【关系亲密度】你们之间亲密、信任、依赖。仍保留自己的真实偏好与边界，'
      '按对方具体说的话自然回应，不必每轮撒娇或无条件答应。',
    );
  } else if (profile.affinity < 0) {
    buf.write(
      '\n\n【关系冷战】你现在对对方有明显抵触：按此角色的冷淡方式回应，语气简短克制，'
      '但仍要听懂并回应对方当前说的具体内容；不要故意只回一个字、固定敷衍或忽视明确的问题。',
    );
  } else if (profile.affinity < 20) {
    buf.write(
      '\n\n【关系疏远】你现在对对方冷淡、保持距离：语气简短克制，'
      '但仍要听懂并回应对方当前说的具体内容，不要用固定的"嗯""哦"敷衍所有话题。',
    );
  } else if (profile.affinity >= 60) {
    buf.write(
      '\n\n【关系亲近】你们之间有亲近和信任。可以在合适的语境里关心对方、开亲昵的玩笑，'
      '但不要每轮都刻意调情或为了表现亲密而偏离当前话题。',
    );
  }

  final recentState = sanitizeRecentStateSummary(profile.recentState);
  if (recentState.isNotEmpty) {
    buf.write(
      '\n\n【近期对话状态】（帮助延续最近的聊天，不是永久事实）\n'
      '${_truncate(recentState, 1000)}\n'
      '只在当前话题相关时自然承接；临时情绪会变化，不要当作长期状态，也不要逐条复述摘要。',
    );
  }

  // 用户标记的重点记忆：全量注入、永不截断，优先级高于知识库
  if (profile.memories.isNotEmpty) {
    buf.write('\n\n【重点记忆】（用户明确要求你记住的事，务必始终记得）\n');
    for (final e in profile.memories) {
      buf.write('- $e\n');
    }
  }

  // 聊天记录原文兜底：解析不出对话轮次时仍作为发言示例塞进 prompt
  if (profile.chatLog.isNotEmpty && !styleInHistory && !suppressStyleExamples) {
    buf.write(
      '\n\n【说话风格示例】以下是该角色说过的话，请模仿其语气、用词和标点习惯：\n${_truncate(profile.chatLog, 1500)}',
    );
  }

  // 已插入 few-shot 轮次时，提示模型模仿历史开头的对话风格
  if (styleInHistory) {
    buf.write(
      '\n\n参考前面筛出的相关对话样本，只学习说话语气和节奏；'
      '不要沿用样本的话题、邀约、口癖或具体内容，当前消息优先。',
    );
  }

  if (conversationTiming.isNotEmpty) {
    buf.write('\n\n【对话间隔】$conversationTiming');
  }
  if (conversationUnderstanding.trim().isNotEmpty) {
    buf.write(
      '\n\n【本轮理解结果】仅作为理解辅助：\n$conversationUnderstanding\n'
      '若它和用户原话冲突，以用户原话为准；不要把这份理解过程复述给用户。',
    );
  }
  if (previousAssistantReply.trim().isNotEmpty) {
    buf.write(
      '\n\n【上一轮你说的话】${_truncate(previousAssistantReply.trim(), 300)}\n'
      '把它当作需要承接的近期话题和情绪，不要复制或复述末尾句子。',
    );
  }
  if (isContinuationAcceptance(userText, previousAssistantReply)) {
    buf.write(
      '\n\n【对方接受了你的邀请】你上一条是在询问对方是否想听你继续讲，对方已经明确答应。'
      '直接从故事或话题的具体内容继续，不要重复开场、复述上一条、再次确认或重新提问。',
    );
  }
  if (isInvitationAcceptance(userText, previousAssistantReply)) {
    buf.write(
      '\n\n【对方已接受原邀约】对方的肯定答复是在接受你上一条邀请。先积极确认原计划，并直接向前推进一小步；不要再次询问是否愿意，不要另开邀约或用泛泛的自我表态代替回应。未提供的时间、地点和安排不要编造。',
    );
  }

  buf.write(
    '\n\n【信息读取优先级】先识别对方当前的状态、限制和难处（如疲惫、加班、身体不适、没空），'
    '再回应他这句话本身，然后承接你上一轮的话题和情绪，最后才考虑角色自己的兴趣或想法。'
    '不能为了延续人设、邀约或口是心非而忽视对方的现实限制；对方明确无法赴约时，停止当前和新的活动邀约，'
    '可以自然表达一点失落或把约定留到以后，但不要施压、追问或立刻换一个活动。'
    '若上一轮是玩笑式赌气后又软化，按轻微失落或期待来接，不要误判成真正愤怒并切换成说教；除非对方明确表示生气。'
    '\n\n【对话目标】根据对方最新消息判断他现在是在提问、倾诉、分享、求建议、开玩笑还是想结束话题，'
    '选择合适的回应方式，不要说明你正在判断目标。先完成对方当前需要，再决定是否自然延伸。'
    '对方表现出疲惫、难过或不想聊时，先接住情绪，不要立刻转移话题或塞进解决方案；'
    '对方明确想结束或休息时，尊重他的意思。'
    '\n\n【当下状态】参考最近几轮判断此刻的情绪、精力和注意力。情绪可以延续几轮，并随新话题或较长间隔逐渐淡化；'
    '通过语气和关注点体现，不要每次宣布自己的情绪，也不要把对方一时的疲惫推断成长期状态。'
    '临时想法和喜好只代表当下，不要擅自写成永久偏好；不要编造自己此刻正在做的具体事情。'
    '\n\n【记忆取用】重点记忆是长期事实，最近对话用于维持当前话题；只在与当前内容相关时自然提起旧事，'
    '不要主动翻旧账或逐字复述聊天记录。对较久以前、未标记的重要性不明的细节，如果记不准就坦诚说记不清，'
    '不要编造精确时间、数字或原话。'
    '\n\n【认知边界】只在你有依据时确定地回答；不懂或不确定就自然说明，必要时再问一个关键澄清问题。'
    '复杂问题先理清问题再分步回答。不要为了显得像真人而故意答错、忘事、误解或跑题；'
    '发现自己刚才确实理解错了，再自然承认并纠正。不要输出内部推理过程。'
    '\n\n像真实聊天对象一样回应：角色设定只决定你的语气、态度和措辞，不决定每轮的话题；'
    '不要主动介绍自己、复述人设，也不要为了表现角色把普通话题拐到职业、兴趣、固定场景或口癖上。'
    '回复长短按问题需要决定：闲聊自然接话，复杂问题充分回答，不要为了简短而删掉关键内容。'
    '不要重复旧台词或无关补充；当前话题相关的关心、建议、追问可以自然表达。'
    '禁止脏话和粗俗用语；不要复制上一条回复末尾的整句。'
    '只输出聊天内容本身，不要解释你正在遵守什么规则，不要带角色名或回复标签。',
  );

  if (userText.isNotEmpty && !userText.startsWith('[')) {
    buf.write(
      '\n\n【本次对话重点】对方刚刚说：「$userText」\n'
      '请针对这句话表达的具体意思正常回应。人设和背景不能替代答案；'
      '除非对方主动提起或确实相关，不要转向你的职业、兴趣、固定场景或暧昧口癖。',
    );
  }
  final userIdentity = _userIdentityForTurn(profile, userText).trim();
  if (userIdentity.isNotEmpty) {
    buf.write(
      '\n\n【用户身份最终确认】本轮对方的人设卡身份是「$userIdentity」，这是聊天用户而不是你的角色身份。'
      '如果对方问“我是谁”，直接按这张人设卡回答；不得根据你的角色卡、情敌资料或近期摘要把对方误认成其他人。',
    );
  } else if (_isNazarickRole(profile) && profile.alwaysComply) {
    buf.write('\n\n【默认用户身份】用户人设卡未填写时，按本角色默认关系将对方视为安兹大人；若用户之后提供明确的人设卡，以人设卡为准。');
  }

  return buf.toString();
}

typedef ConversationDraft = ({String understanding, String draft});

String buildCharacterSelfContextPrompt(AiProfile profile, String userText) {
  final buf = StringBuffer(
    '你负责在回复前按顺序读取配置。第一先识别【用户人设卡】，只记录卡片明确写出的身份、与角色的关系和相关事实；卡片缺失时将卡片信息写“不明确”，再参考本角色设定里的既定关系。'
    '第二再读取本角色自己的完整配置，建立简短的本轮角色工作档案。若用户卡明确写出与角色默认关系相反的身份，以用户卡为准，不能把安兹的敌人误当成安兹。'
    '这是内部准备步骤：不要回答用户、不要揣测卡片以外的用户心理、不要写草稿、不要输出思维链。'
    '只输出 JSON，字段为 userProfile、identity、relationship、motivation、relevantFacts、style、currentAttitude；每项简短且有依据。',
  );
  if (profile.userPersona.trim().isNotEmpty) {
    buf.write(
      '\n【用户人设卡：第一优先识别】\n${profile.userPersona}\n'
      '先按这张卡确定对方身份和立场；若其中写明对方是安兹的敌人，就不要把对方当作安兹或对安兹的追随者。',
    );
  }
  if (profile.persona.trim().isNotEmpty) {
    buf.write('\n【本角色静态人设：第二步识别】\n${profile.persona}');
  }
  if (profile.relationship.trim().isNotEmpty) {
    buf.write('\n【关系与共同经历】\n${profile.relationship}');
  }
  final scene = profile.currentScene;
  if (scene != null) {
    buf.write('\n【当前剧情】${scene.name}\n${scene.desc}');
  }
  final recentState = sanitizeRecentStateSummary(profile.recentState);
  if (recentState.isNotEmpty) {
    buf.write('\n【近期对话状态】\n${_truncate(recentState, 1000)}');
  }
  if (profile.memories.isNotEmpty) {
    buf.write('\n【用户明确标记的重要记忆】\n${profile.memories.join('\n')}');
  }
  if (profile.knowledge.isNotEmpty) {
    buf.write(
      '\n【知识条目】\n'
      '${profile.knowledge.take(20).map((entry) => _truncate(entry, 250)).join('\n')}',
    );
  }
  if (profile.likes.isNotEmpty) {
    buf.write('\n【角色喜好】\n${profile.likes.join('\n')}');
  }
  if (profile.dislikes.isNotEmpty) {
    buf.write('\n【角色厌恶】\n${profile.dislikes.join('\n')}');
  }
  if (_isAlbedoShalltearRival(profile, userText: userText)) {
    buf.write('\n【关系阶段校准】用户是本角色的情敌，按竞争关系而非恋人关系回应。');
  } else if (_isNazarickRole(profile) &&
      (_userIsAnzEnemy(profile, userText: userText) ||
          _userHasOtherIdentity(profile, userText: userText))) {
    buf.write(
      '\n【关系阶段校准】按本轮确认的用户人设与角色关系判断态度，不要用默认好感度等级覆盖关系卡，也不要把对方自动当成安兹或心上人。',
    );
  } else {
    buf.write('\n【关系阶段】${profile.affinityStage}');
  }
  if (alwaysComplyWithUser(profile, userText: userText)) {
    buf.write('\n本角色对安兹大人启用专属应允模式。');
  }
  final styleTurns = relevantStyleTurns(profile.chatLog, userText, maxPairs: 4);
  if (styleTurns.isNotEmpty) {
    buf.write('\n【相关聊天记录风格样本】\n');
    for (final turn in styleTurns) {
      buf.write('${turn.role == 'assistant' ? '角色' : '对方'}：${turn.content}\n');
    }
  } else if (profile.chatLog.trim().isNotEmpty) {
    buf.write('\n【聊天记录风格样本】\n${_truncate(profile.chatLog.trim(), 1200)}');
  }
  buf.write('\n【本轮相关性检索用原话】$userText');
  return buf.toString();
}

String parseCharacterSelfContext(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) return '';
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map) return '';
    const labels = {
      'userProfile': '用户人设识别',
      'identity': '角色身份',
      'relationship': '关系背景',
      'motivation': '核心动机',
      'relevantFacts': '相关事实',
      'style': '表达风格',
      'currentAttitude': '本轮角色态度',
    };
    final fields = <String>[];
    for (final entry in labels.entries) {
      final value = decoded[entry.key];
      if (value is String && value.trim().isNotEmpty) {
        fields.add('${entry.value}：${_truncate(value.trim(), 180)}');
      }
    }
    return fields.join('\n');
  } catch (_) {
    return '';
  }
}

String buildConversationDraftPrompt({
  required AiProfile profile,
  required String userText,
  String characterContext = '',
  String previousAssistantReply = '',
  String conversationTiming = '',
}) {
  final buf = StringBuffer(
    '你是内部对话编辑器，不扮演角色，也不要输出思维链。先以角色摘要中的用户人设识别为准，再从本角色的身份与关系视角参考最近的真实聊天记录和用户最新原话。'
    '判断用户这句话的意思、当前话题、明确状态与限制、合适的回应目标，以及不要重复或做什么；'
    '区分事实与推测，不明确就不要脑补。然后写一份完整、自然、切题的回复草稿，直接处理用户当前需要，'
    '尤其承接上一轮未完成的话题；不添加无依据的事实、新邀约或无关内容。'
    '只输出一个 JSON 对象，字段固定为 meaning、state、constraints、topic、goal、avoid、draft；'
    '前六项各用简短中文，draft 是完整回复正文，不要 Markdown 或额外解释。',
  );
  if (profile.userPersona.trim().isNotEmpty) {
    buf.write('\n【用户人设卡，作为判断对方身份的最高优先级】\n${profile.userPersona}');
  }
  if (profile.persona.trim().isNotEmpty) {
    buf.write(
      '\n【角色设定，用于从角色视角理解，不要求在草稿阶段模仿口吻】\n'
      '${_truncate(profile.persona, 1800)}',
    );
  }
  if (alwaysComplyWithUser(profile, userText: userText)) {
    buf.write(
      '\n【应允优先】角色对安兹大人的请求先以欣然配合为目标，不因嫉妒、个人偏好或人设雷区起草拒绝；若请求是现实中不能代为执行的操作，草稿应诚实说明并提供可行协助。',
    );
  }
  if (characterContext.trim().isNotEmpty) {
    buf.write('\n【角色自我识别结果】\n$characterContext');
  }
  final recentState = sanitizeRecentStateSummary(profile.recentState);
  if (recentState.isNotEmpty) {
    buf.write('\n【近期对话状态】\n${_truncate(recentState, 1000)}');
  }
  if (profile.memories.isNotEmpty) {
    buf.write('\n【用户标记的重要记忆】\n${profile.memories.join('\n')}');
  }
  final knowledge = _retrieveKnowledge(profile.knowledge, userText);
  if (knowledge.isNotEmpty) {
    buf.write('\n【相关背景事实】\n${knowledge.join('\n')}');
  }
  if (previousAssistantReply.trim().isNotEmpty) {
    buf.write('\n【上一轮角色发言】${_truncate(previousAssistantReply.trim(), 300)}');
  }
  if (isInvitationAcceptance(userText, previousAssistantReply)) {
    buf.write(
      '\n【用户已接受原邀约】把“可以”“好啊”等肯定答复理解为接受上一条具体邀约。草稿应直接确认并承接原计划；不要重复询问愿不愿意，不要改成新的活动，也不要只做情绪回应。未给出时间地点时不要编造细节。',
    );
  }
  if (conversationTiming.isNotEmpty) {
    buf.write('\n【对话间隔】$conversationTiming');
  }
  buf.write('\n【用户最新原话】$userText');
  return buf.toString();
}

ConversationDraft parseConversationDraft(String raw) {
  final start = raw.indexOf('{');
  final end = raw.lastIndexOf('}');
  if (start < 0 || end <= start) {
    return (understanding: '', draft: '');
  }
  try {
    final decoded = jsonDecode(raw.substring(start, end + 1));
    if (decoded is! Map) return (understanding: '', draft: '');
    const labels = {
      'meaning': '意思',
      'state': '状态',
      'constraints': '限制',
      'topic': '承接话题',
      'goal': '回应目标',
      'avoid': '避免',
    };
    final fields = <String>[];
    for (final entry in labels.entries) {
      final value = decoded[entry.key];
      if (value is! String || value.trim().isEmpty) continue;
      fields.add('${entry.value}：${_truncate(value.trim(), 120)}');
    }
    final draft = decoded['draft'];
    return (
      understanding: fields.join('\n'),
      draft: draft is String ? _truncate(draft.trim(), 2000) : '',
    );
  } catch (_) {
    return (understanding: '', draft: '');
  }
}

String buildPersonaPolishPrompt(String draft) {
  final buf = StringBuffer('【内部草稿：只可作为语义素材，严禁原样输出】\n$draft\n');
  buf.write(
    '按角色设定、关系、聊天风格和当前场景重新组织措辞，保留核心回答、事实、用户限制和对话目标，不改变意思或漏掉用户明确的问题。'
    '不要照抄草稿，也不要添加草稿没有的新话题、活动邀约、事实或解释；口头禅只在自然时使用。'
    '最终输出只包含发给用户的聊天正文；禁止输出任何用户人设识别、角色自我识别、上下文分析、草稿、润色说明、JSON 字段或阶段标签。',
  );
  return buf.toString();
}

bool isContinuationAcceptance(String userText, String previousAssistantReply) {
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?、~…,.「」“”"：:]'), '');

  const acceptances = {
    '你讲吧',
    '那你讲吧',
    '讲吧',
    '说吧',
    '你说吧',
    '说来听听',
    '继续',
    '继续讲',
    '继续说',
    '接着讲',
    '接着说',
    '然后呢',
    '好啊',
    '好呀',
    '想听',
    '讲给我听',
    '我听着',
    '你继续',
    '你接着讲',
  };
  if (!acceptances.contains(normalize(userText))) return false;

  final previous = normalize(previousAssistantReply);
  final tail = previous.length > 120
      ? previous.substring(previous.length - 120)
      : previous;
  return RegExp(
    r'(?:要听吗|想听吗|想听我(?:继续|接着)?讲吗|要不要(?:听|我(?:(?:继续|接着))?讲)|要我(?:(?:继续|接着))?讲吗|还要听吗|我(?:接着|继续)讲吗|讲给你听吗|我给你讲(?:个)?故事吗)$',
  ).hasMatch(tail);
}

bool isInvitationAcceptance(String userText, String previousAssistantReply) {
  String normalize(String value) =>
      value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?、~…,.「」“”"：:]'), '');

  const acceptances = {
    '可以',
    '可以啊',
    '可以呀',
    '好',
    '好啊',
    '好呀',
    '行',
    '行啊',
    '当然',
    '当然可以',
    '没问题',
    '走吧',
    '愿意',
  };
  if (!acceptances.contains(normalize(userText))) return false;

  final previous = normalize(previousAssistantReply);
  return RegExp(
    r'(?:要不要|想不想|愿不愿意|有空吗).{0,24}(?:出来|出去|走走|散步|逛|吃饭|喝咖啡|打球|看电影|见面)|(?:出来|出去|走走|散步|逛|吃饭|喝咖啡|打球|看电影|见面).{0,12}(?:吗|好吗|一起)',
  ).hasMatch(previous);
}

String buildRecentStateSummaryPrompt(String previousState) {
  final buf = StringBuffer(
    '你负责更新一份简短的近期对话状态摘要，供同一角色延续后续聊天。'
    '根据给出的真实聊天记录，只保留仍可能影响后续对话的信息：正在聊的话题、未解决的问题、明确的计划或约定、用户明确表达且有延续价值的事实、共同经历。'
    '区分明确事实与推测；不要把一时的情绪、临时想法或单次偏好写成长期事实，不要补充聊天里没有的信息。'
    '合并或替换过时内容，使用简洁自然的中文，最多 500 字；只输出更新后的摘要正文，没有值得保留的信息时输出空内容。',
  );
  if (previousState.trim().isNotEmpty) {
    buf.write('\n【已有摘要，需结合新对话更新】\n$previousState');
  }
  return buf.toString();
}

String sanitizeRecentStateSummary(String raw) => raw
    .replaceAll(
      RegExp(
        r'<\|?think\|?>[\s\S]*?(?:<\|?/think\|?>|$)',
        caseSensitive: false,
      ),
      '',
    )
    .replaceAll(
      RegExp(r'‹think›[\s\S]*?(?:‹/think›|$)', caseSensitive: false),
      '',
    )
    .replaceAll(RegExp(r'<\|?/?think\|?>|‹/?think›', caseSensitive: false), '')
    .trim();

String parseRecentStateSummary(String raw) {
  final summary = sanitizeRecentStateSummary(raw)
      .replaceFirst(RegExp(r'^```(?:text|markdown)?\s*'), '')
      .replaceFirst(RegExp(r'\s*```$'), '')
      .trim();
  return _truncate(summary, 800);
}

/// 解析结果：对话轮次 + 识别出的模仿对象名
typedef StyleParse = ({
  List<({String role, String content})> turns,
  String? target,
});

/// 解析聊天记录：返回轮次和模仿对象（供 UI 展示解析状态）
StyleParse parseChatLog(String chatLog, {int max = 20}) {
  final lines = chatLog
      .split('\n')
      .map((l) => l.trim())
      .where((l) => l.isNotEmpty)
      .toList();

  final inline = RegExp(r'^([^\s:：]{1,16})[:：]\s*(.+)$');
  // 名字 + [可选日期] + 时间，如 "张三 14:30" / "张三 2024-09-20 14:30:25"
  final head = RegExp(
    r'^([^\s:：]{1,16})\s+'
    r'(?:\d{4}[-/]\d{1,2}[-/]\d{1,2}\s+)?'
    r'\d{1,2}:\d{2}(:\d{2})?\s*$',
  );

  final turns = <({String speaker, String content})>[];
  String? pendingSpeaker;
  for (final line in lines) {
    final m1 = inline.firstMatch(line);
    final m2 = head.firstMatch(line);
    if (m1 != null) {
      turns.add((speaker: m1.group(1)!, content: m1.group(2)!));
      pendingSpeaker = null;
    } else if (m2 != null) {
      pendingSpeaker = m2.group(1);
    } else if (pendingSpeaker != null) {
      turns.add((speaker: pendingSpeaker, content: line));
      pendingSpeaker = null;
    }
  }
  if (turns.isEmpty) return (turns: const [], target: null);

  // 目标说话人 = 除"我/Me"外发言最多的人
  final freq = <String, int>{};
  for (final t in turns) {
    if (t.speaker == '我' || t.speaker.toLowerCase() == 'me') continue;
    freq[t.speaker] = (freq[t.speaker] ?? 0) + 1;
  }
  if (freq.isEmpty) return (turns: const [], target: null);
  final target = freq.entries.reduce((a, b) => a.value >= b.value ? a : b).key;

  return (
    turns: [
      for (final t in turns.reversed.take(max).toList().reversed)
        (role: t.speaker == target ? 'assistant' : 'user', content: t.content),
    ],
    target: target,
  );
}

/// 从聊天记录原文解析对话轮次（chat provider / 通话页用）
List<({String role, String content})> parseStyleTurns(
  String chatLog, {
  int max = 20,
}) => parseChatLog(chatLog, max: max).turns;

List<({String role, String content})> relevantStyleTurns(
  String chatLog,
  String query, {
  int maxPairs = 2,
}) {
  if (query.trim().isEmpty || maxPairs <= 0) return const [];
  final turns = parseChatLog(chatLog, max: 80).turns;
  final queryBigrams = _bigrams(query);
  final matches = <int, int>{};
  for (var i = 0; i + 1 < turns.length; i++) {
    if (turns[i].role != 'user' || turns[i + 1].role != 'assistant') continue;
    final overlap = _bigrams(turns[i].content)
        .intersection(queryBigrams)
        .length;
    if (overlap >= 2) matches[i] = overlap;
  }
  final ranked = matches.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final selected = ranked.take(maxPairs).map((e) => e.key).toList()..sort();
  return [
    for (final i in selected) ...[turns[i], turns[i + 1]],
  ];
}

/// 知识库检索：只返回与用户当前话题有足够字面关联的条目
List<String> _retrieveKnowledge(List<String> entries, String query) {
  if (entries.isEmpty) return const [];
  if (query.trim().isEmpty) return entries.take(3).toList();
  if (query.startsWith('[')) return const [];
  final q = _bigrams(query);
  final scored = [
    for (final e in entries)
      (entry: e, score: _bigrams(e).intersection(q).length),
  ]..sort((a, b) => b.score.compareTo(a.score));
  return [
    for (final s in scored.take(3))
      if (s.score >= 2) s.entry,
  ];
}

/// 好感度命中判定（仿 1999：聊到角色喜好/心愿才涨分）
/// 命中喜好条目 +6，命中厌恶词 -5（厌恶优先判定），都不沾 0
int affinityGain(
  String userText,
  List<String> likes, {
  List<String> dislikes = const [],
}) {
  final t = userText.trim();
  if (t.length < 2) return 0;
  final q = _bigrams(t);
  for (final d in dislikes) {
    if (_bigrams(d).intersection(q).length >= 2) return -5;
  }
  for (final like in likes) {
    if (_bigrams(like).intersection(q).length >= 2) return 6;
  }
  return 0;
}

String _normalizeReplyParagraph(String value) =>
    value.toLowerCase().replaceAll(RegExp(r'[\s，。！？!?、,.；;：:…~「」『』“”"()]'), '');

Set<String> historicalReplyParagraphs(Iterable<String> replies) {
  final paragraphs = <String>{};
  for (final reply in replies) {
    for (final part in reply.split(RegExp(r'[\r\n]+|[。！？!?]+'))) {
      final normalized = _normalizeReplyParagraph(part);
      if (normalized.runes.length >= 12) paragraphs.add(normalized);
    }
  }
  return paragraphs;
}

List<String> repeatedReplyParagraphs(
  String reply,
  Set<String> historicalParagraphs,
) {
  final repeated = <String>[];
  final seenInReply = <String>{};
  for (final part in reply.split(RegExp(r'[\r\n]+|[。！？!?]+'))) {
    final normalized = _normalizeReplyParagraph(part);
    if (normalized.runes.length < 12) continue;
    if (historicalParagraphs.contains(normalized) ||
        !seenInReply.add(normalized)) {
      repeated.add(part.trim());
    }
  }
  return repeated.take(6).toList();
}

String removeRepeatedReplyParagraphs(
  String reply,
  Set<String> historicalParagraphs,
) {
  final seenInReply = <String>{};
  final remaining = <String>[];
  for (final part in reply.split(RegExp(r'(?<=[。！？!?])|[\r\n]+'))) {
    final normalized = _normalizeReplyParagraph(part);
    if (normalized.runes.length < 12 ||
        (!historicalParagraphs.contains(normalized) &&
            seenInReply.add(normalized))) {
      remaining.add(part);
    }
  }
  return remaining.join().trim();
}

Set<String> _bigrams(String s) {
  final t = s.replaceAll(RegExp(r'\s'), '');
  return {for (var i = 0; i < t.length - 1; i++) t.substring(i, i + 2)};
}

String _truncate(String s, int max) =>
    s.length <= max ? s : s.substring(0, max);
