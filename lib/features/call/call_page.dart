import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/output_mode_button.dart';
import '../../providers/output_mode_provider.dart';
import '../../models/contact.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../services/ai_prompt.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_api_client.dart';
import '../../services/voice_service.dart';
import '../../services/llm_service.dart';
import '../../services/virtual_actor.dart';
import 'actor_avatar.dart';
import 'live2d_actor.dart';

/// 剥掉（动作/神态）描写，只保留说话内容，避免 TTS 把动作念出来
String stripActions(String text) {
  // 移除所有中文括号（不管内部是什么）
  var result = text.replaceAll(RegExp(r'（[^）]*）'), '');
  // 移除所有英文括号（不管内部是什么）
  result = result.replaceAll(RegExp(r'\([^)]*\)'), '');
  return result.trim();
}

/// 音视频通话页：语音/视频双模式
/// AI 会话：接通后 Ollama 流式生成 → flutter_tts 播报 + 实时字幕；
/// 用户按住说话 → speech_to_text 识别 → 发给 AI。非 AI 会话响铃后无应答。
class CallPage extends ConsumerStatefulWidget {
  final String conversationId;
  final bool isVideo;

  const CallPage({
    super.key,
    required this.conversationId,
    this.isVideo = false,
  });

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
  final _voice = VoiceService();
  final _stt = SttService();
  final _inputController = TextEditingController();
  final _captions = <_Caption>[];
  final _captionScrollController = ScrollController();
  final _history = <({String role, String content})>[];
  Future<void> _speechQueue = Future<void>.value();
  int _speechGeneration = 0;
  int _turnGeneration = 0;
  bool _hasStyleTurns = false;
  Future<void>? _shutdown;

  _CallStatus _status = _CallStatus.ringing;
  Timer? _timer;
  Timer? _idleTimer;
  int _seconds = 0;
  DateTime? _lastUserInputTime;
  String _endReason = '';

  bool _sttReady = false;
  bool _listening = false;
  String _partial = '';
  bool _aiSpeaking = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _cameraOn = true;
  bool _ending = false;
  bool _live2dOn = true;
  VirtualActor? _actor;
  String _observedAiText = '';

  bool get _voiceOn => ref.read(outputModeProvider).speaks;
  bool _showInput = false;
  bool _showCaptions = false;

  CameraController? _camera;
  bool get _isAi => _conversation?.contact.isAi ?? false;

  Conversation? get _conversation => ref
      .read(resolvedConversationListProvider)
      .value
      ?.where((c) => c.id == widget.conversationId)
      .firstOrNull;

  @override
  void initState() {
    super.initState();
    unawaited(
      _boot().catchError((Object error) {
        debugPrint('Call initialization failed: $error');
        if (mounted && _status != _CallStatus.ended) _end('通话初始化失败：$error');
      }),
    );
  }

  Future<void> _boot() async {
    await _bootFast();
  }

