import '../../core/widgets/app_page_body.dart';

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/avatar_picker.dart';
import '../../models/contact.dart';
import '../../models/ai_profile.dart';
import '../../models/conversation.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/conversation_provider.dart';
import '../common/model_picker.dart';
import 'persona_polish_dialog.dart';

/// 添加 AI 好友：填名字/人设/头像，创建一个新的 AI 会话
/// 每个 AI 好友有独立的人设、知识库、模型和聊天记录
class AddAiFriendPage extends ConsumerStatefulWidget {
  const AddAiFriendPage({super.key});

  @override
  ConsumerState<AddAiFriendPage> createState() => _AddAiFriendPageState();
}

class _AddAiFriendPageState extends ConsumerState<AddAiFriendPage> {
  final _nameController = TextEditingController();
  final _personaController = TextEditingController();
  final _greetingController = TextEditingController();
  Uint8List? _avatarBytes;
  String? _avatarAsset;
  ModelChoice _modelChoice = const ModelChoice();
  bool _saving = false;

  Future<void> _polishPersona() async {
    final result = await showDialog<String>(
      context: context,
      builder: (_) => PersonaPolishDialog(
        name: _nameController.text.trim(),
        persona: _personaController.text.trim(),
        profile: AiProfile(
          provider: _modelChoice.provider,
          baseUrl: _modelChoice.baseUrl,
          apiKey: _modelChoice.apiKey,
          model: _modelChoice.model,
          providerName: _modelChoice.providerName,
        ),
      ),
    );
    if (result != null && mounted) _personaController.text = result;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
    _greetingController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('先给 AI 好友起个名字')));
      return;
    }
    if (_saving) return;
    setState(() => _saving = true);

    final ts = DateTime.now().millisecondsSinceEpoch;
    final conversationId = 'conv_ai_$ts';
    final contact = Contact(
      id: 'ai_$ts',
      name: name,
      wechatId: 'ai_$ts',
      isAi: true,
      avatarAsset: _avatarAsset,
      avatarBytes: _avatarBytes,
    );

    await ref
        .read(conversationListProvider.notifier)
        .addConversation(
          Conversation(
            id: conversationId,
            contact: contact,
            lastMessage: '',
            lastMessageTime: DateTime.now(),
          ),
        );

    final persona = _personaController.text.trim();
    final notifier = ref.read(aiProfileProvider(conversationId).notifier);
    if (persona.isNotEmpty) {
      await notifier.setPersona(persona);
    }
    final greeting = _greetingController.text.trim();
    if (greeting.isNotEmpty) {
      await notifier.setGreeting(greeting);
    }
    await notifier.setModelConfig(
      provider: _modelChoice.provider,
      baseUrl: _modelChoice.baseUrl,
      apiKey: _modelChoice.apiKey,
      model: _modelChoice.model,
      providerName: _modelChoice.providerName,
    );

    if (!mounted) return;
    context.pop();
    context.push('/chat/$conversationId');
  }

  @override
  Widget build(BuildContext context) {
    final preview = Contact(
      id: 'preview',
      name: _nameController.text.trim(),
      isAi: true,
      avatarAsset: _avatarAsset,
      avatarBytes: _avatarBytes,
    );

    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(title: const Text('添加 AI 好友')),
      body: AppPageBody(
        child: ListView(
          children: [
            const SizedBox(height: 24),
            Center(
              child: GestureDetector(
                onTap: () => showAvatarPicker(
                  context,
                  onBytes: (bytes) async =>
                      setState(() => _avatarBytes = bytes),
                  onAsset: (asset) async =>
                      setState(() => _avatarAsset = asset),
                ),
                child: Column(
                  children: [
                    AppAvatar(contact: preview, size: 72),
                    const SizedBox(height: 8),
                    const Text(
                      '点击设置头像',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Material(
              color: Colors.white,
              child: TextField(
                controller: _nameController,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                  labelText: '名字',
                  hintText: '例：顾晚晴、星仔、学习助手',
                  contentPadding: EdgeInsets.symmetric(horizontal: 16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              child: TextField(
                controller: _personaController,
                maxLines: 6,
                decoration: InputDecoration(
                  suffixIcon: IconButton(
                    tooltip: '润色人设',
                    icon: const Icon(Icons.auto_awesome),
                    onPressed: _saving ? null : _polishPersona,
                  ),
                  labelText: '人设（可选，稍后可改）',
                  hintText: '例：你是"顾晚晴"，29岁律所合伙人，冰山御姐，忽冷忽热……',
                  alignLabelWithHint: true,
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              child: TextField(
                controller: _greetingController,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: '开场白（可选，进会话自动发第一句）',
                  hintText: '例：（倚在门边挑眉看你）哟，稀客',
                  alignLabelWithHint: true,
                  contentPadding: EdgeInsets.all(16),
                  border: InputBorder.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
            Material(
              color: Colors.white,
              child: ListTile(
                leading: const Icon(Icons.memory, color: AppColors.primary),
                title: const Text('模型', style: TextStyle(fontSize: 16)),
                subtitle: Text(
                  modelChoiceLabel(_modelChoice),
                  style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
                trailing: const Icon(
                  Icons.chevron_right,
                  color: AppColors.textSecondary,
                ),
                onTap: () async {
                  final choice = await showModelPicker(
                    context,
                    ref,
                    _modelChoice,
                  );
                  if (choice != null) {
                    setState(() => _modelChoice = choice);
                  }
                },
              ),
            ),
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '每个 AI 好友有独立的人设、知识库、聊天记录和模型，创建后可在聊天页右上角进入「AI 设置」完善。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: FilledButton(
                onPressed: _saving ? null : _save,
                child: Text(_saving ? '创建中…' : '创建并开始聊天'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
