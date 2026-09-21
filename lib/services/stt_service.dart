import 'package:speech_to_text/speech_to_text.dart';

/// 语音识别：通话中按住说话转文字（Web 走浏览器 SpeechRecognition，可能受网络限制）
class SttService {
  final _stt = SpeechToText();
  bool _available = false;
  String _lastResult = '';

  bool get available => _available;
  String get lastResult => _lastResult;

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
