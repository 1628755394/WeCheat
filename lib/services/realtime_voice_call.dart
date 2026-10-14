import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'voice_api_client.dart';
import 'voice_service.dart';

/// Owns one SoulNexus session, microphone stream and received PCM playback.
class RealtimeVoiceCall {
  RealtimeVoiceCall._(
    this._api,
    this._session,
    this._socket, {
    required this.onTranscript,
    required this.onSpeaking,
    required this.onError,
    required this.onClosed,
    required this.canPlay,
  });

  final VoiceApiClient _api;
  final VoiceSessionInfo _session;
  final WebSocketChannel _socket;
  final void Function(String role, String text) onTranscript;
  final void Function(bool speaking) onSpeaking;
  final void Function(Object error) onError;
  final VoidCallback onClosed;
  final bool Function() canPlay;
  final AudioRecorder _recorder = AudioRecorder();
  final VoiceService _player = VoiceService();
  StreamSubscription<dynamic>? _socketSubscription;
  StreamSubscription<Uint8List>? _micSubscription;
  BytesBuilder? _incomingAudio;
  Future<void> _playback = Future<void>.value();
  bool _closed = false;
  bool _recording = false;
  bool _muted = false;
  int _playbackGeneration = 0;

  static Future<RealtimeVoiceCall> connect({
    required VoiceApiClient api,
    required String cloneProfileId,
    required String systemPrompt,
    required String initialGreeting,
    required List<Map<String, String>> history,
    required void Function(String role, String text) onTranscript,
    required void Function(bool speaking) onSpeaking,
    required void Function(Object error) onError,
    required VoidCallback onClosed,
    required bool Function() canPlay,
  }) async {
    final session = await api.createVoiceSession(
      cloneProfileId: cloneProfileId,
      systemPrompt: systemPrompt,
      initialGreeting: initialGreeting,
      history: history,
    );
    final socket = api.connectVoiceSession(session);
    final call = RealtimeVoiceCall._(
      api,
      session,
      socket,
      onTranscript: onTranscript,
      onSpeaking: onSpeaking,
      onError: onError,
      onClosed: onClosed,
      canPlay: canPlay,
    );
    call._socketSubscription = socket.stream.listen(
      call._receive,
      onError: call._socketError,
      onDone: call._socketClosed,
    );
    try {
      await socket.ready.timeout(const Duration(seconds: 10));
      return call;
    } catch (_) {
      await call.close();
      rethrow;
    }
  }

  void _receive(dynamic event) {
    if (_closed) return;
    if (event is List<int>) {
      _incomingAudio?.add(event);
      return;
    }
    if (event is! String) return;
    try {
      final frame = jsonDecode(event);
      if (frame is! Map) return;
      switch (frame['type']) {
        case 'transcript.user':
          if (frame['final'] == true && frame['text'] is String) {
            onTranscript('user', frame['text'] as String);
          }
          return;
        case 'transcript.assistant':
          if (frame['final'] == true && frame['text'] is String) {
            onTranscript('assistant', frame['text'] as String);
          }
          return;
        case 'tts':
          if (frame['state'] == 'start') {
            _incomingAudio = BytesBuilder(copy: false);
            onSpeaking(true);
          } else if (frame['state'] == 'stop') {
            final bytes = _incomingAudio?.takeBytes();
            _incomingAudio = null;
            if (bytes != null && bytes.isNotEmpty && canPlay()) {
              final generation = _playbackGeneration;
              _playback = _playback.then((_) async {
                if (_closed || generation != _playbackGeneration) return;
                await _player.playAndWait(
                  pcm16ToWav(bytes, _session.sampleRate),
                  mimeType: 'audio/wav',
                );
                if (!_closed && generation == _playbackGeneration) {
                  onSpeaking(false);
                }
              });
            } else {
              onSpeaking(false);
            }
          }
          return;
        case 'error':
          onError(frame['message'] ?? '语音会话出错');
          return;
      }
    } catch (error) {
      onError(error);
    }
  }

  void _socketError(Object error) {
    if (!_closed) onError(error);
    _socketClosed();
  }

  void _socketClosed() {
    if (_closed) return;
    onClosed();
    unawaited(close());
  }

  Future<bool> startListening() async {
    if (_closed || _recording) return false;
    try {
      if (!await _recorder.hasPermission()) return false;
      final mic = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
          autoGain: true,
          echoCancel: true,
          noiseSuppress: true,
          androidConfig: AndroidRecordConfig(
            audioSource: AndroidAudioSource.voiceCommunication,
            audioManagerMode: AudioManagerMode.modeInCommunication,
            speakerphone: true,
          ),
        ),
      );
      if (_closed) {
        await _recorder.stop();
        return false;
      }
      _recording = true;
      _send({'type': 'listen', 'state': 'start'});
      _micSubscription = mic.listen((bytes) {
        if (!_closed && _recording && bytes.isNotEmpty) {
          _socket.sink.add(_muted ? Uint8List(bytes.length) : bytes);
        }
      }, onError: onError);
      return true;
    } catch (error) {
      onError(error);
      return false;
    }
  }

  void setMuted(bool value) => _muted = value;

  Future<void> stopListening({bool finalize = true}) async {
    if (!_recording) return;
    _recording = false;
    await _micSubscription?.cancel();
    _micSubscription = null;
    await _recorder.stop();
    if (finalize) _send({'type': 'listen', 'state': 'stop'});
  }

  Future<void> abortSpeech() async {
    _playbackGeneration++;
    _incomingAudio = null;
    await _player.stop();
    _send({'type': 'abort'});
    if (!_closed) onSpeaking(false);
  }

  void _send(Map<String, String> frame) {
    if (!_closed) _socket.sink.add(jsonEncode(frame));
  }

  Future<void> close() async {
    if (_closed) return;
    await stopListening();
    _send({'type': 'hangup'});
    _closed = true;
    _playbackGeneration++;
    await _socketSubscription?.cancel();
    await _socket.sink.close();
    await _recorder.dispose();
    await _player.dispose();
    try {
      await _api.endVoiceSession(_session.id);
    } catch (error) {
      debugPrint('End voice session failed: $error');
    }
    _api.close();
  }
}
