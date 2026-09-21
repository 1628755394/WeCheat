import 'package:flutter_tts/flutter_tts.dart';

/// 文字转语音：AI 通话里播报回复（Web 走浏览器 SpeechSynthesis）
class TtsService {
  final _tts = FlutterTts();
  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    try {
      await _tts.setLanguage('zh-CN');
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// 播报一句话；Web 端浏览器会自动排队
  Future<void> speak(String text) async {
    if (!_ready || text.trim().isEmpty) return;
    try {
      await _tts.speak(text);
    } catch (_) {}
  }

  Future<void> stop() async {
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() => stop();
}
