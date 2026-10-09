// 调试工具：直接改某个会话的 AI 资料字段（需先关闭应用）
// ignore_for_file: depend_on_referenced_packages, avoid_print
import 'dart:io';

import 'package:hive/hive.dart';

void main() async {
  Hive.init('C:/Users/17793/Documents');
  final box = await Hive.openBox('ai_profiles');
  const convId = 'conv_char_jiexiaozi'; // 陈野
  final raw = box.get(convId);
  if (raw == null) {
    print('profile not found');
    exit(1);
  }
  final map = Map<String, dynamic>.from(raw as Map);
  map['userPersona'] = '我叫阿哲，陈野的男朋友。跟她一个大院长大的发小，'
      '比她大一岁，计算机系大四。我性格比她稳，爱逗她惹她炸毛再哄好。'
      '她打球受伤都是我背她去医务室，她的糗事和软肋我全知道。'
      '她改不了口叫我"兄弟"，我也不急，反正人已经是我女朋友了。';
  map['relationship'] = '我和陈野是男女朋友关系：从小一起长大的发小，'
      '前阵子我表的白，她脸红着答应了。现在处在"名义上交往、相处还像哥们"的别扭期，'
      '她不许我当众秀恩爱，但私下里牵手拥抱都不躲。';
  await box.put(convId, map);
  print('updated $convId');
  await box.close();
  exit(0);
}
