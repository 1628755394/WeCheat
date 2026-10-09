import 'dart:typed_data';

export 'voice_recorder_web.dart'
    if (dart.library.io) 'voice_recorder_io.dart';

/// 录音器跨平台封装（条件导出）：按住说话 → 返回音频字节
abstract class VoiceRecorder {
  /// 开始录音；无权限/不支持返回 false
  Future<bool> start();

  /// 停止并返回音频字节；取消或失败返回 null
  Future<Uint8List?> stop();

  /// 放弃当前录音
  Future<void> cancel();

  void dispose();
}
