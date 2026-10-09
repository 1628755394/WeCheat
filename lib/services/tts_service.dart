import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';

/// 文字转语音：AI 通话里播报回复（Web 走浏览器 SpeechSynthesis）
class TtsService {
  // FlutterTts has one platform channel; extra instances replace its callbacks.
  static final _tts = FlutterTts();
  static bool _ready = false;
  static String _language = 'zh-CN';
  static Completer<bool>? _playback;
  static bool _speaking = false;
  static int _generation = 0;

  bool get _isWindows =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;

  Future<void> init({String language = 'zh-CN'}) async {
    if (_ready && _language == language) return;
    try {
      await _tts.setLanguage(language).timeout(const Duration(seconds: 5));
      _language = language;
      // Windows stop() dereferences a native result when this mode is enabled.
      // Wait for completion in Dart instead, including cancellation and errors.
      await _tts.awaitSpeakCompletion(!_isWindows);
      await _tts.setSpeechRate(0.5);
      await _tts.setVolume(1.0);
      _ready = true;
    } catch (error) {
      debugPrint('TTS initialization failed: $error');
      _ready = false;
    }
  }

  /// 播报一句话；Web 端浏览器会自动排队
  Future<bool> speak(String text, {String language = 'zh-CN'}) async {
    final generation = _generation;
    await init(language: language);
    if (!_ready || text.trim().isEmpty || generation != _generation) {
      return false;
    }
    final done = Completer<bool>();
    _playback = done;
    _speaking = true;
    if (_isWindows) {
      _tts.setCompletionHandler(() {
        if (!done.isCompleted) done.complete(true);
      });
      _tts.setCancelHandler(() {
        if (!done.isCompleted) done.complete(false);
      });
      _tts.setErrorHandler((error) {
        debugPrint('TTS playback failed: $error');
        if (!done.isCompleted) done.complete(false);
      });
    }
    try {
      final result = await _tts.speak(text);
      if (result != 1) return false;
      if (_isWindows) {
        return await done.future.timeout(const Duration(minutes: 2));
      }
      return true;
    } catch (error) {
      debugPrint('TTS playback failed: $error');
      return false;
    } finally {
      if (identical(_playback, done)) {
        _playback = null;
        _speaking = false;
      }
    }
  }

  Future<void> stop() async {
    _generation++;
    final done = _playback;
    _playback = null;
    if (done != null && !done.isCompleted) done.complete(false);
    if (!_speaking) return;
    _speaking = false;
    try {
      await _tts.stop();
    } catch (_) {}
  }

  Future<void> dispose() => stop();
}
