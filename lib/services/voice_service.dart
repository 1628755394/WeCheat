import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

class VoiceService {
  AudioPlayer? _audioPlayer;
  AudioPlayer get _player => _audioPlayer ??= AudioPlayer();
  Completer<bool>? _activePlayback;
  Future<void>? _disposing;
  int _generation = 0;

  /// 播放合成音频
  Future<void> play(Uint8List bytes, {String? mimeType}) async {
    try {
      await stop();
      if (_disposing != null) return;
      await _player.play(BytesSource(bytes, mimeType: mimeType));
    } catch (error) {
      debugPrint('Voice playback failed: $error');
    }
  }

  Future<bool> playAndWait(
    Uint8List bytes, {
    String? mimeType,
    void Function(Duration position, Duration duration)? onProgress,
  }) async {
    await stop();
    if (_disposing != null || bytes.isEmpty) return false;
    final generation = _generation;
    final done = Completer<bool>();
    _activePlayback = done;
    var duration = Duration.zero;
    final completeSubscription = _player.onPlayerComplete.listen(
      (_) {
        if (!done.isCompleted) done.complete(true);
      },
      onError: (Object error) {
        debugPrint('Voice playback failed: $error');
        if (!done.isCompleted) done.complete(false);
      },
    );
    final progressSubscription = onProgress == null
        ? null
        : _player.onPositionChanged.listen((position) {
            onProgress(position, duration);
          });
    final durationSubscription = onProgress == null
        ? null
        : _player.onDurationChanged.listen((value) => duration = value);
    try {
      await _player.play(BytesSource(bytes, mimeType: mimeType));
      if (generation != _generation || _disposing != null) return false;
      return await done.future.timeout(const Duration(minutes: 2));
    } catch (error) {
      debugPrint('Voice playback failed: $error');
      return false;
    } finally {
      await completeSubscription.cancel();
      await progressSubscription?.cancel();
      await durationSubscription?.cancel();
      if (identical(_activePlayback, done)) _activePlayback = null;
    }
  }

  Future<void> stop() async {
    _generation++;
    final active = _activePlayback;
    _activePlayback = null;
    if (active != null && !active.isCompleted) active.complete(false);
    try {
      await _audioPlayer?.stop();
    } catch (_) {}
  }

  Future<void> dispose() => _disposing ??= _dispose();

  Future<void> _dispose() async {
    await stop();
    try {
      await _audioPlayer?.dispose();
    } catch (error) {
      debugPrint('Voice disposal failed: $error');
    }
  }
}

/// 剥掉（动作/神态）描写，只保留说话内容，避免 TTS 把动作念出来
String stripActions(String text) {
  // 移除所有中文括号（不管内部是什么）
  var result = text.replaceAll(RegExp(r'（[^）]*）'), '');
  // 移除所有英文括号（不管内部是什么）
  result = result.replaceAll(RegExp(r'\([^)]*\)'), '');
  return result.trim();
}
