import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:speech_to_text/speech_to_text.dart';

/// 语音识别：支持麦克风输入与本地 Faster-whisper 音频文件转写
class SttService {
  static const defaultTranscriptionEndpoint =
      'http://127.0.0.1:8000/v1/audio/transcriptions';

  final _stt = SpeechToText();
  bool _available = false;
  String _lastResult = '';

  bool get available => _available;
  String get lastResult => _lastResult;

  static Future<String?> transcribeAudio(
    Uint8List bytes, {
    String endpoint = defaultTranscriptionEndpoint,
    String fileName = 'voice.wav',
  }) async {
    if (bytes.isEmpty) return null;
    final request = http.MultipartRequest('POST', Uri.parse(endpoint))
      ..fields['model'] = 'whisper-1'
      ..fields['response_format'] = 'json'
      ..fields['language'] = 'zh'
      ..files.add(
        http.MultipartFile.fromBytes('file', bytes, filename: fileName),
      );
    final response = await request.send().timeout(const Duration(seconds: 120));
    final body = await response.stream
        .bytesToString()
        .timeout(const Duration(seconds: 120));
    if (response.statusCode != 200) {
      throw Exception('Whisper 接口返回 ${response.statusCode}');
    }
    return parseTranscriptionResponse(body);
  }

  static String? parseTranscriptionResponse(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['text'] is String) {
        final text = (decoded['text'] as String).trim();
        return text.isEmpty ? null : text;
      }
      if (decoded is String) {
        final text = decoded.trim();
        return text.isEmpty ? null : text;
      }
    } catch (_) {
      final text = body.trim();
      return text.isEmpty ? null : text;
    }
    return null;
  }

  Future<bool> init() async {
    if (_available) return true;
    try {
      _available = await _stt.initialize();
    } catch (_) {
      _available = false;
    }
    return _available;
  }

  /// 开始识别；onPartial 回传实时中间结果
  Future<void> listen({void Function(String text)? onPartial}) async {
    _lastResult = '';
    await _stt.listen(
      listenOptions: SpeechListenOptions(
        localeId: 'zh_CN',
        partialResults: true,
        cancelOnError: true,
      ),
      onResult: (result) {
        _lastResult = result.recognizedWords;
        onPartial?.call(_lastResult);
      },
    );
  }

  Future<void> stop() => _stt.stop();

  Future<void> cancel() => _stt.cancel();
}