  Future<void> _bootFast() async {
    await ref.read(outputModeProvider.notifier).ensureLoaded();
    if (!mounted || _status == _CallStatus.ended) return;
    // 会话列表可能还在加载，先等它就绪，确保能识别 AI 会话
    if (_conversation == null) {
      await ref.read(conversationListProvider.future);
      if (!mounted) return;
    }
    if (_isAi && _status == _CallStatus.ringing) {
      setState(() => _status = _CallStatus.connected);
      _startTimer();
      _startIdleTimer();
    }
    // 预载本会话的 AI 资料，保证通话第一轮就带人设/知识库
    await ref
        .read(aiProfileProvider(widget.conversationId).notifier)
        .ensureLoaded();
    if (!mounted || _status == _CallStatus.ended) return;
    if (_isAi && widget.isVideo) unawaited(_initCamera());
    if (_isAi) {
      _actor = VirtualActor(ref.read(aiProfileProvider(widget.conversationId)));
    }
    setState(() {});

    if (_isAi) {
      // 聊天记录样本解析成 few-shot 轮次放历史最前，通话中模仿其语气
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      final styleTurns = parseStyleTurns(profile.chatLog);
      _hasStyleTurns = styleTurns.isNotEmpty;
      _history.addAll(styleTurns);

      // 捎带最近聊天记录作上下文（system prompt 每轮按需组装）
      setState(() => _status = _CallStatus.connected);
      _startTimer();
      _startIdleTimer();
      final repository = ref.read(messageRepositoryProvider);
      await repository.init();
      if (!mounted || _status == _CallStatus.ended) return;
      final msgs = repository
          .loadByConversation(widget.conversationId)
          .where((m) => !m.recalled && m.type == MessageType.text)
          .toList();
      _history.addAll(
        msgs.reversed
            .take(10)
            .toList()
            .reversed
            .map(
              (m) => (role: m.isMe ? 'user' : 'assistant', content: m.content),
            ),
      );
      // 响铃 1.5s 后接通
      await Future.delayed(Duration.zero);
      if (!mounted || _status == _CallStatus.ended) return;
      setState(() => _status = _CallStatus.connected);
      _startTimer();
      _startIdleTimer(); // 启动空闲检测

      // 使用人设中的开场白，如果为空则用默认问候
      final greeting = profile.greeting.isEmpty
          ? '（电话接通了，先跟用户打个招呼）'
          : '（电话接通了）${profile.greeting}';
      unawaited(_aiTurn(greeting));
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
      final controller = CameraController(
        front,
        ResolutionPreset.low,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted || _status == _CallStatus.ended) {
        await controller.dispose();
        return;
      }
      setState(() => _camera = controller);
    } catch (_) {
      // 摄像头不可用：保持占位画面
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _seconds++);
    });
  }

  /// 启动空闲检测：30 秒无用户输入时 AI 主动询问
  void _startIdleTimer() {
    _idleTimer?.cancel();
    _lastUserInputTime = DateTime.now();
    _idleTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _status != _CallStatus.connected) {
        _idleTimer?.cancel();
        return;
      }
      _checkIdle();
    });
  }

  /// 重置空闲检测定时器（用户有输入时调用）
  void _resetIdleTimer() {
    _lastUserInputTime = DateTime.now();
  }

  /// 检查是否空闲超过 30 秒
  void _checkIdle() {
    if (_lastUserInputTime == null) return;
    final idleSeconds = DateTime.now()
        .difference(_lastUserInputTime!)
        .inSeconds;
    if (idleSeconds >= 30 && !_aiSpeaking) {
      _actor?.react(ActorEvent.silence);
      // 30 秒无输入且 AI 没在说话，主动询问
      _resetIdleTimer();
      unawaited(_aiTurn('（对方很久没说话了，主动关心一下）'));
    }
  }

  String get _duration =>
      '${(_seconds ~/ 60).toString().padLeft(2, '0')}:${(_seconds % 60).toString().padLeft(2, '0')}';

  void _scrollCaptionsToEnd({bool force = false}) {
    if (!_showCaptions) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_captionScrollController.hasClients) return;
      final position = _captionScrollController.position;
      if (!force && position.maxScrollExtent - position.pixels > 80) return;
      _captionScrollController.animateTo(
        position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _saveCallCaption(_Caption caption) async {
    if (caption.text.trim().isEmpty) return;
    final conversation = _conversation;
    if (conversation == null) return;
    try {
      final repository = ref.read(messageRepositoryProvider);
      await repository.init();
      await repository.save(
        Message(
          id: 'call_${DateTime.now().microsecondsSinceEpoch}',
          conversationId: widget.conversationId,
          senderId: caption.who == 'me' ? 'me' : conversation.contact.id,
          isMe: caption.who == 'me',
          type: MessageType.text,
          content: caption.text,
          createdAt: DateTime.now(),
        ),
      );
    } catch (error) {
      debugPrint('Call transcript save failed: $error');
    }
  }

  /// AI 说话一轮：流式生成 → 按句播报 TTS + 更新字幕
  Future<void> _aiTurn(String userContent) async {
    if (!mounted || _status != _CallStatus.connected) return;
    if (_aiSpeaking) await _interruptAiSpeech();
    if (!mounted || _status != _CallStatus.connected) return;
    final turn = ++_turnGeneration;

    // 检查是否已经有相同的用户输入（避免重复添加）
    final lastEntry = _history.isNotEmpty ? _history.last : null;
    if (lastEntry == null ||
        lastEntry.role != 'user' ||
        lastEntry.content != userContent) {
      _history.add((role: 'user', content: userContent));
    }

    final caption = _Caption('ai', '');
    setState(() {
      _captions.add(caption);
      _aiSpeaking = true;
    });
    _observedAiText = '';
    _scrollCaptionsToEnd();

    var full = '';
    var pending = '';
    var firstSegment = true;
    try {
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(
                profile,
                _history,
                systemPrompt: buildAiSystemPrompt(
                  profile,
                  userText: userContent,
                  inCall: true,
                  styleInHistory: _hasStyleTurns,
                ),
              )) {
        if (_status == _CallStatus.ended || turn != _turnGeneration) return;
        full += chunk;
        if (full.length - _observedAiText.length >= 16) {
          _observedAiText = full;
          _actor?.hearAi(full);
        }
        pending += chunk;
        caption.text = stripActions(full);
        if (mounted) setState(() {});
        _scrollCaptionsToEnd();
        var boundary = _speechBoundary(pending, first: firstSegment);
        while (boundary != null) {
          final sentence = pending.substring(0, boundary);
          pending = pending.substring(boundary);
          if (_voiceOn) _queueSpeech(sentence, turn);
          firstSegment = false;
          boundary = _speechBoundary(pending, first: firstSegment);
        }
      }
    } catch (error) {
      if (turn != _turnGeneration) return;
      debugPrint('Call AI response failed: $error');
      setState(
        () => caption.text = '回复生成失败：${LlmService.friendlyError(error)}',
      );
    }
    if (turn != _turnGeneration || _status == _CallStatus.ended) return;
    if (full.trim().isEmpty) {
      setState(() => _aiSpeaking = false);
      _actor?.stopSpeech();
      return;
    }
    _actor?.hearAi(full);
    if (pending.trim().isNotEmpty && _voiceOn) _queueSpeech(pending, turn);

    // 重复检测：如果回复与最近 3 轮高度相似，重新生成
    final cleanFull = stripActions(full).trim();
    final recentReplies = _history
        .where((h) => h.role == 'assistant')
        .map((h) => stripActions(h.content).trim())
        .toList()
        .reversed
        .take(3)
        .toList();
    if (_isTooSimilar(cleanFull, recentReplies)) {
      if (turn != _turnGeneration || _status == _CallStatus.ended) return;
      _addHint('检测到回复重复，正在重新生成…');
      // 清除当前字幕，重新生成
      setState(() => _captions.remove(caption));
      // 不要移除历史记录，因为用户输入已经添加了
      // 重新调用 _aiTurn，但不需要再添加用户输入
      await _retryWithDifferentContext(userContent, turn);
      return;
    }

    _history.add((role: 'assistant', content: full));
    unawaited(_saveCallCaption(caption));
    await _speechQueue;
    if (mounted && turn == _turnGeneration) {
      setState(() => _aiSpeaking = false);
      _actor?.stopSpeech();
    }
  }

  /// 重新生成回复（重复检测失败时）
  Future<void> _retryWithDifferentContext(
    String userContent,
    int originalTurn,
  ) async {
    if (!mounted ||
        _status != _CallStatus.connected ||
        originalTurn != _turnGeneration) {
      return;
    }
    final turn = ++_turnGeneration;
    final caption = _Caption('ai', '');
    setState(() {
      _captions.add(caption);
      _aiSpeaking = true;
    });
    _scrollCaptionsToEnd();

    var full = '';
    var pending = '';
    var firstSegment = true;
    try {
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      // 使用更强的防复读提示
      final enhancedPrompt =
          '${buildAiSystemPrompt(profile, userText: userContent, inCall: true, styleInHistory: _hasStyleTurns)}\n\n【重要】不要重复你刚才说过的话，也不要复制之前的回复内容。';
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(profile, _history, systemPrompt: enhancedPrompt)) {
        if (_status == _CallStatus.ended || turn != _turnGeneration) return;
        full += chunk;
        pending += chunk;
        caption.text = stripActions(full);
        if (mounted) setState(() {});
        _scrollCaptionsToEnd();
        var boundary = _speechBoundary(pending, first: firstSegment);
        while (boundary != null) {
          final sentence = pending.substring(0, boundary);
          pending = pending.substring(boundary);
          if (_voiceOn) _queueSpeech(sentence, turn);
          firstSegment = false;
          boundary = _speechBoundary(pending, first: firstSegment);
        }
      }
    } catch (error) {
      if (turn != _turnGeneration) return;
      debugPrint('Call AI retry failed: $error');
      setState(() => caption.text = '重试失败：${LlmService.friendlyError(error)}');
    }
    if (turn != _turnGeneration || _status == _CallStatus.ended) return;
    if (full.trim().isEmpty) {
      setState(() => _aiSpeaking = false);
      _actor?.stopSpeech();
      return;
    }
    _actor?.hearAi(full);
    if (pending.trim().isNotEmpty && _voiceOn) _queueSpeech(pending, turn);
    _history.add((role: 'assistant', content: full));
    unawaited(_saveCallCaption(caption));
    await _speechQueue;
    if (mounted && turn == _turnGeneration) {
      setState(() => _aiSpeaking = false);
      _actor?.stopSpeech();
    }
  }

  /// 重复检测：检查文本是否与最近回复过于相似
  bool _isTooSimilar(String text, List<String> recent) {
    if (recent.isEmpty) return false;
    if (text.length < 4) return false;

    // Jaccard 相似度检测
    for (final r in recent) {
      if (r.length < 4) continue;
      final similarity = _jaccardSimilarity(text, r);
      if (similarity > 0.4) return true; // 相似度超过 40% 认为重复
    }
    return false;
  }

  /// Jaccard 相似度计算（基于 bigram）
  double _jaccardSimilarity(String a, String b) {
    final bigramsA = _bigrams(a);
    final bigramsB = _bigrams(b);
    if (bigramsA.isEmpty || bigramsB.isEmpty) return 0.0;

    final intersection = bigramsA.intersection(bigramsB);
    final union = bigramsA.union(bigramsB);
    return union.isEmpty ? 0.0 : intersection.length / union.length;
  }

  /// 提取文本的 bigram 集合
  Set<String> _bigrams(String text) {
    final runes = text.runes.toList();
    final bigrams = <String>{};
    for (int i = 0; i < runes.length - 1; i++) {
      bigrams.add(String.fromCharCodes(runes.sublist(i, i + 2)));
    }
    return bigrams;
  }

  int? _speechBoundary(String text, {required bool first}) {
    final sentence = RegExp(r'[。！？!?；;\n]').firstMatch(text);
    if (!first) return sentence?.end;
    if (sentence != null &&
        text.substring(0, sentence.end).runes.length <= 24) {
      return sentence.end;
    }
    final pause = RegExp(r'[，、,:：]').firstMatch(text);
    if (pause != null) {
      final length = text.substring(0, pause.end).runes.length;
      if (length >= 6 && length <= 24) return pause.end;
    }
    final runes = text.runes.toList();
    if (runes.length < 24) return null;
    return String.fromCharCodes(runes.take(24)).length;
  }

  void _queueSpeech(String sentence, int turn) {
    final generation = _speechGeneration;
    _speechQueue = _speechQueue.catchError((_) {}).then((_) async {
      if (!_canSpeak(turn, generation)) return;
      await _speak(sentence, turn, generation);
    });
  }

  bool _canSpeak(int turn, int generation) =>
      mounted &&
      _status == _CallStatus.connected &&
      _voiceOn &&
      turn == _turnGeneration &&
      generation == _speechGeneration;

  Future<void> _startListening() async {
    if (_muted || _status != _CallStatus.connected) return;
    if (_aiSpeaking) await _interruptAiSpeech();
    _actor?.react(ActorEvent.userSpeech);
    if (!_sttReady) _sttReady = await _stt.init();
    if (!mounted || _status != _CallStatus.connected) return;
    if (!_sttReady) {
      _addHint('语音识别不可用，点右侧键盘图标改用文字输入');
      return;
    }
    setState(() {
      _listening = true;
      _partial = '';
    });
    await _stt.listen(
      onPartial: (t) {
        if (mounted) setState(() => _partial = t);
      },
    );
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    await _stt.stop();
    if (!mounted || _status != _CallStatus.connected) return;
    setState(() => _listening = false);
    final text = _stt.lastResult.isNotEmpty ? _stt.lastResult : _partial;
    if (text.trim().isEmpty) return;
    _actor?.hearUser(
      text,
      memories: ref.read(aiProfileProvider(widget.conversationId)).memories,
    );
    _resetIdleTimer(); // 重置空闲检测
    setState(() {
      _captions.add(_Caption('me', text));
      _partial = '';
    });
    unawaited(_saveCallCaption(_captions.last));
    _scrollCaptionsToEnd();
    unawaited(_aiTurn(text));
  }

  void _addHint(String text) {
    if (!mounted || _status == _CallStatus.ended) return;
    setState(() => _captions.add(_Caption('ai', text)));
  }

  Future<void> _interruptAiSpeech() async {
    _actor?.react(ActorEvent.interruption);
    _actor?.stopSpeech();
    _speechGeneration++;
    _turnGeneration++;
    await _tts.stop();
    await _voice.stop();
    if (mounted) setState(() => _aiSpeaking = false);
  }

  Future<void> _speak(String sentence, int turn, int generation) async {
    final spoken = stripActions(sentence);
    if (spoken.isEmpty || !_canSpeak(turn, generation)) return;
    final profile = ref.read(aiProfileProvider(widget.conversationId));
    try {
      if (profile.hasSoulNexusVoice &&
          profile.voiceApiBaseUrl.isNotEmpty &&
          VoiceApiRuntime.bearerToken.isNotEmpty) {
        final api = VoiceApiClient(baseUrl: profile.voiceApiBaseUrl);
        try {
          final bytes = await api.synthesizeVoice(
            profile.voiceCloneProfileId,
            spoken,
          );
          if (!_canSpeak(turn, generation)) return;
          _actor?.startSpeech();
          final played = await _voice.playAndWait(
            bytes,
            onProgress: (position, duration) {
              if (duration <= Duration.zero) return;
              final progress =
                  (position.inMicroseconds / duration.inMicroseconds)
                      .clamp(0.0, 1.0);
              // Clone audio exposes playback position, so pauses in the
              // envelope are reflected in the model instead of a fixed loop.
              _actor?.setSpeechEnergy(
                0.35 + 0.65 * (math.sin(progress * math.pi * 12) + 1) / 2,
              );
            },
          );
          if (!_canSpeak(turn, generation) || played) return;
        } catch (error) {
          debugPrint('Clone voice synthesis failed: $error');
        } finally {
          api.close();
        }
      }
      if (_canSpeak(turn, generation)) {
        _actor?.startSpeech();
        final played = await _tts.speak(spoken, language: profile.language);
        if (!played && _canSpeak(turn, generation)) {
          _addHint('系统语音播报失败，请检查音频输出设备和中文语音包');
        }
      }
    } finally {
      _actor?.stopSpeech();
    }
  }

  /// 切换字幕显示
  void _toggleCaptions() {
    if (!mounted) return;
    setState(() => _showCaptions = !_showCaptions);
    _scrollCaptionsToEnd(force: true);
  }

  /// 文字输入发送（键盘模式 / STT 兜底）
  void _sendTyped() {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _actor?.hearUser(
      text,
      memories: ref.read(aiProfileProvider(widget.conversationId)).memories,
    );
    _inputController.clear();
    _resetIdleTimer(); // 重置空闲检测
    setState(() => _captions.add(_Caption('me', text)));
    unawaited(_saveCallCaption(_captions.last));
    _scrollCaptionsToEnd();
    unawaited(_aiTurn(text));
  }

  void _end([String reason = '']) {
    if (!mounted || _ending || _status == _CallStatus.ended) return;
    _ending = true;
    if (mounted && widget.isVideo) {
      // Remove the native GPU view before releasing the route.
      setState(() => _live2dOn = false);
    }
    _endReason = reason;
    _actor?.stopSpeech();
    _speechGeneration++;
    _turnGeneration++;
    setState(() => _status = _CallStatus.ended);
    _timer?.cancel();
    _idleTimer?.cancel();
    final shutdown = _shutdownCall();
    Future.delayed(const Duration(milliseconds: 850), () async {
      if (!mounted) return;
      try {
        await shutdown.timeout(const Duration(seconds: 2));
      } catch (_) {}
      if (!mounted) return;
      try {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        } else {
          context.go('/chat/${widget.conversationId}');
        }
      } catch (error) {
        debugPrint('Call route cleanup failed: $error');
      }
    });
  }

  Future<void> _shutdownCall() => _shutdown ??= _releaseCall();

  Future<void> _releaseCall() async {
    try {
      await _tts.stop();
      await _voice.dispose();
      if (_sttReady) await _stt.cancel();
    } catch (error) {
      debugPrint('Call cleanup failed: $error');
    } finally {
      await _camera?.dispose();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _idleTimer?.cancel();
    _status = _CallStatus.ended;
    _speechGeneration++;
    _turnGeneration++;
    _actor?.stopSpeech();
    _inputController.dispose();
    _captionScrollController.dispose();
    unawaited(_shutdownCall());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(resolvedConversationListProvider);
    ref.watch(outputModeProvider);
    ref.listen(outputModeProvider, (previous, next) {
      if (!next.speaks) {
        _speechGeneration++;
        unawaited(_tts.stop());
        unawaited(_voice.stop());
      }
    });
    final contact = _conversation?.contact;
    final name = contact?.displayName ?? '通话';

    return Scaffold(
      backgroundColor: const Color(0xFF1F1F1F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F1F1F),
        foregroundColor: Colors.white,
        automaticallyImplyLeading: false,
        title: _statusText(name),
        actions: const [OutputModeButton(dark: true)],
      ),
      body: SafeArea(
        child: Stack(
          children: [
            // 远端画面 / 主内容
            Positioned.fill(
              bottom: _status == _CallStatus.connected ? 190 : 0,
              child: widget.isVideo
                  ? _remoteVideo(contact, name)
                  : _voiceMain(contact, name),
            ),
            // 字幕 + 底部控制区：字幕动态贴在控制区上方，不重叠
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_status == _CallStatus.connected)
                    _showCaptions ? _captionList() : _latestCaption(),
                  _controls(),
                ],
              ),
            ),
            // 视频模式：本地小窗
            if (widget.isVideo && _status == _CallStatus.connected && _cameraOn)
              Positioned(top: 60, right: 14, child: _selfPreview()),
          ],
        ),
      ),
    );
  }

  Widget _statusText(String name) {
    switch (_status) {
      case _CallStatus.ringing:
        return Text(
          '正在等待对方接受邀请…',
          style: TextStyle(color: Colors.white70, fontSize: 14),
        );
      case _CallStatus.connected:
        final profile = ref.read(aiProfileProvider(widget.conversationId));
        final cloneVoiceOn =
            _isAi &&
            _voiceOn &&
            profile.hasSoulNexusVoice &&
            profile.voiceApiBaseUrl.isNotEmpty &&
            VoiceApiRuntime.bearerToken.isNotEmpty;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _duration,
              style: const TextStyle(color: Colors.white70, fontSize: 14),
            ),
            if (cloneVoiceOn)
              const Text(
                '克隆音色通话中',
                style: TextStyle(color: Colors.white54, fontSize: 11),
              ),
          ],
        );
      case _CallStatus.ended:
        return Text(
          _endReason.isNotEmpty ? _endReason : '通话时长 $_duration',
          style: const TextStyle(color: Colors.white70, fontSize: 14),
        );
    }
  }

  Widget _voiceMain(Contact? contact, String name) {
    final profile = ref.read(aiProfileProvider(widget.conversationId));
    final actorSize = (MediaQuery.sizeOf(context).height * 0.20).clamp(
      105.0,
      160.0,
    );
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (contact != null)
            _actor != null && _status == _CallStatus.connected
                ? ActorAvatar(
                    contact: contact,
                    actor: _actor!,
                    profile: profile,
                    size: actorSize,
                  )
                : AppAvatar(contact: contact, size: 110),
          const SizedBox(height: 20),
          Text(
            name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _remoteVideo(Contact? contact, String name) {
    final profile = ref.read(aiProfileProvider(widget.conversationId));
    return Container(
      width: double.infinity,
      height: double.infinity,
      color: const Color(0xFF141414),
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (contact != null && _actor != null && _status == _CallStatus.connected && _live2dOn)
            Live2DActor(contact: contact, actor: _actor!, profile: profile)
          else if (contact != null)
            Center(child: AppAvatar(contact: contact, size: 130)),
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: Text(
              name,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ),
        ],
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
          child: Icon(Icons.videocam_off, color: Colors.white38, size: 30),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(width: 100, height: 140, child: child),
    );
  }

  Widget _captionList() {
    final height = (MediaQuery.sizeOf(context).height * 0.38).clamp(
      140.0,
      340.0,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxWidth: 600, maxHeight: height),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.76),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Scrollbar(
            controller: _captionScrollController,
            thumbVisibility: true,
            child: ListView.builder(
              controller: _captionScrollController,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              itemCount: _captions.length + (_listening ? 1 : 0),
              itemBuilder: (context, index) {
                final listening = index == _captions.length;
                final caption = listening ? null : _captions[index];
                final text = listening
                    ? (_partial.isEmpty ? '正在聆听…' : _partial)
                    : caption!.text;
                if (text.trim().isEmpty) return const SizedBox.shrink();
                final isAi = caption?.who == 'ai';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 34,
                        child: Text(
                          isAi ? 'TA' : '我',
                          style: TextStyle(
                            color: isAi
                                ? Colors.lightGreenAccent
                                : Colors.white54,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _latestCaption() {
    _Caption? latest;
    for (final caption in _captions.reversed) {
      if (caption.text.trim().isNotEmpty) {
        latest = caption;
        break;
      }
    }
    final listeningText = _listening
        ? (_partial.isEmpty ? '正在聆听…' : _partial)
        : null;
    if (latest == null && listeningText == null) return const SizedBox.shrink();
    final caption = _listening ? null : latest;
    final text = listeningText ?? caption!.text;
    final runes = text.runes.toList();
    final visibleText = runes.length > 90
        ? String.fromCharCodes(runes.skip(runes.length - 90))
        : text;
    final who = caption?.who ?? 'me';
    final isAi = who == 'ai';
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: Container(
          key: ValueKey<Object>(caption ?? listeningText!),
          constraints: const BoxConstraints(maxWidth: 560),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isAi ? Icons.graphic_eq : Icons.person_outline,
                size: 17,
                color: isAi ? Colors.lightGreenAccent : Colors.white70,
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  visibleText,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isAi ? Colors.white : Colors.white70,
                    fontSize: 15,
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
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
        // AI 会话：按住说话条 / 文字输入条（键盘图标切换）
        if (_isAi) _inputArea(),
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
              onTap: () {
                setState(() => _muted = !_muted);
                _actor?.react(_muted ? ActorEvent.mute : ActorEvent.unmute);
              },
            ),
            _controlButton(
              icon: _showCaptions ? Icons.subtitles : Icons.subtitles_outlined,
              label: '字幕',
              active: _showCaptions,
              onTap: _toggleCaptions,
            ),
          ],
        ),
      ],
    );
  }

  /// 输入区：按住说话（默认）或文字输入（豆包式切换）
  Widget _inputArea() {
    if (_showInput) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextField(
                  controller: _inputController,
                  autofocus: false,
                  onSubmitted: (_) => _sendTyped(),
                  decoration: const InputDecoration(
                    isDense: true,
                    border: InputBorder.none,
                    hintText: '输入文字…',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.send, color: Colors.white),
              onPressed: _sendTyped,
            ),
            IconButton(
              icon: const Icon(Icons.mic, color: Colors.white70),
              onPressed: () => setState(() => _showInput = false),
            ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onLongPressStart: (_) => unawaited(_startListening()),
              onLongPressEnd: (_) => unawaited(_stopListening()),
              child: Container(
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
          ),
          IconButton(
            icon: const Icon(Icons.keyboard, color: Colors.white70),
            onPressed: () => setState(() => _showInput = true),
          ),
        ],
      ),
    );
  }

  Widget _hangupButton() {
    return GestureDetector(
      onTap: _ending ? null : _end,
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
          const Text(
            '挂断',
            style: TextStyle(color: Colors.white70, fontSize: 12),
          ),
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
          Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
