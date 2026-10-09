import 'dart:convert';

import '../models/ai_profile.dart';

/// Web 端写不了服务端本地路径，改用 base64 字段（需要服务端兼容；
/// 官方 GPT-SoVITS api_v2 只认 ref_audio_path，可在服务侧自行适配）
Future<Map<String, String>> refAudioFields(AiProfile profile) async {
  final bytes = profile.voiceBytes;
  if (bytes == null || bytes.isEmpty) return const {};
  return {'ref_audio_base64': base64Encode(bytes)};
}
