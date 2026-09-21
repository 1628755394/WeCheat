import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wecheat/providers/contact_override_provider.dart';
import 'package:wecheat/providers/conversation_provider.dart';

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
        .firstWhere((c) => c.id == 'conv1');
    expect(conv.contact.displayName, '林晓雨');

    // 设置备注
    await container
        .read(contactOverridesProvider.notifier)
        .setRemark(conv.contact, '小雨');

    // 覆盖层变化应触发派生列表更新
    final updated = container
        .read(resolvedConversationListProvider)
        .value!
        .firstWhere((c) => c.id == 'conv1');
    expect(updated.contact.remark, '小雨');
    expect(updated.contact.displayName, '小雨');
  });

  test('清空备注恢复原名', () async {
    await container.read(conversationListProvider.future);
    final conv = container
        .read(resolvedConversationListProvider)
        .value!
        .firstWhere((c) => c.id == 'conv1');

    await container
        .read(contactOverridesProvider.notifier)
        .setRemark(conv.contact, '小雨');
    await container
        .read(contactOverridesProvider.notifier)
        .setRemark(conv.contact, '');

    final updated = container
        .read(resolvedConversationListProvider)
        .value!
        .firstWhere((c) => c.id == 'conv1');
    expect(updated.contact.displayName, '林晓雨');
  });
}
