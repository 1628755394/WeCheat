import 'dart:async';
import 'dart:math' as math;

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/app_avatar.dart';
import '../../core/widgets/output_mode_button.dart';
import '../../providers/output_mode_provider.dart';
import '../../models/contact.dart';
import '../../models/ai_profile.dart';
import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../providers/ai_profile_provider.dart';
import '../../providers/mood_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/call_performance_provider.dart';
import '../../providers/conversation_provider.dart';
import '../../services/ai_prompt.dart';
import '../../services/mood_policy.dart';
import '../../services/stt_service.dart';
import '../../services/tts_service.dart';
import '../../services/voice_api_client.dart';
import '../../services/realtime_voice_call.dart';
import '../../services/voice_service.dart';
import '../../services/llm_service.dart';
import '../../services/virtual_actor.dart';
import '../../services/repetition_policy.dart';
import 'actor_avatar.dart';
import 'live2d_actor.dart';
import 'call_waiting_view.dart';
import 'mao_actions.dart';
import '../../services/call_greeting.dart';

/// 剥掉（动作/神态）描写，只保留说话内容，避免 TTS 把动作念出来
String stripActions(String text) {
  // 移除所有中文括号（不管内部是什么）
  var result = text.replaceAll(RegExp(r'（[^）]*）'), '');
  // 移除所有英文括号（不管内部是什么）
  result = result.replaceAll(RegExp(r'\([^)]*\)'), '');
  return result.trim();
}

