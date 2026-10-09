import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/repositories/ai_characters.dart';
import 'package:wecheat/services/ai_prompt.dart';

void main() {
  test('雅儿贝德内置角色包含新版人设与开场白', () {
    final character = AiCharacters.all.singleWhere((c) => c.id == 'yarebede');
    expect(character.persona, contains('创造者是翠玉录'));
    expect(character.persona, contains('对话范例'));
    expect(character.persona, contains('请尽情享受吧，安兹大人'));
    expect(character.persona, contains('反例只用于识别，严禁模仿'));
    expect(character.persona, contains('夏提雅视作头号情敌'));
    expect(character.greeting, contains('鼻尖轻嗅您的气息'));
    expect(character.chatLog, contains('刚才夏提雅过来见我'));
    expect(character.chatLog, contains('可以摸摸你的胸吗'));
    expect(character.allowActions, isTrue);
    expect(character.profile.alwaysComply, isTrue);
  });

  test('雅儿贝德启用安兹专属应允模式并展示对应规则', () {
    const profile = AiProfile(alwaysComply: true, affinity: 100);
    final prompt = buildAiSystemPrompt(profile, userText: '替我安排一下');
    const anzCardProfile = AiProfile(
      alwaysComply: true,
      persona: '你是雅儿贝德，侍奉安兹',
      userPersona: '安兹乌尔恭',
    );
    final anzCardPrompt = buildAiSystemPrompt(anzCardProfile);
    expect(anzCardPrompt, contains('【安兹专属绝对服从】'));
    expect(anzCardPrompt, contains('【用户身份最终确认】'));
    expect(prompt, contains('【安兹专属绝对服从】'));
    expect(prompt, contains('不因嫉妒、恐惧、个人偏好或角色雷区拒绝'));
    expect(prompt, contains('无法在现实中代为执行'));
    expect(prompt, isNot(contains('仍保留自己的真实偏好与边界')));
    expect(conversationRulesFor(profile).last, contains('雅儿贝德面对安兹大人的要求有求必应'));
    final draftPrompt = buildConversationDraftPrompt(
      profile: profile,
      userText: '替我安排一下',
    );
    expect(draftPrompt, contains('【应允优先】'));

    const enemyProfile = AiProfile(
      alwaysComply: true,
      persona: '你是雅儿贝德，效忠安兹',
      userPersona: '我是安兹大人的敌人',
    );
    final enemyPrompt = buildAiSystemPrompt(enemyProfile);
    expect(enemyPrompt, contains('【用户身份优先】'));
    expect(enemyPrompt, isNot(contains('【安兹专属绝对服从】')));
    expect(
      conversationRulesFor(enemyProfile)
          .any((rule) => rule.contains('用户人设卡明确将对方设为安兹的敌人')),
      isTrue,
    );

    const albedoUser = AiProfile(
      alwaysComply: true,
      affinity: 100,
      persona: '你是雅儿贝德，侍奉安兹',
      userPersona: '我是雅儿贝德',
    );
    final roleMatchedPrompt = buildAiSystemPrompt(albedoUser);
    expect(roleMatchedPrompt, contains('【用户身份与关系校准】'));
    expect(roleMatchedPrompt, contains('【用户身份最终确认】'));
    expect(roleMatchedPrompt, contains('我是雅儿贝德'));
    expect(roleMatchedPrompt, isNot(contains('【安兹专属绝对服从】')));
    expect(roleMatchedPrompt, isNot(contains('【关系亲密度】')));
  });

  test('夏提雅作为内置角色加入注册表并包含设定', () {
    final character = AiCharacters.all.singleWhere((c) => c.id == 'shalltear');
    expect(character.name, '夏提雅·布拉德弗伦');
    expect(character.persona, contains('魅魔之耻'));
    expect(character.persona, contains('洗脑失控'));
    expect(character.persona, contains('安兹的指令高于嗜血本能'));
    expect(character.greeting, contains('夏提雅在此等候您的命令'));
    expect(character.conversationId, 'conv_char_shalltear');
    expect(character.allowActions, isTrue);
  });

  test('宝青坊主内置角色遵循当前聊天规则且不预设恋爱关系', () {
    final character = AiCharacters.all.singleWhere(
      (item) => item.id == 'baoqingfangzhu',
    );
    final profile = character.profile;
    final prompt = buildAiSystemPrompt(profile, userText: '我今天有点累');

    expect(character.name, '宝青坊主');
    expect(character.conversationId, 'conv_char_baoqingfangzhu');
    expect(character.persona, contains('不会把每次帮助都变成讨债'));
    expect(character.persona, contains('关系可以逐渐亲近，但由对话自然形成'));
    expect(character.initialAffinity, 16);
    expect(profile.affinity, 16);
    expect(profile.alwaysComply, isFalse);
    expect(character.knowledge, isNotEmpty);
    expect(character.likes, isNotEmpty);
    expect(character.dislikes, isNotEmpty);
    expect(character.scenes, hasLength(2));
    expect(prompt, contains('【当前对话规则】'));
    expect(prompt, contains('当前消息优先'));
    expect(prompt, contains('不得复用本会话中该角色之前说过的完整句子或段落'));
    expect(prompt, contains('【关系疏远】'));
    expect(prompt, isNot(contains('【关系亲密度】')));
  });

  test('空资料使用默认提示词', () {
    final p = buildAiSystemPrompt(const AiProfile());
    expect(p, contains('AI 助手'));
    expect(p, isNot(contains('【参考知识】')));
  });

  test('人设注入 system prompt', () {
    final p = buildAiSystemPrompt(const AiProfile(persona: '你是林晓雨，说话温柔'));
    expect(p, contains('【角色设定】'));
    expect(p, contains('林晓雨'));
  });

  test('知识库按相关性检索注入', () {
    const profile = AiProfile(
      knowledge: ['用户喜欢篮球和游泳', '用户的生日是3月15日', '林晓雨养了一只猫'],
    );
    final p = buildAiSystemPrompt(profile, userText: '我生日是什么时候');
    expect(p, contains('【参考知识】'));
    expect(p, contains('生日是3月15日'));
  });

  test('知识库条目少时仍只注入相关内容', () {
    const profile = AiProfile(knowledge: ['完全无关的天文知识xyz', '用户喜欢吃火锅']);
    final p = buildAiSystemPrompt(profile, userText: '你喜欢吃火锅吗');
    expect(p, contains('【参考知识】'));
    expect(p, contains('用户喜欢吃火锅'));
    expect(p, isNot(contains('天文知识')));
  });

  test('没有相关知识时不注入任意条目', () {
    const profile = AiProfile(knowledge: ['喜欢篮球和烤冷面']);
    final p = buildAiSystemPrompt(profile, userText: '我最近加班好累');
    expect(p, isNot(contains('【参考知识】')));
    expect(p, isNot(contains('篮球')));
  });

  test('聊天记录无法解析时作为发言示例注入', () {
    const profile = AiProfile(chatLog: '哈哈好的呀');
    final p = buildAiSystemPrompt(profile);
    expect(p, contains('【说话风格示例】'));
    expect(p, contains('哈哈好的呀'));
  });

  test('聊天记录已解析成轮次时不重复注入', () {
    const profile = AiProfile(chatLog: '林晓雨: 哈哈好的呀');
    final p = buildAiSystemPrompt(profile, styleInHistory: true);
    expect(p, isNot(contains('【说话风格示例】')));
  });

  test('无关聊天样本可从提示词中完全排除', () {
    const profile = AiProfile(chatLog: '陈野: 走啊，去打球');
    final p = buildAiSystemPrompt(profile, suppressStyleExamples: true);
    expect(p, isNot(contains('去打球')));
  });

  test('风格样本只保留和当前话题相关的问答', () {
    const chatLog =
        '我: 周末打球吗\n'
        '陈野: 走啊，球场见\n'
        '陈野: 我等你\n'
        '我: 我最近加班好累\n'
        '陈野: 辛苦了，先休息会儿';
    final turns = relevantStyleTurns(chatLog, '我今天加班好累');
    expect(turns.length, 2);
    expect(turns.first.content, '我最近加班好累');
    expect(turns.last.content, '辛苦了，先休息会儿');
  });

  test('单行格式聊天记录解析成 few-shot 轮次', () {
    final turns = parseStyleTurns('我: 晚上吃啥\n林晓雨: 吃火锅呀\n我: 行\n林晓雨: 那就楼下那家');
    expect(turns.length, 4);
    // 林晓雨发言最多 → assistant；我 → user
    expect(turns[0].role, 'user');
    expect(turns[1].role, 'assistant');
    expect(turns[1].content, '吃火锅呀');
    expect(turns[3].role, 'assistant');
  });

  test('微信导出格式（名字 时间 换行 内容）解析', () {
    final turns = parseStyleTurns('林晓雨 14:20\n晚上一起吃饭吗\n我 14:21\n好啊去哪');
    expect(turns.length, 2);
    expect(turns[0].role, 'assistant');
    expect(turns[0].content, '晚上一起吃饭吗');
    expect(turns[1].role, 'user');
  });

  test('PC 微信多选复制格式（名字 日期 时间）解析', () {
    final turns = parseStyleTurns(
      '星仔  2024-09-20 14:30:25\n卧槽今天又加班\n我  2024-09-20 14:31:02\n辛苦了啊',
    );
    expect(turns.length, 2);
    expect(turns[0].role, 'assistant');
    expect(turns[0].content, '卧槽今天又加班');
    expect(turns[1].role, 'user');
    expect(turns[1].content, '辛苦了啊');
  });

  test('空/无法解析的聊天记录返回空', () {
    expect(parseStyleTurns(''), isEmpty);
    expect(parseStyleTurns('没有说话人标记的随便一段文字'), isEmpty);
  });

  test('角色设定只影响语气，回答优先回应当前话题', () {
    final p = buildAiSystemPrompt(
      const AiProfile(
        persona: '你是酒馆老板娘，风情亲近',
        userPersona: '对方是你的男朋友',
        relationship: '你们从小认识',
      ),
      userText: '我好累啊，不想上班',
      conversationUnderstanding: '意思：用户疲惫；限制：暂时无法活动；回应目标：体谅并承接邀约。',
      previousAssistantReply: '本来想约你打球，算了，等你有空再说。',
      conversationTiming: '你们隔了一阵子才继续聊天',
    );
    expect(p, contains('角色设定只决定你的语气、态度和措辞'));
    expect(p, contains('不要为了表现角色把普通话题拐到职业、兴趣'));
    expect(p, contains('对方刚刚说：「我好累啊，不想上班」'));
    expect(p, contains('【对话目标】'));
    expect(p, contains('【当下状态】'));
    expect(p, contains('【记忆取用】'));
    expect(p, contains('【认知边界】'));
    expect(p, contains('【信息读取优先级】'));
    expect(p, contains('【本轮理解结果】'));
    expect(p, contains('回应目标：体谅并承接邀约'));
    expect(p, contains('【上一轮你说的话】本来想约你打球'));
    expect(p, contains('对方明确无法赴约时，停止当前和新的活动邀约'));
    expect(p, contains('禁止脏话和粗俗用语'));
    expect(p, contains('不要复制上一条回复末尾的整句'));
    expect(p, contains('你们隔了一阵子才继续聊天'));
    expect(p, isNot(contains('最多一句')));
    expect(p, isNot(contains('不超过30个汉字')));
  });

  test('AI 配置展示用户、角色、上下文、润色和全历史禁复读规则', () {
    final rules = conversationRulesFor(const AiProfile());
    expect(rules.length, greaterThanOrEqualTo(6));
    expect(rules[0], contains('用户人设卡'));
    expect(rules[1], contains('本角色的人设'));
    expect(rules[2], contains('识别意图'));
    expect(rules[3], contains('不显示在消息气泡'));
    expect(rules[5], contains('本会话中该角色之前说过的完整句子或段落'));
  });

  test('跨历史检测并移除重复语音段落', () {
    final history = historicalReplyParagraphs(['王座之厅里，夏提雅已经等候多时。安兹大人请放心。']);
    expect(repeatedReplyParagraphs('王座之厅里，夏提雅已经等候多时！', history), isNotEmpty);
    final cleaned = removeRepeatedReplyParagraphs(
      '这是本轮的新回应。王座之厅里，夏提雅已经等候多时。',
      history,
    );
    expect(cleaned, contains('这是本轮的新回应'));
    expect(cleaned, isNot(contains('夏提雅已经等候多时')));
    expect(
      repeatedReplyParagraphs('这段相同内容在一条回复里不能重复。\n这段相同内容在一条回复里不能重复。', const {}),
      isNotEmpty,
    );
  });

  test('复读过滤不屏蔽角色专名和当前角色身份', () {
    const profile = AiProfile(
      persona: '你是雅儿贝德，深爱安兹大人，常说请尽情享受吧',
      userPersona: '安兹乌尔恭',
    );
    expect(
      ignoreRequiredNamesInRepeatedPhrases(
        ['安兹大人', '雅儿贝德', '请尽情享受吧', '尽情享受', '这句普通话重复出现'],
        profile,
        characterName: '雅儿贝德',
      ),
      ['这句普通话重复出现'],
    );
    expect(
      ignoreRequiredNamesInRepeatedPhrases(
        ['安兹大人', '捏碎喉咙'],
        profile,
        characterName: '雅儿贝德',
      ),
      ['捏碎喉咙'],
    );
  });

  test('角色自我识别读取人设、相关知识和聊天记录样本', () {
    const profile = AiProfile(
      persona: '你是沉稳的守护者',
      knowledge: ['你负责纳萨力克的事务'],
      chatLog: '雅儿贝德：一切听从您的吩咐',
      userPersona: '对方是安兹大人',
    );
    final prompt = buildCharacterSelfContextPrompt(profile, '今天有什么安排');
    expect(prompt, contains('【本角色静态人设：第二步识别】'));
    expect(prompt, contains('【用户人设卡：第一优先识别】'));
    expect(
      prompt.indexOf('【用户人设卡：第一优先识别】'),
      lessThan(prompt.indexOf('【本角色静态人设：第二步识别】')),
    );
    expect(prompt, contains('【知识条目】'));
    expect(prompt, contains('一切听从您的吩咐'));
    expect(prompt, contains('不要写草稿'));

    final context = parseCharacterSelfContext(
      '{"userProfile":"安兹大人的敌人","identity":"守护者","relationship":"忠诚侍奉","motivation":"安兹","relevantFacts":"管理纳萨力克","style":"优雅","currentAttitude":"恭敬"}',
    );
    expect(context, contains('用户人设识别：安兹大人的敌人'));
    expect(context, contains('角色身份：守护者'));
    expect(context, contains('本轮角色态度：恭敬'));
    expect(parseCharacterSelfContext('（内部思考过程，不应泄漏）'), isEmpty);
  });

  test('上下文分析与语义草稿在一个阶段完成', () {
    const profile = AiProfile(
      recentState: '角色刚问用户是否想听她讲小说。',
      memories: ['用户喜欢听悬疑故事'],
      knowledge: ['角色正在看一本民国背景的小说'],
    );
    final prompt = buildConversationDraftPrompt(
      profile: profile,
      userText: '你讲吧，讲讲民国小说',
      characterContext: '角色身份：雅儿贝德；表达风格：优雅缱绻。',
      previousAssistantReply: '我最近在看一本小说，要听吗？',
    );
    expect(
      prompt,
      contains('字段固定为 meaning、state、constraints、topic、goal、avoid、draft'),
    );
    expect(prompt, contains('不要输出思维链'));
    expect(prompt, contains('【角色自我识别结果】'));
    expect(prompt, contains('表达风格：优雅缱绻'));
    expect(prompt, contains('角色刚问用户是否想听她讲小说'));
    expect(prompt, contains('用户喜欢听悬疑故事'));
    expect(prompt, contains('民国背景的小说'));
    expect(prompt, contains('你讲吧'));
  });

  test('解析分析字段和草稿，异常格式安全回退', () {
    final result = parseConversationDraft(
      '```json\n{"meaning":"接受讲述邀请","state":"好奇","constraints":"无","topic":"上一条小说话题","goal":"直接继续讲","avoid":"不要重复邀请","draft":"她刚入法庭，就发现证词里有个矛盾。"}\n```',
    );
    expect(result.understanding, contains('回应目标：直接继续讲'));
    expect(result.draft, '她刚入法庭，就发现证词里有个矛盾。');
    expect(parseConversationDraft('不是 JSON').draft, isEmpty);
  });

  test('角色润色把草稿作为内部素材且只输出最终聊天内容', () {
    final p = buildPersonaPolishPrompt('今晚不方便，就等你有空再约。');
    expect(p, contains('保留核心回答、事实、用户限制和对话目标'));
    expect(p, contains('不要照抄草稿'));
    expect(p, contains('禁止输出任何用户人设识别'));
    expect(p, contains('不要添加草稿没有的新话题、活动邀约'));
    expect(p, contains('今晚不方便，就等你有空再约。'));
    expect(p, isNot(contains('【角色自我识别摘要】')));
    expect(p, isNot(contains('【上下文分析摘要】')));
  });

  test('关系阶段使用五级称谓', () {
    expect(AiProfile.stageForAffinity(-1), '相离');
    expect(AiProfile.stageForAffinity(0), '相遇');
    expect(AiProfile.stageForAffinity(20), '相识');
    expect(AiProfile.stageForAffinity(40), '相知');
    expect(AiProfile.stageForAffinity(60), '相爱');
    expect(const AiProfile(affinity: 100).affinityStage, '相爱');

    const shalltear = AiProfile(
      persona: '你是夏提雅，侍奉安兹并与雅儿贝德竞争',
      userPersona: '我是雅儿贝德',
      affinity: 100,
    );
    expect(relationshipStageForUser(shalltear), '相离');
    expect(buildAiSystemPrompt(shalltear), contains('【情敌关系优先】'));

    const albedo = AiProfile(
      persona: '你是雅儿贝德，侍奉安兹',
      userPersona: '我是雅儿贝德',
      affinity: 100,
    );
    expect(relationshipStageForUser(albedo), '相识');
    expect(buildAiSystemPrompt(albedo), contains('【用户身份与关系校准】'));
  });

  test('亲密关系不要求无条件服从或每轮调情', () {
    final p = buildAiSystemPrompt(const AiProfile(affinity: 100));
    expect(p, contains('仍保留自己的真实偏好与边界'));
    expect(p, isNot(contains('言听计从')));
    expect(p, contains('不必每轮撒娇或无条件答应'));
  });

  test('只在对方接受上一条邀请时识别为续讲', () {
    expect(isContinuationAcceptance('你讲吧', '我最近在看一本小说，要听吗？'), isTrue);
    expect(isContinuationAcceptance('继续', '我继续讲吗？'), isTrue);
    expect(isContinuationAcceptance('你讲吧', '你今天过得怎么样？'), isFalse);
    expect(isContinuationAcceptance('我好累', '要听吗？'), isFalse);

    final prompt = buildAiSystemPrompt(
      const AiProfile(),
      userText: '你讲吧',
      previousAssistantReply: '我最近在看一本小说，要听吗？',
    );
    expect(prompt, contains('【对方接受了你的邀请】'));
    expect(prompt, contains('直接从故事或话题的具体内容继续'));
  });

  test('可以啊会被识别为接受散步邀约并承接原计划', () {
    const previous = '刚听说你今天忙完休息会儿，要不要出来走走？';
    expect(isInvitationAcceptance('可以啊', previous), isTrue);
    expect(isInvitationAcceptance('可以啊', '你今天怎么样？'), isFalse);

    final draftPrompt = buildConversationDraftPrompt(
      profile: const AiProfile(),
      userText: '可以啊',
      previousAssistantReply: previous,
    );
    expect(draftPrompt, contains('【用户已接受原邀约】'));
    expect(draftPrompt, contains('不要重复询问愿不愿意'));

    final finalPrompt = buildAiSystemPrompt(
      const AiProfile(),
      userText: '可以啊',
      previousAssistantReply: previous,
    );
    expect(finalPrompt, contains('【对方已接受原邀约】'));
    expect(finalPrompt, contains('不要另开邀约'));
  });

  test('无邀请语境的普通短回复不触发续讲指令', () {
    final prompt = buildAiSystemPrompt(
      const AiProfile(),
      userText: '你讲吧',
      previousAssistantReply: '你今天过得怎么样？',
    );
    expect(prompt, isNot(contains('【对方接受了你的邀请】')));
  });

  test('冷战关系仍要求回应用户当前内容', () {
    final p = buildAiSystemPrompt(const AiProfile(affinity: -1));
    expect(p, contains('不要故意只回一个字'));
    expect(p, contains('回应对方当前说的具体内容'));
  });

  test('近期摘要持久化并兼容旧资料', () {
    const profile = AiProfile(
      recentState: '最近在准备考试，周末约好复习。',
      recentStateMessageCount: 24,
    );
    final restored = AiProfile.fromMap(profile.toMap());
    expect(restored.recentState, profile.recentState);
    expect(restored.recentStateMessageCount, 24);
    expect(AiProfile.fromMap({'persona': '旧资料'}).recentState, isEmpty);
  });

  test('近期摘要注入时强调仅用于承接近期对话', () {
    final p = buildAiSystemPrompt(
      const AiProfile(recentState: '最近在准备考试，周末约好复习。'),
    );
    expect(p, contains('【近期对话状态】'));
    expect(p, contains('周末约好复习'));
    expect(p, contains('临时情绪会变化'));
  });

  test('近期摘要更新提示避免将临时情绪写成长期事实', () {
    final prompt = buildRecentStateSummaryPrompt('用户今天有些疲惫');
    expect(prompt, contains('不要把一时的情绪'));
    expect(prompt, contains('【已有摘要，需结合新对话更新】'));
    expect(parseRecentStateSummary('```text\n用户在准备考试。\n```'), '用户在准备考试。');
    expect(
      parseRecentStateSummary('最近在读书。‹think›内部推理泄漏‹/think›仍在准备考试。'),
      '最近在读书。仍在准备考试。',
    );
  });

  test('通话模式附加口语化约束', () {
    final p = buildAiSystemPrompt(const AiProfile(), inCall: true);
    expect(p, contains('口语化'));
  });
}
