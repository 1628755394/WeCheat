import 'dart:io';

import '../models/ai_profile.dart';

/// 桌面端：把参考音频落到临时文件，GPT-SoVITS api_v2 走 ref_audio_path
Future<Map<String, String>> refAudioFields(AiProfile profile) async {
  final bytes = profile.voiceBytes;
  if (bytes == null || bytes.isEmpty) return const {};
  final dir = Directory.systemTemp;
  final file = File(
      '${dir.path}${Platform.pathSeparator}wecheat_voice_${bytes.hashCode}.wav');
  if (!await file.exists()) await file.writeAsBytes(bytes, flush: true);
  return {'ref_audio_path': file.path};
}
