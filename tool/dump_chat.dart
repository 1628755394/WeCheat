// 调试工具：dump 某个会话的聊天记录（dart run tool/dump_chat.dart）
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';

import 'package:hive/hive.dart';

void main(List<String> args) async {
  // 用法：dart run tool/dump_chat.dart [会话id关键词，默认 jiexiaozi]
  final key = args.isEmpty ? 'jiexiaozi' : args.first;
  final tmp = Directory.systemTemp.createTempSync('hive_dump');
  File('C:/Users/17793/Documents/messages.hive')
      .copySync('${tmp.path}/messages.hive');
  Hive.init(tmp.path);
  final box = await Hive.openBox('messages');
  final list = <Map>[];
  for (final raw in box.values) {
    final m = raw as Map;
    if (key == 'all' ||
        (m['conversationId'] as String).contains(key)) {
      list.add(m);
    }
  }
  list.sort((a, b) =>
      (a['createdAt'] as int).compareTo(b['createdAt'] as int));
  for (final m in list) {
    final who = m['isMe'] == true ? '我' : '${m['senderId']}';
    final recalled = m['recalled'] == true ? ' [已撤回]' : '';
    final t =
        DateTime.fromMillisecondsSinceEpoch(m['createdAt'] as int);
    print('[${t.hour}:${t.minute.toString().padLeft(2, '0')}:'
        '${t.second.toString().padLeft(2, '0')}] [$who]$recalled '
        '${m['content']}');
    print('---');
  }
  print('total: ${list.length}');
  exit(0);
}
