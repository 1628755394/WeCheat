import '../../core/widgets/app_page_body.dart';
import '../../core/widgets/wechat_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../models/ai_profile.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../services/ai_prompt.dart';
import '../common/edit_field_page.dart';
import '../common/model_picker.dart';
import 'voice_api_settings_page.dart';
import 'writing_assistant_page.dart';
import 'expression_settings_page.dart';
import 'live2d_model_tile.dart';
import 'custom_actions_page.dart';
import 'mood_debug_page.dart';
import '../../providers/mood_provider.dart';
import '../../services/mood_policy.dart';

/// AI 设置页：角色人设 / 知识库 / 聊天记录样本（风格模仿）
class AiSettingsPage extends ConsumerWidget {
  final String conversationId;

  const AiSettingsPage({super.key, required this.conversationId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(aiProfileProvider(conversationId));
    final notifier = ref.read(aiProfileProvider(conversationId).notifier);
    final conversationRules = conversationRulesFor(profile);
    final mood = ref.watch(moodProvider(conversationId));

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('AI 设置')),
      body: AppPageBody(
        child: ListView(
          children: [
            const _SectionHeader('模型'),
            Material(
              color: Colors.white,
              child: ListTile(
                leading: const Icon(Icons.memory, color: AppColors.primary),
                title: const Text('模型', style: TextStyle(fontSize: 16)),
                subtitle: Text(
                  modelChoiceLabel(
                    ModelChoice(
                      provider: profile.provider,
                      baseUrl: profile.baseUrl,
                      apiKey: profile.apiKey,
                      model: profile.model,
                      providerName: profile.providerName,
                    ),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
                onTap: () => _pickModel(context, ref, profile),
              ),
            ),
            if (!const bool.fromEnvironment('dart.vm.product'))
              Material(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(Icons.tune, color: AppColors.primary),
                  title: const Text('情绪参数'),
                  subtitle: const Text('查看情绪状态、调整参数与预览回复规则'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          MoodDebugPage(conversationId: conversationId),
                    ),
                  ),
                ),
              ),
            const _SectionHeader('视频通话'),
            Material(
              color: Colors.white,
              child: Live2DModelTile(conversationId: conversationId),
            ),
            if (profile.live2dModel != null)
              Material(
                color: Colors.white,
                child: ListTile(
                  leading: const Icon(Icons.gesture),
                  title: const Text('自定义动作'),
                  subtitle: Text('${profile.live2dModel!.actions.length} 个动作'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(
                      builder: (_) =>
                          CustomActionsPage(conversationId: conversationId),
                    ),
                  ),
                ),
              ),
            const _SectionHeader('角色卡'),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.auto_awesome,
                      color: AppColors.primary,
                    ),
                    title: const Text('人设创作助手'),
                    subtitle: const Text('对话编写人设、开场白、样本与规则'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => WritingAssistantPage(
                          conversationId: conversationId,
                        ),
                      ),
                    ),
                  ),
                  const Divider(indent: 16, height: 1),
                  ListTile(
                    title: const Text('人设', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      profile.persona.isEmpty
                          ? '未设置，默认 AI 助手'
                          : profile.persona,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () => _edit(
                      context,
                      title: '人设',
                      initial: profile.persona,
                      hint: '例：你是"林晓雨"，25岁产品经理，说话温柔爱用语气词，回复简短',
                      onSave: notifier.setPersona,
                    ),
                  ),
                  const Divider(indent: 16, height: 1),
                  ListTile(
                    title: const Text('开场白', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      profile.greeting.isEmpty
                          ? '未设置，进空会话不会主动打招呼'
                          : profile.greeting,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () => _edit(
                      context,
                      title: '开场白',
                      initial: profile.greeting,
                      hint: '例：（倚在门边挑眉看你）哟，稀客\n仅对空会话生效',
                      onSave: notifier.setGreeting,
                    ),
                  ),
                  const Divider(indent: 16, height: 1),
                  ListTile(
                    title: const Text('我的人设', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      profile.userPersona.isEmpty
                          ? '未设置：告诉 TA"你是谁"，TA 会记住并自然引用'
                          : profile.userPersona,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () => _edit(
                      context,
                      title: '我的人设',
                      initial: profile.userPersona,
                      hint: '例：我是TA的青梅竹马，计算机系大四，加班狗，爱熬夜',
                      onSave: notifier.setUserPersona,
                    ),
                  ),
                  const Divider(indent: 16, height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.translate,
                      color: AppColors.primary,
                    ),
                    title: const Text('回复语言', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      _languageLabel(profile.language),
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () =>
                        _pickLanguage(context, notifier, profile.language),
                  ),
                  const Divider(indent: 16, height: 1),
                  SwitchListTile(
                    title: const Text('括号动作描写', style: TextStyle(fontSize: 16)),
                    subtitle: const Text(
                      '开启后回复带（）动作/神态；关闭则像正常人发微信只说人话',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    value: profile.allowActions,
                    onChanged: notifier.setAllowActions,
                  ),
                ],
              ),
            ),
            const _SectionHeader('对话规则（每轮回复执行）'),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.edit_note,
                      color: AppColors.primary,
                    ),
                    title: const Text('自定义对话规则'),
                    subtitle: Text(
                      profile.customRules.isEmpty
                          ? '未添加'
                          : profile.customRules.join('；'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _edit(
                      context,
                      title: '自定义对话规则',
                      initial: profile.customRules.join('\n'),
                      hint: '每行一条规则，应用于每轮回复',
                      onSave: (value) => notifier.setCustomRules(
                        value
                            .split('\n')
                            .map((line) => line.trim())
                            .where((line) => line.isNotEmpty)
                            .toList(),
                      ),
                    ),
                  ),
                  const Divider(indent: 16, height: 1),
                  ExpansionTile(
                    leading: const Icon(
                      Icons.rule_outlined,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      '三阶段回复流程',
                      style: TextStyle(fontSize: 16),
                    ),
                    subtitle: const Text(
                      '先识别角色 → 理解用户并起草 → 按人设润色',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    children: [
                      for (var i = 0; i < conversationRules.length; i++)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${i + 1}.',
                                style: const TextStyle(
                                  fontSize: 13,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  conversationRules[i],
                                  style: const TextStyle(
                                    fontSize: 13,
                                    height: 1.4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            // 剧情场景卡（猫箱式）：点了进场景发开场白，prompt 注入场景描述
            if (profile.scenes.isNotEmpty) ...[
              const _SectionHeader('剧情场景（点击进入，会发一条开场消息）'),
              Material(
                color: Colors.white,
                child: Column(
                  children: [
                    for (var i = 0; i < profile.scenes.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, height: 1),
                      ListTile(
                        leading: Icon(
                          i == profile.sceneIndex
                              ? Icons.play_circle_filled
                              : Icons.play_circle_outline,
                          color: i == profile.sceneIndex
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        title: Text(
                          profile.scenes[i].name,
                          style: const TextStyle(fontSize: 15),
                        ),
                        subtitle: Text(
                          profile.scenes[i].desc,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing: i == profile.sceneIndex
                            ? const Text(
                                '进行中',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              )
                            : null,
                        onTap: () {
                          if (i != profile.sceneIndex &&
                              profile.scenes[i].name.contains('争吵') &&
                              !canEnterConflictScene(mood, profile.affinity)) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('争吵剧情需要好感达到 70，且正处于赌气状态'),
                              ),
                            );
                            return;
                          }
                          ref
                              .read(
                                chatMessagesProvider(conversationId).notifier,
                              )
                              .enterScene(i == profile.sceneIndex ? -1 : i);
                          if (context.mounted) Navigator.of(context).pop();
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ],
            const _SectionHeader('知识库（回答时自动检索相关条目）'),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  for (var i = 0; i < profile.knowledge.length; i++) ...[
                    if (i > 0) const Divider(indent: 16, height: 1),
                    ListTile(
                      title: Text(
                        profile.knowledge[i],
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      trailing: IconButton(
                        icon: const Icon(
                          Icons.delete_outline,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                        onPressed: () => notifier.removeKnowledge(i),
                      ),
                      onTap: () => _edit(
                        context,
                        title: '知识条目',
                        initial: profile.knowledge[i],
                        onSave: (v) => notifier.updateKnowledge(i, v),
                      ),
                    ),
                  ],
                  if (profile.knowledge.isNotEmpty)
                    const Divider(indent: 16, height: 1),
                  ListTile(
                    leading: const Icon(Icons.add, color: AppColors.primary),
                    title: const Text(
                      '添加知识条目',
                      style: TextStyle(fontSize: 16, color: AppColors.primary),
                    ),
                    onTap: () => _edit(
                      context,
                      title: '知识条目',
                      hint: '例：用户叫小明，喜欢篮球，生日是3月15日',
                      onSave: notifier.addKnowledge,
                    ),
                  ),
                ],
              ),
            ),
            const _SectionHeader('聊天记录（AI 会模仿其中人物的语气）'),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  ListTile(
                    title: const Text('聊天记录样本', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      profile.chatLog.isEmpty
                          ? '带发言人名字的记录会解析成真实对话，效果更好'
                          : profile.chatLog,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () => _edit(
                      context,
                      title: '聊天记录样本',
                      initial: profile.chatLog,
                      hint: 'PC微信：右键消息→多选→勾选→复制，粘贴到这里即可\n也支持"名字: 内容"单行格式\n只贴目标人物一人的台词也行',
                      onSave: notifier.setChatLog,
                    ),
                  ),
                  // 解析状态反馈：让用户知道记录是否真的被读懂
                  if (profile.chatLog.isNotEmpty) _parseStatus(profile.chatLog),
                ],
              ),
            ),
            const _SectionHeader('重点记忆（聊天里长按消息标记，永久生效）'),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  if (profile.memories.isEmpty)
                    const ListTile(
                      title: Text(
                        '暂无记忆',
                        style: TextStyle(
                          fontSize: 15,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        '聊天页长按任意消息 →「标记为记忆」',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    )
                  else
                    for (var i = 0; i < profile.memories.length; i++) ...[
                      if (i > 0) const Divider(indent: 16, height: 1),
                      ListTile(
                        leading: const Icon(
                          Icons.star,
                          size: 18,
                          color: Colors.amber,
                        ),
                        title: Text(
                          profile.memories[i],
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 14),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.delete_outline,
                            size: 20,
                            color: AppColors.textSecondary,
                          ),
                          onPressed: () => notifier.removeMemoryAt(i),
                        ),
                      ),
                    ],
                ],
              ),
            ),
            const _SectionHeader('近期对话状态（后台每 8 条新消息更新，可编辑）'),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.history,
                      color: AppColors.primary,
                    ),
                    title: const Text('近期摘要', style: TextStyle(fontSize: 16)),
                    subtitle: Text(
                      profile.recentState.isEmpty
                          ? '暂无摘要。更新时会发送给当前选择的模型，可随时编辑或清空。'
                          : profile.recentState,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.chevron_right,
                          color: AppColors.textSecondary,
                        ),
                        if (profile.recentState.isNotEmpty)
                          IconButton(
                            tooltip: '清空近期摘要',
                            icon: const Icon(
                              Icons.delete_outline,
                              size: 20,
                              color: AppColors.textSecondary,
                            ),
                            onPressed: () => notifier.setRecentState(''),
                          ),
                      ],
                    ),
                    onTap: () => _edit(
                      context,
                      title: '近期对话状态',
                      initial: profile.recentState,
                      hint: '摘要会在聊天过程中后台更新，也可以在这里手动修改。',
                      onSave: (value) => notifier.setRecentState(value),
                    ),
                  ),
                ],
              ),
            ),
            const _SectionHeader('关系阶段（聊天互动会改变）'),
            Material(
              color: Colors.white,
              child: ListTile(
                leading: Icon(
                  relationshipStageForUser(profile) == '相爱'
                      ? Icons.favorite
                      : Icons.favorite_border,
                  color: relationshipStageForUser(profile) == '相爱'
                      ? Colors.redAccent
                      : AppColors.primary,
                ),
                title: const Text('关系阶段', style: TextStyle(fontSize: 16)),
                subtitle: Text(
                  '${relationshipStageForUser(profile)} · 好感度 ${profile.affinity}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
                onTap: () => _editAffinity(context, notifier, profile),
              ),
            ),
            if (profile.likes.isNotEmpty)
              Material(
                color: Colors.white,
                child: Column(
                  children: [
                    const ListTile(
                      dense: true,
                      title: Text(
                        '喜好与心愿',
                        style: TextStyle(
                          fontSize: 14,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      subtitle: Text(
                        '聊到这些话题好感度才会上涨',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                    for (var i = 0; i < profile.likes.length; i++)
                      ListTile(
                        dense: true,
                        leading: const Icon(
                          Icons.favorite_border,
                          size: 16,
                          color: Colors.redAccent,
                        ),
                        title: Text(
                          profile.likes[i],
                          style: const TextStyle(fontSize: 14),
                        ),
                      ),
                  ],
                ),
              ),
            const _SectionHeader('SoulNexus 克隆音色'),
            Material(
              color: Colors.white,
              child: ListTile(
                leading: const Icon(
                  Icons.face_retouching_natural,
                  color: AppColors.primary,
                ),
                title: const Text('虚拟演员'),
                subtitle: const Text('情绪敏感度、呼吸、视线与动作幅度'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push<void>(
                  MaterialPageRoute(
                    builder: (_) =>
                        ExpressionSettingsPage(conversationId: conversationId),
                  ),
                ),
              ),
            ),
            Material(
              color: Colors.white,
              child: Column(
                children: [
                  SwitchListTile(
                    title: const Text('自动发语音消息'),
                    subtitle: const Text('AI 正常回复会成为可点播的语音气泡'),
                    value: profile.autoVoiceMessages,
                    onChanged: notifier.setAutoVoiceMessages,
                  ),
                  const Divider(indent: 16, height: 1),
                  ListTile(
                    leading: const Icon(
                      Icons.record_voice_over,
                      color: AppColors.primary,
                    ),
                    title: const Text(
                      '语音服务与音色档案',
                      style: TextStyle(fontSize: 16),
                    ),
                    subtitle: Text(
                      profile.hasSoulNexusVoice
                          ? '已绑定克隆档案：${profile.voiceCloneProfileId}'
                          : '未绑定；连接自建 Voice API 后选择火山引擎音色',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    trailing: const Icon(
                      Icons.chevron_right,
                      color: AppColors.textSecondary,
                    ),
                    onTap: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => VoiceApiSettingsPage(
                          conversationId: conversationId,
                        ),
                      ),
                    ),
                  ),
                  if (profile.hasSoulNexusVoice || profile.voiceBytes != null)
                    ListTile(
                      leading: const Icon(
                        Icons.delete_outline,
                        color: Colors.red,
                      ),
                      title: const Text(
                        '删除当前音色',
                        style: TextStyle(color: Colors.red),
                      ),
                      onTap: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (dialogContext) => WeChatDialog(
                            title: const Text('删除当前角色的音色？'),
                            content: const Text(
                              '删除后使用系统语音。服务端的克隆档案可以在音色管理中单独删除。',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, false),
                                child: const Text('取消'),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.pop(dialogContext, true),
                                child: const Text(
                                  '删除',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ),
                            ],
                          ),
                        );
                        if (confirmed == true) await notifier.clearAllVoice();
                      },
                    ),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '人设、知识库和聊天风格用于生成通话回复。克隆音色由自建 Voice API 管理；火山引擎凭证只配置在 API 服务端。API Token 仅保存在本次运行内，退出应用后需要重新输入。手机需通过电脑局域网地址访问 API。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _languageLabel(String language) => switch (language) {
    'ja-JP' => '日语（日本）',
    'en-US' => '英语（美国）',
    _ => '中文（普通话）',
  };

  static Future<void> _pickLanguage(
    BuildContext context,
    AiProfileNotifier notifier,
    String current,
  ) async {
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('选择回复语言'),
        children: [
          for (final option in const [
            ('zh-CN', '中文（普通话）'),
            ('ja-JP', '日语（日本）'),
            ('en-US', '英语（美国）'),
          ])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, option.$1),
              child: Row(
                children: [
                  Icon(
                    option.$1 == current
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: option.$1 == current
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  const SizedBox(width: 10),
                  Text(option.$2),
                ],
              ),
            ),
        ],
      ),
    );
    if (selected != null && selected != current) {
      await notifier.setLanguage(selected);
    }
  }

  /// 调整关系阶段对应的好感度
  Future<void> _editAffinity(
    BuildContext context,
    AiProfileNotifier notifier,
    AiProfile profile,
  ) async {
    var value = profile.affinity.toDouble();
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => WeChatDialog(
          title: const Text('调整关系阶段'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${AiProfile.stageForAffinity(value.round())} · ${value.round()}',
                style: const TextStyle(fontSize: 20),
              ),
              Slider(
                value: value,
                min: -100,
                max: 100,
                divisions: 40,
                label: '${value.round()}',
                onChanged: (v) => setState(() => value = v),
              ),
              const Text(
                '相离 <0 · 相遇 0–19 · 相识 20–39 · 相知 40–59 · 相爱 ≥60',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                notifier.setAffinity(value.round());
                Navigator.pop(ctx);
              },
              child: const Text('确定'),
            ),
          ],
        ),
      ),
    );
  }

  /// 聊天记录解析状态：识别出对话轮次显示模仿对象，否则提示格式问题
  Widget _parseStatus(String chatLog) {
    final parsed = parseChatLog(chatLog);
    final String text;
    final Color color;
    if (parsed.turns.isNotEmpty) {
      text = '已识别 ${parsed.turns.length} 轮对话，模仿对象：${parsed.target}';
      color = AppColors.primary;
    } else {
      text = '未识别发言人名字，整段仅作风格示例（建议加"名字:"前缀或"名字 时间"行）';
      color = Colors.orange;
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: TextStyle(fontSize: 12, color: color)),
      ),
    );
  }

  /// 模型选择：本地 Ollama / cc-switch 服务商 / 手动密钥
  Future<void> _pickModel(
    BuildContext context,
    WidgetRef ref,
    AiProfile profile,
  ) async {
    final choice = await showModelPicker(
      context,
      ref,
      ModelChoice(
        provider: profile.provider,
        baseUrl: profile.baseUrl,
        apiKey: profile.apiKey,
        model: profile.model,
        providerName: profile.providerName,
      ),
    );
    if (choice == null) return;
    await ref
        .read(aiProfileProvider(conversationId).notifier)
        .setModelConfig(
          provider: choice.provider,
          baseUrl: choice.baseUrl,
          apiKey: choice.apiKey,
          model: choice.model,
          providerName: choice.providerName,
        );
  }

  Future<void> _edit(
    BuildContext context, {
    required String title,
    String initial = '',
    String hint = '',
    required Future<void> Function(String) onSave,
  }) async {
    final result = await Navigator.of(context).push<String>(
      MaterialPageRoute(
        builder: (_) => EditFieldPage(
          title: title,
          initial: initial,
          hint: hint,
          maxLines: 8,
        ),
      ),
    );
    if (result != null) await onSave(result.trim());
  }
}

class _SectionHeader extends StatelessWidget {
  final String text;
  const _SectionHeader(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
      child: Text(
        text,
        style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
      ),
    );
  }
}