/// 音视频通话页：语音/视频双模式
/// 绑定 SoulNexus 音色的 AI 会话接通后持续传送麦克风 PCM，
/// 由服务端识别、生成回复并合成语音；其他 AI 会话使用本地语音输入。
/// 非 AI 会话响铃后无应答。
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
  RealtimeVoiceCall? _realtimeCall;
  bool _realtimeConnecting = false;
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
  bool _pressHeld = false;
  bool _realtimeMicReady = false;
  String _partial = '';
  bool _aiSpeaking = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _cameraOn = true;
  bool _ending = false;
  bool _live2dOn = true;
  bool _modelPending = false;
  int _idleNudgeIndex = 0;
  VirtualActor? _actor;

  bool get _voiceOn => ref.read(outputModeProvider).speaks;
  bool _showInput = false;
  String? _commandFeedback;
  int _measuredFrames = 0;
  int _slowFrames = 0;

  bool get _hasAnimatedModel {
    final profile = ref.read(aiProfileProvider(widget.conversationId));
    return _isAi &&
        widget.isVideo &&
        _live2dOn &&
        profile.live2dModel != null &&
        profile.expressionProfile.animationEnabled &&
        ref.read(callPerformanceProvider).rendersModel;
  }

  void _onFrameTimings(List<FrameTiming> timings) {
    if (!mounted || _status == _CallStatus.ended) return;
    for (final timing in timings) {
      _measuredFrames++;
      if (timing.buildDuration.inMilliseconds > 40 ||
          timing.rasterDuration.inMilliseconds > 40) {
        _slowFrames++;
      }
    }
    if (_measuredFrames < 30) return;
    if (_slowFrames >= 8) {
      ref.read(callPerformanceProvider.notifier).reduceEffects();
    }
    _measuredFrames = 0;
    _slowFrames = 0;
  }

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
    SchedulerBinding.instance.addTimingsCallback(_onFrameTimings);
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
    await ref.read(callPerformanceProvider.notifier).ensureLoaded();
    if (!mounted || _status == _CallStatus.ended) return;
    // 会话列表可能还在加载，先等它就绪，确保能识别 AI 会话
    if (_conversation == null) {
      await ref.read(conversationListProvider.future);
      if (!mounted) return;
    }
    // 预载本会话的 AI 资料，保证通话第一轮就带人设/知识库
    await ref
        .read(aiProfileProvider(widget.conversationId).notifier)
        .ensureLoaded();
    await ref.read(moodProvider(widget.conversationId).notifier).ensureLoaded();
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
      // Start native loading immediately; keep the invitation overlay until ready.
      if (_hasAnimatedModel) {
        setState(() => _modelPending = true);
      } else {
        await Future.delayed(const Duration(milliseconds: 1500));
        if (!mounted || _status == _CallStatus.ended) return;
        _connectCall(profile);
      }
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

  void _connectCall(AiProfile profile) {
    if (!mounted || _status != _CallStatus.ringing) return;
    setState(() {
      _modelPending = false;
      _status = _CallStatus.connected;
    });
    _startTimer();
    _startIdleTimer();
    final greeting = buildCallGreetingPrompt(profile, _history);
    if (profile.hasSoulNexusVoice &&
        profile.voiceApiBaseUrl.isNotEmpty &&
        VoiceApiRuntime.bearerToken.isNotEmpty) {
      _realtimeConnecting = true;
      unawaited(_connectRealtime(profile, greeting));
    } else {
      unawaited(_aiTurn(greeting));
    }
  }

  Future<void> _connectRealtime(AiProfile profile, String greeting) async {
    final api = VoiceApiClient(baseUrl: profile.voiceApiBaseUrl);
    try {
      final call = await RealtimeVoiceCall.connect(
        api: api,
        cloneProfileId: profile.voiceCloneProfileId,
        systemPrompt: buildAiSystemPrompt(
          profile,
          userText: '',
          inCall: true,
          styleInHistory: _hasStyleTurns,
        ),
        initialGreeting: stripActions(profile.greeting).isEmpty
            ? '你好，我在听。'
            : stripActions(profile.greeting),
        canPlay: () => mounted && _status == _CallStatus.connected && _voiceOn,
        history: _history
            .where((entry) => entry.role == 'user' || entry.role == 'assistant')
            .toList()
            .reversed
            .take(24)
            .toList()
            .reversed
            .map((entry) => {'role': entry.role, 'content': entry.content})
            .toList(),
        onTranscript: (role, text) {
          if (!mounted ||
              _status != _CallStatus.connected ||
              text.trim().isEmpty) {
            return;
          }
          if (_history.isNotEmpty &&
              _history.last.role == role &&
              _history.last.content == text) {
            return;
          }
          if (role == 'user') {
            _resetIdleTimer();
            _actor?.hearUser(text, memories: profile.memories);
          } else {
            _actor?.hearAi(text);
          }
          _history.add((role: role, content: text));
          final caption = _Caption(role == 'user' ? 'me' : 'ai', text);
          setState(() => _captions.add(caption));
          unawaited(_saveCallCaption(caption));
          _scrollCaptionsToEnd();
        },
        onSpeaking: (speaking) {
          if (!mounted || _status != _CallStatus.connected) return;
          if (speaking && _voiceOn) {
            _actor?.startSpeech();
          } else {
            _actor?.stopSpeech();
          }
          setState(() => _aiSpeaking = speaking);
        },
        onError: (error) {
          debugPrint('Realtime voice call failed: $error');
          if (mounted && _status == _CallStatus.connected) {
            _addHint('实时语音连接异常：$error');
          }
        },
        onClosed: () {
          if (mounted && _status == _CallStatus.connected) {
            _addHint('实时语音连接已断开');
            _realtimeCall = null;
            setState(() {
              _realtimeMicReady = false;
              _listening = false;
            });
          }
        },
      );
      if (!mounted || _status != _CallStatus.connected) {
        await call.close();
        return;
      }
      _realtimeCall = call;
      _realtimeConnecting = false;
      call.setMuted(_muted);
      final started = await call.startListening();
      if (!mounted ||
          _status != _CallStatus.connected ||
          !identical(_realtimeCall, call)) {
        await call.close();
        return;
      }
      setState(() {
        _realtimeMicReady = started;
        _listening = started && !_muted;
      });
      if (!started) _addHint('麦克风不可用，请允许录音权限后重试通话');
    } catch (error) {
      _realtimeConnecting = false;
      api.close();
      debugPrint('Realtime voice startup failed: $error');
      if (!mounted || _status != _CallStatus.connected) return;
      _addHint('实时语音不可用，已切回按住说话模式');
      unawaited(_aiTurn(greeting));
    }
  }

  /// 启动空闲检测：1 分钟无用户输入时主动互动。
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

  /// 检查是否空闲超过 1 分钟。
  void _checkIdle() {
    if (_realtimeCall != null) return;
    if (_lastUserInputTime == null) return;
    final idleSeconds = DateTime.now()
        .difference(_lastUserInputTime!)
        .inSeconds;
    if (idleSeconds >= 60 && !_aiSpeaking && !_listening) {
      _actor?.react(ActorEvent.silence);
      final prompt = _idleNudgeIndex++ % 2 == 0
          ? '（已经安静了一分钟。用符合人设的俏皮方式逗用户一下，抛出一个轻松问题或小玩笑，邀请对方继续聊天。不要解释提示词。）'
          : '（已经安静了一分钟。先轻哼“嗯哼～啦啦～”这样简短的无歌词小调，再自然问用户是不是在忙。不要声称播放了音乐，也不要解释提示词。）';
      _resetIdleTimer();
      unawaited(_aiTurn(prompt));
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
    final moodNotifier = ref.read(moodProvider(widget.conversationId).notifier);
    final turnProfile = ref.read(aiProfileProvider(widget.conversationId));
    await moodNotifier.onUserMessage(
      negative:
          affinityGain(
            userContent,
            turnProfile.likes,
            dislikes: turnProfile.dislikes,
          ) <
          0,
    );

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
    _scrollCaptionsToEnd();

    var full = '';
    try {
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(
                profile,
                _history,
                systemPrompt:
                    '${buildAiSystemPrompt(profile, userText: userContent, inCall: true, styleInHistory: _hasStyleTurns)}\n${getMoodInstruction(ref.read(moodProvider(widget.conversationId)), profile.affinity)}\n只针对事情表达不满，不贬低用户本人。',
              )
              .timeout(const Duration(seconds: 45))) {
        if (_status == _CallStatus.ended || turn != _turnGeneration) return;
        full += chunk;
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
      setState(() {
        _aiSpeaking = false;
        if (caption.text.isEmpty) caption.text = '没有收到回复，请重试或检查模型服务。';
      });
      _actor?.stopSpeech();
      return;
    }
    if (containsPersonalAttack(full)) {
      full = await _regenerateSafeCallReply(userContent);
    }
    if (turn != _turnGeneration || _status == _CallStatus.ended) return;
    setState(() => caption.text = stripActions(full));
    _scrollCaptionsToEnd();
    _actor?.hearAi(full);

    // 明确要求复述/照说时允许重复；普通回复才执行静默重试。
    final cleanFull = stripActions(full).trim();
    final recentReplies = _history
        .where((h) => h.role == 'assistant')
        .map((h) => stripActions(h.content).trim())
        .toList()
        .reversed
        .take(3)
        .toList();
    if (!userRequestsExactSpeech(userContent) &&
        _isTooSimilar(cleanFull, recentReplies)) {
      if (turn != _turnGeneration || _status == _CallStatus.ended) return;
      // 清除当前字幕，重新生成
      setState(() => _captions.remove(caption));
      // 不要移除历史记录，因为用户输入已经添加了
      // 重新调用 _aiTurn，但不需要再添加用户输入
      await _retryWithDifferentContext(userContent, turn);
      return;
    }

    if (_voiceOn) _queueSpeech(full, turn);

    _history.add((role: 'assistant', content: full));
    await moodNotifier.onReply(turnProfile.affinity);
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
    try {
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      // 使用更强的防复读提示
      final enhancedPrompt =
          '${buildAiSystemPrompt(profile, userText: userContent, inCall: true, styleInHistory: _hasStyleTurns)}\n${getMoodInstruction(ref.read(moodProvider(widget.conversationId)), profile.affinity)}\n只针对事情表达不满，不贬低用户本人。\n\n【重要】不要重复你刚才说过的话，也不要复制之前的回复内容。';
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(profile, _history, systemPrompt: enhancedPrompt)) {
        if (_status == _CallStatus.ended || turn != _turnGeneration) return;
        full += chunk;
      }
    } catch (error) {
      if (turn != _turnGeneration) return;
      debugPrint('Call AI retry failed: $error');
      setState(() => caption.text = '重试失败：${LlmService.friendlyError(error)}');
    }
    if (turn != _turnGeneration || _status == _CallStatus.ended) return;
    if (full.trim().isEmpty) {
      setState(() {
        _aiSpeaking = false;
        if (caption.text.isEmpty) caption.text = '没有收到回复，请重试或检查模型服务。';
      });
      _actor?.stopSpeech();
      return;
    }
    if (containsPersonalAttack(full)) {
      full = await _regenerateSafeCallReply(userContent);
    }
    if (turn != _turnGeneration || _status == _CallStatus.ended) return;
    setState(() => caption.text = stripActions(full));
    _scrollCaptionsToEnd();
    _actor?.hearAi(full);
    if (_voiceOn) _queueSpeech(full, turn);
    _history.add((role: 'assistant', content: full));
    await ref
        .read(moodProvider(widget.conversationId).notifier)
        .onReply(ref.read(aiProfileProvider(widget.conversationId)).affinity);
    unawaited(_saveCallCaption(caption));
    await _speechQueue;
    if (mounted && turn == _turnGeneration) {
      setState(() => _aiSpeaking = false);
      _actor?.stopSpeech();
    }
  }

  Future<String> _regenerateSafeCallReply(String userContent) async {
    const fallback = '这件事让我有些失望，我想先缓一缓。';
    try {
      final profile = ref.read(aiProfileProvider(widget.conversationId));
      var rewritten = '';
      await for (final chunk
          in ref
              .read(llmServiceProvider)
              .chat(
                profile,
                _history,
                systemPrompt:
                    '${buildAiSystemPrompt(profile, userText: userContent, inCall: true, styleInHistory: _hasStyleTurns)}\n${getMoodInstruction(ref.read(moodProvider(widget.conversationId)), profile.affinity)}\n上一版回复包含人身贬低。重新回答当前问题，只针对事情表达情绪，绝不评价或辱骂用户本人。',
              )
              .timeout(const Duration(seconds: 45))) {
        rewritten += chunk;
      }
      if (rewritten.trim().isNotEmpty && !containsPersonalAttack(rewritten)) {
        return rewritten;
      }
    } catch (error) {
      debugPrint('Call safe reply regeneration failed: $error');
    }
    return fallback;
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
    if (_realtimeConnecting) {
      _addHint('实时语音连接中，请稍后再说');
      return;
    }
    if (_aiSpeaking) await _interruptAiSpeech();
    if (!_pressHeld || !mounted || _status != _CallStatus.connected) return;
    _actor?.react(ActorEvent.userSpeech);
    if (_realtimeCall case final call?) {
      final started = await call.startListening();
      if (!_pressHeld || !mounted || _status != _CallStatus.connected) {
        if (started) await call.stopListening();
        return;
      }
      if (!started) {
        _addHint('麦克风不可用，请检查录音权限');
        return;
      }
      setState(() {
        _listening = true;
        _partial = '';
      });
      return;
    }
    if (!_sttReady) _sttReady = await _stt.init();
    if (!_pressHeld || !mounted || _status != _CallStatus.connected) return;
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
    if (!_pressHeld) await _stopListening();
  }

  Future<void> _stopListening() async {
    if (!_listening) return;
    if (_realtimeCall case final call?) {
      await call.stopListening();
      if (mounted) setState(() => _listening = false);
      return;
    }
    await _stt.stop();
    if (!mounted || _status != _CallStatus.connected) return;
    setState(() => _listening = false);
    final text = _stt.lastResult.isNotEmpty ? _stt.lastResult : _partial;
    if (text.trim().isEmpty) return;
    _runCommand(text);
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
    if (_realtimeCall case final call?) await call.abortSpeech();
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
                  (position.inMicroseconds / duration.inMicroseconds).clamp(
                    0.0,
                    1.0,
                  );
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
    if (_realtimeConnecting || _realtimeCall != null) {
      _addHint('实时语音通话请使用麦克风；文字消息可在聊天页发送');
      return;
    }
    _runCommand(text);
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

  void _runCommand(String text) {
    if (_status != _CallStatus.connected) return;
    if (!_hasAnimatedModel) {
      if (mounted) setState(() => _commandFeedback = '动作不可用');
      return;
    }
    final action = VirtualActor.parseAction(text);
    final model = ref
        .read(aiProfileProvider(widget.conversationId))
        .live2dModel!;
    final custom = action == ActorAction.stop ? null : model.matchAction(text);
    if (action == null && custom == null) {
      if (_commandFeedback != null) setState(() => _commandFeedback = null);
      return;
    }
    String? error;
    if (custom != null) {
      if (!(_actor?.requestCustomAction(custom) ?? false)) error = '角色动画未启用';
    } else if (action == null) {
      error = '未识别的动作指令';
    } else if (!supportsModelAction(
      ref
          .read(aiProfileProvider(widget.conversationId))
          .live2dModel!
          .parameterIds,
      action,
    )) {
      error = '当前模型不支持此动作';
    } else if (!(_actor?.requestAction(action) ?? false)) {
      error = '角色动画未启用';
    }
    _resetIdleTimer();
    setState(
      () => _commandFeedback =
          error ?? (action == ActorAction.stop ? '动作已停止' : '已接收：$text'),
    );
  }

  Widget _commandControls() => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _inputArea(),
            if (_commandFeedback != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _commandFeedback!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
          ],
        ),
      ),
    ),
  );

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
    unawaited(_shutdownCall());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        context.go('/chat/${widget.conversationId}');
      } catch (error) {
        debugPrint('Call route cleanup failed: $error');
      }
    });
  }

  Future<void> _shutdownCall() => _shutdown ??= _releaseCall();

  Future<void> _releaseCall() async {
    try {
      await _realtimeCall?.close();
      _realtimeCall = null;
      await _tts.stop();
      await _voice.dispose();
      if (_sttReady) await _stt.cancel();
    } catch (error) {
      debugPrint('Call cleanup failed: $error');
    }
    try {
      await _camera?.dispose();
    } catch (error) {
      debugPrint('Call camera cleanup failed: $error');
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onFrameTimings);
    _timer?.cancel();
    _idleTimer?.cancel();
    _status = _CallStatus.ended;
    _speechGeneration++;
    _turnGeneration++;
    _actor?.stopSpeech();
    _actor?.dispose();
    _inputController.dispose();
    _captionScrollController.dispose();
    unawaited(_shutdownCall());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(resolvedConversationListProvider);
    final profile = ref.watch(aiProfileProvider(widget.conversationId));
    final performance = ref.watch(callPerformanceProvider);
    ref.listen(callPerformanceProvider, (previous, next) {
      if (_modelPending && !next.rendersModel) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _connectCall(profile),
        );
      }
    });
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxHeight < 420;
            return Column(
              children: [
                Expanded(
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (widget.isVideo &&
                          (_modelPending || _status == _CallStatus.connected))
                        _remoteVideo(contact, name),
                      if (!widget.isVideo && _status == _CallStatus.connected)
                        _voiceMain(contact, name),
                      if (_status == _CallStatus.ringing)
                        ColoredBox(
                          color: const Color(0xFF1F1F1F),
                          child: CallWaitingView(
                            contact: contact,
                            name: name,
                            isVideo: widget.isVideo,
                            animationsEnabled:
                                performance.animationsEnabled &&
                                profile.expressionProfile.animationEnabled,
                            reducedEffects: performance.reducedEffects,
                          ),
                        ),
                      if (widget.isVideo &&
                          _status == _CallStatus.connected &&
                          _cameraOn)
                        Positioned(
                          top: 12,
                          right: 14,
                          child: Transform.scale(
                            scale: compact ? 0.65 : 1,
                            alignment: Alignment.topRight,
                            child: _selfPreview(),
                          ),
                        ),
                    ],
                  ),
                ),
                ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight:
                        constraints.maxHeight *
                        (_status == _CallStatus.ringing
                            ? 0.3
                            : (constraints.maxHeight < 300
                                  ? 1
                                  : (compact ? 0.68 : 0.6))),
                  ),
                  child: Padding(
                    padding: EdgeInsets.only(top: 8, bottom: compact ? 8 : 20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_status == _CallStatus.connected)
                          Flexible(
                            child: _showCaptions
                                ? _captionList()
                                : SingleChildScrollView(
                                    child: _latestCaption(),
                                  ),
                          ),
                        _controls(),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
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
          if (contact != null &&
              _actor != null &&
              (_status == _CallStatus.connected || _modelPending) &&
              _live2dOn &&
              _hasAnimatedModel)
            Live2DActor(
              key: ValueKey(profile.live2dModel!.directory),
              contact: contact,
              actor: _actor!,
              profile: profile,
              onReady: () => _connectCall(profile),
              onInteraction: _resetIdleTimer,
              onUnavailable: () {
                if (!mounted) return;
                setState(() => _live2dOn = false);
                if (_modelPending) _connectCall(profile);
              },
            )
          else if (contact != null)
            Center(
              child: CallAvatar(
                contact: contact,
                animationsEnabled:
                    ref.read(callPerformanceProvider).animationsEnabled &&
                    profile.expressionProfile.animationEnabled,
                reducedEffects: ref
                    .read(callPerformanceProvider)
                    .reducedEffects,
              ),
            ),
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
      260.0,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      child: Center(
        child: Container(
          width: double.infinity,
          constraints: BoxConstraints(maxWidth: 440, maxHeight: height),
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
          constraints: const BoxConstraints(maxWidth: 380),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(6),
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
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isAi ? Colors.white : Colors.white70,
                    fontSize: 14,
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
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_hasAnimatedModel) _commandControls(),
        // AI 视频/语音通话都保留实时麦克风输入；动作输入仍在模型区上方显示。
        if (_isAi && !_hasAnimatedModel) _inputArea(),
        const SizedBox(height: 16),
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
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
                    _realtimeCall?.setMuted(_muted);
                    if (_realtimeCall != null) {
                      setState(() => _listening = _realtimeMicReady && !_muted);
                    }
                    _actor?.react(_muted ? ActorEvent.mute : ActorEvent.unmute);
                  },
                ),
                _controlButton(
                  icon: _showCaptions
                      ? Icons.subtitles
                      : Icons.subtitles_outlined,
                  label: '字幕',
                  active: _showCaptions,
                  onTap: _toggleCaptions,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// 输入区：按住说话（默认）或文字输入（豆包式切换）
  Widget _inputArea() => Align(
    alignment: Alignment.center,
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 440),
      child: _inputField(),
    ),
  );

  Widget _inputField() => _realtimeCall != null || _realtimeConnecting
      ? Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          height: 48,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF353535),
            borderRadius: BorderRadius.circular(28),
          ),
          child: Text(
            _realtimeConnecting
                ? '正在连接实时语音…'
                : !_realtimeMicReady
                ? '麦克风不可用，请检查录音权限'
                : _muted
                ? '麦克风已静音'
                : '正在聆听 · 直接说话',
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        )
      : Container(
          margin: const EdgeInsets.symmetric(horizontal: 8),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: const Color(0xFF353535),
            borderRadius: BorderRadius.circular(28),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                visualDensity: VisualDensity.standard,
                constraints: const BoxConstraints.tightFor(
                  width: 48,
                  height: 48,
                ),
                tooltip: _showInput ? '切换语音输入' : '切换文字输入',
                icon: Icon(
                  _showInput ? Icons.mic : Icons.keyboard,
                  color: Colors.white70,
                ),
                onPressed: () {
                  FocusScope.of(context).unfocus();
                  setState(() => _showInput = !_showInput);
                },
              ),
              const SizedBox(width: 4),
              Expanded(
                child: _showInput
                    ? Container(
                        decoration: BoxDecoration(
                          color: Colors.transparent,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: TextField(
                          controller: _inputController,
                          minLines: 1,
                          maxLines: 3,
                          style: const TextStyle(
                            fontSize: 14,
                            color: Colors.white,
                          ),
                          cursorColor: const Color(0xFF47A8FF),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) => _sendTyped(),
                          decoration: const InputDecoration(
                            isDense: true,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            hintText: '聊点什么…',
                            hintStyle: TextStyle(color: Colors.white54),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                          ),
                        ),
                      )
                    : GestureDetector(
                        onLongPressStart: (_) {
                          _pressHeld = true;
                          unawaited(_startListening());
                        },
                        onLongPressEnd: (_) {
                          _pressHeld = false;
                          unawaited(_stopListening());
                        },
                        child: Container(
                          height: 44,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: _listening
                                ? Colors.white
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(20),
                          ),
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
              if (_showInput)
                IconButton(
                  visualDensity: VisualDensity.standard,
                  constraints: const BoxConstraints.tightFor(
                    width: 48,
                    height: 48,
                  ),
                  tooltip: '发送',
                  icon: const CircleAvatar(
                    radius: 18,
                    backgroundColor: Color(0xFF168BFF),
                    child: Icon(
                      Icons.arrow_upward,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  onPressed: _sendTyped,
                )
              else
                const SizedBox(width: 48),
            ],
          ),
        );

  Widget _hangupButton() {
    final size = MediaQuery.sizeOf(context).width < 360 ? 52.0 : 64.0;
    return GestureDetector(
      onTap: _ending ? null : _end,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
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
    final size = MediaQuery.sizeOf(context).width < 360 ? 48.0 : 60.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: size,
            height: size,
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
