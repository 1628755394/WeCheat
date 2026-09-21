import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/avatar_picker.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/conversation_provider.dart';

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
  Uint8List? _avatarBytes;
  String? _avatarAsset;
  bool _saving = false;

  @override
  void dispose() {
    _nameController.dispose();
    _personaController.dispose();
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

    await ref.read(conversationListProvider.notifier).addConversation(
          Conversation(
            id: conversationId,
            contact: contact,
            lastMessage: '',
            lastMessageTime: DateTime.now(),
          ),
        );

    final persona = _personaController.text.trim();
    if (persona.isNotEmpty) {
      await ref
          .read(aiProfileProvider(conversationId).notifier)
          .setPersona(persona);
    }

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
      body: ListView(
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
                  const Text('点击设置头像',
                      style: TextStyle(
                          fontSize: 12, color: AppColors.textSecondary)),
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
              decoration: const InputDecoration(
                labelText: '人设（可选，稍后可改）',
                hintText: '例：你是"顾晚晴"，29岁律所合伙人，冰山御姐，忽冷忽热……',
                alignLabelWithHint: true,
                contentPadding: EdgeInsets.all(16),
                border: InputBorder.none,
              ),
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
    );
  }
}
