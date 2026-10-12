import 'dart:io';
import 'dart:typed_data';

import 'package:record/record.dart';
import 'package:path/path.dart' as p;

import 'voice_recorder.dart';

/// 桌面/移动端录音：录到系统临时目录的 m4a 文件，stop 读回字节
class VoiceRecorderImpl implements VoiceRecorder {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  @override
  Future<bool> start() async {
    try {
      if (!await _recorder.hasPermission()) return false;
      _path = p.join(
        Directory.systemTemp.path,
        'wecheat_voice_${DateTime.now().millisecondsSinceEpoch}.m4a',
      );
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: _path!,
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<Uint8List?> stop() async {
    try {
      final path = await _recorder.stop();
      final p = path ?? _path;
      _path = null;
      if (p == null) return null;
      final file = File(p);
      if (!await file.exists()) return null;
      final bytes = await file.readAsBytes();
      await file.delete();
      return bytes.isEmpty ? null : bytes;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await _recorder.stop();
      final p = _path;
      _path = null;
      if (p != null && await File(p).exists()) await File(p).delete();
    } catch (_) {}
  }

  @override
  void dispose() => _recorder.dispose();
}
