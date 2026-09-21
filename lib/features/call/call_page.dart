import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';

/// 音视频通话页：语音/视频双模式
/// AI 会话：接通后 Ollama 流式生成 → flutter_tts 播报 + 实时字幕；
/// 用户按住说话 → speech_to_text 识别 → 发给 AI。非 AI 会话响铃后无应答。
class CallPage extends ConsumerStatefulWidget {
  final String conversationId;
  final bool isVideo;

  const CallPage({super.key, required this.conversationId, this.isVideo = false});

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

enum _CallStatus { ringing, connected, ended }

class _Caption {
  final String who; // 'me' | 'ai'
  String text;
  _Caption(this.who, this.text);
}

class _CallPageState extends ConsumerState<CallPage> {
  final _tts = TtsService();
  final _stt = SttService();
  final _captions = <_Caption>[];
  final _history = <({String role, String content})>[];

  _CallStatus _status = _CallStatus.ringing;
  Timer? _timer;
  int _seconds = 0;
  String _endReason = '';

  bool _sttReady = false;
  bool _listening = false;
  String _partial = '';
  bool _aiSpeaking = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _cameraOn = true;

  CameraController? _camera;
  bool get _isAi => _conversation?.contact.isAi ?? false;

  Conversation? get _conversation => ref
      .read(conversationListProvider)
      .value
      ?.where((c) => c.id == widget.conversationId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    // 会话列表可能还在加载，先等它就绪，确保能识别 AI 会话
    if (_conversation == null) {
      await ref.read(conversationListProvider.future);
      if (!mounted) return;
    }
    await _tts.init();
    _sttReady = await _stt.init();
    if (_isAi && widget.isVideo) unawaited(_initCamera());
    if (!mounted) return;
    setState(() {});

    if (_isAi) {
      _history.add((
        role: 'system',
        content:
            '你正在和用户进行微信${widget.isVideo ? '视频' : '语音'}通话。用简短口语化的中文对话，每次一两句话，不要用列表和 markdown。',
      ));
      // 捎带最近聊天记录作上下文
      final msgs = ref
              .read(chatMessagesProvider(widget.conversationId))
              .value
              ?.messages ??
          [];
      _history.addAll(msgs.reversed
          .take(10)
          .toList()
          .reversed
          .map((m) => (role: m.isMe ? 'user' : 'assistant', content: m.content)));

      // 响铃 1.5s 后接通
      await Future.delayed(const Duration(milliseconds: 1500));
      if (!mounted || _status == _CallStatus.ended) return;
      setState(() => _status = _CallStatus.connected);
      _startTimer();
      unawaited(_aiTurn('（电话接通了，先跟用户打个招呼）'));
    } else {
      // 非 AI 会话：响铃 3 秒无应答
      await Future.delayed(const Duration(seconds: 3));
      if (!mounted || _status == _CallStatus.ended) return;
      _end('对方无应答');
    }
  }

