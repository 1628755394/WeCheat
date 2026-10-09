import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:record/record.dart';

import 'voice_recorder.dart';

/// Web 录音：record_web 输出 blob URL，stop 后 http 拉回字节
class VoiceRecorderImpl implements VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) return false;
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.opus),
        path: '',
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> stop() async {
    try {
      final url = await _recorder.stop();
      if (url == null || url.isEmpty) return null;
      final resp = await http.get(Uri.parse(url));
      return resp.statusCode == 200 ? resp.bodyBytes : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _recorder.stop();
    } catch (_) {}
  }

  @override
  void dispose() => _recorder.dispose();
}
