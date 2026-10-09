import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/message.dart';
import 'package:wecheat/providers/ai_profile_provider.dart';
import 'package:wecheat/providers/contact_override_provider.dart';
import 'package:wecheat/providers/conversation_provider.dart';
import 'package:wecheat/services/stt_service.dart';

void main() {
  late Directory dir;
  late ProviderContainer container;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('hive_test');
    Hive.init(dir.path);
    container = ProviderContainer();
  });

  tearDown(() async {
    container.dispose();
    await Hive.close();
    await dir.delete(recursive: true);
  });

  test('设置备注后会话列表 displayName 生效', () async {
    // 等会话列表初始化
    await container.read(conversationListProvider.future);
    final conv = container
        .read(resolvedConversationListProvider)
        .value!
        .firstWhere((c) => c.id == 'conv_char_yujie');
    expect(conv.contact.displayName, '沈曼殊');

    // 设置备注
    await container
        .read(contactOverridesProvider.notifier)
        .setRemark(conv.contact, '曼殊姐');

    // 覆盖层变化应触发派生列表更新
    final updated = container
        .read(resolvedConversationListProvider)
        .value!
        .firstWhere((c) => c.id == 'conv_char_yujie');
    expect(updated.contact.remark, '曼殊姐');
    expect(updated.contact.displayName, '曼殊姐');
  });

  test('清空备注恢复原名', () async {
    await container.read(conversationListProvider.future);
    final conv = container
        .read(resolvedConversationListProvider)
        .value!
        .firstWhere((c) => c.id == 'conv_char_yujie');

    await container
        .read(contactOverridesProvider.notifier)
        .setRemark(conv.contact, '曼殊姐');
    await container
        .read(contactOverridesProvider.notifier)
        .setRemark(conv.contact, '');

    final updated = container
        .read(resolvedConversationListProvider)
        .value!
        .firstWhere((c) => c.id == 'conv_char_yujie');
    expect(updated.contact.displayName, '沈曼殊');
  });

  test('新内置夏提雅会补种单聊资料与全员群成员', () async {
    final conversations = await container.read(conversationListProvider.future);
    final shalltear = conversations.singleWhere(
      (c) => c.id == 'conv_char_shalltear',
    );
    expect(shalltear.contact.name, '夏提雅·布拉德弗伦');

    final profile = Hive.box('ai_profiles').get('conv_char_shalltear') as Map;
    expect(profile['persona'], contains('魅魔之耻'));
    expect(profile['allowActions'], isTrue);
    final albedoProfile =
        Hive.box('ai_profiles').get('conv_char_yarebede') as Map;
    expect(albedoProfile['allowActions'], isTrue);
    final group = conversations.singleWhere(
      (c) => c.id == 'conv_group_chars',
    );
    expect(group.members.any((member) => member.id == 'char_shalltear'), isTrue);
  });

  test('语音消息持久化原始文件名供转写使用', () {
    final message = Message(
      id: 'voice_1',
      conversationId: 'conv_1',
      senderId: 'me',
      isMe: true,
      type: MessageType.voice,
      content: '',
      audioBytes: Uint8List.fromList([1, 2, 3]),
      audioFileName: 'memo.ogg',
      createdAt: DateTime(2026),
    );
    final restored = Message.fromMap(message.toMap());
    expect(restored.audioFileName, 'memo.ogg');
    expect(restored.audioBytes!.toList(), [1, 2, 3]);
  });

  test('本地 Whisper 转写结果解析 JSON 与纯文本', () {
    expect(
      SttService.parseTranscriptionResponse('{"text":"你好，安兹大人。"}'),
      '你好，安兹大人。',
    );
    expect(SttService.parseTranscriptionResponse('  你好。\n'), '你好。');
    expect(SttService.parseTranscriptionResponse('  '), isNull);
  });

  test('导入克隆音色时保留已有 AI 资料', () async {
    final box = await Hive.openBox('ai_profiles');
    final initial = const AiProfile(persona: '既有人设', model: 'test-model')
        .copyWith(transcriptionEndpoint: 'http://127.0.0.1:9000/v1/audio/transcriptions');
    await box.put('voice_test', initial.toMap());
    final bytes = Uint8List.fromList([1, 2, 3]);
    await container
        .read(aiProfileProvider('voice_test').notifier)
        .setVoice(bytes, 'sample.wav');

    final saved = AiProfile.fromMap(box.get('voice_test') as Map);
    expect(saved.persona, '既有人设');
    expect(saved.model, 'test-model');
    expect(
      saved.transcriptionEndpoint,
      'http://127.0.0.1:9000/v1/audio/transcriptions',
    );
    expect(saved.voiceName, 'sample.wav');
    expect(saved.voiceBytes!.toList(), [1, 2, 3]);
  });

  test('聊天背景按会话独立持久化并可恢复默认', () async {
    final first = container.read(chatBackgroundProvider('conv_a').notifier);
    final second = container.read(chatBackgroundProvider('conv_b').notifier);
    await first.setColor(0xFFF4F0E8);
    await second.setImage(Uint8List.fromList([1, 2, 3]));

    expect(container.read(chatBackgroundProvider('conv_a')).colorValue,
        0xFFF4F0E8);
    expect(container.read(chatBackgroundProvider('conv_a')).imageBytes, isNull);
    expect(container.read(chatBackgroundProvider('conv_b')).colorValue, isNull);
    expect(
      container.read(chatBackgroundProvider('conv_b')).imageBytes!.toList(),
      [1, 2, 3],
    );

    final saved = ChatBackground.fromMap(
      Hive.box('chat_backgrounds').get('conv_b') as Map,
    );
    expect(saved.imageBytes!.toList(), [1, 2, 3]);

    await first.clear();
    expect(container.read(chatBackgroundProvider('conv_a')).colorValue, isNull);
    expect(container.read(chatBackgroundProvider('conv_a')).imageBytes, isNull);
  });
}