  Future<void> _initCamera() async {
    try {
      final cams = await availableCameras();
      if (cams.isEmpty) return;
      final front = cams.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cams.first,
      );
      final controller =
          CameraController(front, ResolutionPreset.medium, enableAudio: false);
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (_) {
      // 摄像头不可用：保持占位画面
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  String get _duration =>
      '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  /// AI 说话一轮：流式生成 → 按句播报 TTS + 更新字幕
  Future<void> _aiTurn(String userContent) async {
    _history.add((role: 'user', content: userContent));
    final caption = _Caption('ai', '');
    setState(() {
      _captions.add(caption);
      _aiSpeaking = true;
    });

    var full = '';
    var pending = '';
    final sentenceEnd = RegExp(r'[。！？!?；;\n]');
    try {
      await for (final chunk
          in ref.read(ollamaServiceProvider).chat(_history)) {
        if (_status == _CallStatus.ended) return;
        full += chunk;
        pending += chunk;
        caption.text = full;
        if (mounted) setState(() {});
        // 遇到完整句子就送 TTS，边说边生成
        var match = sentenceEnd.firstMatch(pending);
        while (match != null) {
          final sentence = pending.substring(0, match.end);
          pending = pending.substring(match.end);
          unawaited(_tts.speak(sentence));
          match = sentenceEnd.firstMatch(pending);
        }
      }
    } catch (_) {
      caption.text = '（连接失败，请确认 Ollama 正在运行）';
    }
    if (pending.trim().isNotEmpty) unawaited(_tts.speak(pending));
    _history.add((role: 'assistant', content: full));
    if (mounted) setState(() => _aiSpeaking = false);
  }

  Future<void> _startListening() async {
    if (_muted || _status != _CallStatus.connected) return;
    if (!_sttReady) {
      _addHint('语音识别不可用（Chrome 语音识别依赖网络服务）');
      return;
    }
    if (_aiSpeaking) {
      // AI 说话中允许打断：停掉播报
      await _tts.stop();
    }
    setState(() {
      _listening = true;
      _partial = '';
    });
    await _stt.listen(onPartial: (t) {
      if (mounted) setState(() => _partial = t);
    });
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    await _stt.stop();
    setState(() => _listening = false);
    final text = _stt.lastResult.isNotEmpty ? _stt.lastResult : _partial;
    if (text.trim().isEmpty) return;
    setState(() {
      _captions.add(_Caption('me', text));
      _partial = '';
    });
    unawaited(_aiTurn(text));
  }

  void _addHint(String text) {
    setState(() => _captions.add(_Caption('ai', text)));
  }

  void _end([String reason = '']) {
    _endReason = reason;
    setState(() => _status = _CallStatus.ended);
    _timer?.cancel();
    unawaited(_tts.stop());
    unawaited(_stt.cancel());
    Future.delayed(const Duration(milliseconds: 900), () {
      if (mounted) context.pop();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _tts.dispose();
    _stt.cancel();
    _camera?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(conversationListProvider);
    final contact = _conversation?.contact;
    final name = contact?.displayName ?? '通话';

    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      body: SafeArea(
        child: Stack(
          children: [
            // 远端画面 / 主内容
            if (widget.isVideo) _remoteVideo(contact, name) else _voiceMain(contact, name),
            // 顶部状态
            Positioned(
              top: 16,
              left: 0,
              right: 0,
              child: Center(child: _statusText(name)),
            ),
            // 字幕区
            if (_status == _CallStatus.connected) _captionOverlay(),
            // 视频模式：本地小窗
            if (widget.isVideo && _status == _CallStatus.connected && _cameraOn)
              Positioned(
                top: 60,
                right: 14,
                child: _selfPreview(),
              ),
            // 底部控制区
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: _controls(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusText(String name) {
    switch (_status) {
      case _CallStatus.ringing:
        return Text('正在等待对方接受邀请…',
            style: TextStyle(color: Colors.white70, fontSize: 14));
      case _CallStatus.connected:
        return Text(_duration,
            style: const TextStyle(color: Colors.white70, fontSize: 14));
      case _CallStatus.ended:
        return Text(
          _endReason.isNotEmpty ? _endReason : '通话时长 $_duration',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        );
    }
  }

  Widget _voiceMain(Contact? contact, String name) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (contact != null) AppAvatar(contact: contact, size: 110),
          const SizedBox(height: 20),
          Text(name,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 160),
        ],
      ),
    );
  }

  Widget _remoteVideo(Contact? contact, String name) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF141414),
      child: Center(
        // AI 没有摄像头：头像 + 说话时呼吸缩放
        child: AnimatedScale(
          scale: _aiSpeaking ? 1.08 : 1.0,
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeInOut,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (contact != null) AppAvatar(contact: contact, size: 130),
              const SizedBox(height: 16),
              Text(name,
                  style: const TextStyle(color: Colors.white70, fontSize: 16)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _selfPreview() {
    Widget child;
    final cam = _camera;
    if (cam != null && cam.value.isInitialized) {
      child = CameraPreview(cam);
    } else {
      child = const ColoredBox(
        color: Color(0xFF2C2C2C),
        child: Center(
            child: Icon(Icons.videocam_off, color: Colors.white38, size: 30)),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 100, height: 140, child: child),
    );
  }

  Widget _captionOverlay() {
    final shown = _captions.length > 4
        ? _captions.sublist(_captions.length - 4)
        : _captions;
    return Positioned(
      left: 20,
      right: 20,
      bottom: 150,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          for (final c in shown)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(
                '${c.who == 'me' ? '我' : 'AI'}：${c.text}',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: c.who == 'me' ? Colors.white60 : Colors.white,
                  fontSize: 14,
                ),
              ),
            ),
          if (_listening)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _partial.isEmpty ? '正在聆听…' : _partial,
                style: const TextStyle(color: Colors.greenAccent, fontSize: 14),
              ),
            ),
        ],
      ),
    );
  }

  Widget _controls() {
    if (_status == _CallStatus.ringing) {
      return Center(child: _hangupButton());
    }
    if (_status == _CallStatus.ended) return const SizedBox.shrink();

    return Column(
      children: [
        // 按住说话（AI 会话且非静音）
        if (_isAi)
          GestureDetector(
            onLongPressStart: (_) => unawaited(_startListening()),
            onLongPressEnd: (_) => unawaited(_stopListening()),
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 60),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: _listening ? Colors.white : Colors.white24,
                borderRadius: BorderRadius.circular(6),
              ),
              alignment: Alignment.center,
              child: Text(
                _listening ? '松开 发送' : '按住 说话',
                style: TextStyle(
                  color: _listening ? Colors.black87 : Colors.white,
                  fontSize: 15,
                ),
              ),
            ),
          ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _controlButton(
              icon: _speakerOn ? Icons.volume_up : Icons.volume_off,
              label: '免提',
              active: _speakerOn,
              onTap: () => setState(() => _speakerOn = !_speakerOn),
            ),
            if (widget.isVideo)
              _controlButton(
                icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                label: '摄像头',
                active: _cameraOn,
                onTap: () => setState(() => _cameraOn = !_cameraOn),
              ),
            _hangupButton(),
            _controlButton(
              icon: _muted ? Icons.mic_off : Icons.mic,
              label: '静音',
              active: !_muted,
              onTap: () => setState(() => _muted = !_muted),
            ),
          ],
        ),
      ],
    );
  }

  Widget _hangupButton() {
    return GestureDetector(
      onTap: _end,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: Color(0xFFFA5151),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.call_end, color: Colors.white, size: 30),
          ),
          const SizedBox(height: 6),
          const Text('挂断', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _controlButton({
    required IconData icon,
    required String label,
    required bool active,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: active ? Colors.white24 : Colors.white10,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          ),
          const SizedBox(height: 6),
          Text(label,
              style: const TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
