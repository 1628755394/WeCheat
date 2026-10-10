import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';

class VoiceApiRuntime {
  static String bearerToken = '';
}

class VoiceCloneProfile {
  final String id;
  final String name;
  final String status;
  final String speakerId;
  final String assetId;
  final String resourceId;
  final String failedReason;
  final double progress;

  const VoiceCloneProfile({
    required this.id,
    required this.name,
    required this.status,
    this.speakerId = '',
    this.assetId = '',
    this.resourceId = '',
    this.failedReason = '',
    this.progress = 0,
  });

  factory VoiceCloneProfile.fromMap(Map map) => VoiceCloneProfile(
    id: (map['id'] as String?) ?? '',
    name: (map['name'] as String?) ?? '',
    status: (map['status'] as String?) ?? '',
    speakerId: (map['speakerId'] as String?) ?? '',
    assetId: (map['assetId'] as String?) ?? '',
    resourceId: (map['resourceId'] as String?) ?? '',
    failedReason: (map['failedReason'] as String?) ?? '',
    progress: (map['progress'] as num?)?.toDouble() ?? 0,
  );
}

class VoiceCloneResourceOption {
  final String id;
  final String label;

  const VoiceCloneResourceOption({required this.id, required this.label});

  factory VoiceCloneResourceOption.fromMap(Map map) => VoiceCloneResourceOption(
    id: (map['id'] as String?) ?? '',
    label: (map['label'] as String?) ?? '',
  );
}

class VoiceSessionInfo {
  final String id;
  final String path;
  final String ticket;
  final int sampleRate;

  const VoiceSessionInfo({
    required this.id,
    required this.path,
    required this.ticket,
    required this.sampleRate,
  });

  factory VoiceSessionInfo.fromMap(Map map) => VoiceSessionInfo(
    id: (map['sessionId'] as String?) ?? '',
    path: (map['webSocketPath'] as String?) ?? '/api/v1/voice-sessions/ws',
    ticket: (map['webSocketTicket'] as String?) ?? '',
    sampleRate: (map['sampleRateHz'] as num?)?.toInt() ?? 16000,
  );
}

class VoiceApiClient {
  VoiceApiClient({required this.baseUrl, String? token})
    : token = token ?? VoiceApiRuntime.bearerToken;

  final String baseUrl;
  final String token;
  final http.Client _http = http.Client();

  Uri _uri(String path) {
    final base = Uri.parse(baseUrl.trim());
    final prefix = base.path.replaceFirst(RegExp(r'/+$'), '');
    final apiRoot = prefix.endsWith('/api/v1')
        ? prefix
        : prefix.endsWith('/api')
        ? '$prefix/v1'
        : '$prefix/api/v1';
    final suffix = path.startsWith('/api/v1') ? path.substring(7) : path;
    return base.replace(path: '$apiRoot$suffix', query: null, fragment: null);
  }

  Map<String, String> get _headers => {
    'Authorization': 'Bearer $token',
    'Content-Type': 'application/json',
  };

  Future<Map<String, dynamic>> loadConfig() =>
      _request('GET', '/voice-clones/config');

  Future<List<VoiceCloneProfile>> listClones({String? status}) async {
    final query = status == null
        ? ''
        : '?status=${Uri.encodeQueryComponent(status)}';
    final data = await _request('GET', '/voice-clones$query');
    final rows = data['data'] as List? ?? const [];
    return [
      for (final row in rows)
        if (row is Map) VoiceCloneProfile.fromMap(row),
    ];
  }

  Future<List<VoiceCloneProfile>> listReadyClones() =>
      listClones(status: 'success');

  Future<void> deleteClone(String profileId) async {
    await _request('DELETE', '/voice-clones/${Uri.encodeComponent(profileId)}');
  }

  Future<VoiceCloneProfile> createClone({
    required String name,
    required String speakerId,
    String resourceId = 'seed-icl-2.0',
    String language = 'zh',
    String trainText = '',
  }) async {
    final data = await _request(
      'POST',
      '/voice-clones',
      body: {
        'name': name,
        'speakerId': speakerId,
        'resourceId': resourceId,
        'language': language,
        'trainText': trainText,
      },
    );
    return VoiceCloneProfile.fromMap(data['data'] as Map);
  }

  Future<VoiceCloneProfile> updateCloneResource(
    String profileId,
    String resourceId,
  ) async {
    final data = await _request(
      'POST',
      '/voice-clones/${Uri.encodeComponent(profileId)}/resource',
      body: {'resourceId': resourceId},
    );
    return VoiceCloneProfile.fromMap(data['data'] as Map);
  }

  Future<VoiceCloneProfile> uploadTrainingAudio(
    String profileId,
    String fileName,
    Uint8List bytes,
  ) async {
    final request =
        http.MultipartRequest(
            'POST',
            _uri('/voice-clones/${Uri.encodeComponent(profileId)}/audio'),
          )
          ..headers['Authorization'] = 'Bearer $token'
          ..files.add(
            http.MultipartFile.fromBytes('file', bytes, filename: fileName),
          );
    final response = await request.send().timeout(const Duration(minutes: 2));
    final body = await response.stream.bytesToString();
    final decoded = jsonDecode(body) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceApiException(_message(decoded, '音频上传失败'));
    }
    return VoiceCloneProfile.fromMap(decoded['data'] as Map);
  }

  Future<VoiceCloneProfile> syncClone(String profileId) async {
    final data = await _request(
      'POST',
      '/voice-clones/${Uri.encodeComponent(profileId)}/sync',
      body: const {},
    );
    return VoiceCloneProfile.fromMap(data['data'] as Map);
  }

  Future<Uint8List> synthesizeVoice(String profileId, String text) async {
    final data = await _request(
      'POST',
      '/voice-clones/${Uri.encodeComponent(profileId)}/synthesize',
      body: {'text': text},
    );
    final result = data['data'] as Map;
    final pcm = base64Decode(result['pcmBase64'] as String);
    final rate = (result['sampleRate'] as num?)?.toInt() ?? 16000;
    return pcm16ToWav(Uint8List.fromList(pcm), rate);
  }

  Future<VoiceSessionInfo> createVoiceSession({
    required String cloneProfileId,
    required String systemPrompt,
    required String initialGreeting,
    required List<Map<String, String>> history,
  }) async {
    final data = await _request(
      'POST',
      '/voice-sessions',
      body: {
        'cloneProfileId': cloneProfileId,
        'systemPrompt': systemPrompt,
        'initialGreeting': initialGreeting,
        'history': history,
      },
    );
    return VoiceSessionInfo.fromMap(data['data'] as Map);
  }

  WebSocketChannel connectVoiceSession(VoiceSessionInfo session) {
    final api = _uri(session.path);
    final scheme = api.scheme == 'https' ? 'wss' : 'ws';
    final uri = api.replace(
      scheme: scheme,
      queryParameters: {'session_id': session.id, 'ticket': session.ticket},
    );
    return WebSocketChannel.connect(uri);
  }

  Future<void> endVoiceSession(String sessionId) async {
    await _request(
      'DELETE',
      '/voice-sessions/${Uri.encodeComponent(sessionId)}',
    );
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = _uri(path);
    final request = http.Request(method, uri)..headers.addAll(_headers);
    if (body != null) request.body = jsonEncode(body);
    late final http.StreamedResponse response;
    try {
      response = await _http.send(request).timeout(const Duration(seconds: 30));
    } on Exception catch (error) {
      throw VoiceApiException(_friendlyNetworkError(error));
    }
    final text = await response.stream.bytesToString();
    final decoded = text.trim().isEmpty
        ? <String, dynamic>{}
        : jsonDecode(text) as Map<String, dynamic>;
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw VoiceApiException(_message(decoded, '语音服务请求失败'));
    }
    return decoded;
  }

  String _friendlyNetworkError(Object error) {
    final text = error.toString().toLowerCase();
    if (text.contains('connection refused') || text.contains('errno = 1225')) {
      return '音色服务未启动（请启动 127.0.0.1:7072），当前将回退系统语音';
    }
    if (text.contains('timed out')) return '音色服务连接超时，当前将回退系统语音';
    return '音色服务连接失败，当前将回退系统语音';
  }

  String _message(Map<String, dynamic> response, String fallback) {
    final message = response['msg'];
    return message is String && message.isNotEmpty ? message : fallback;
  }

  void close() => _http.close();
}

class VoiceApiException implements Exception {
  const VoiceApiException(this.message);

  final String message;

  @override
  String toString() => message;
}

Uint8List pcm16ToWav(Uint8List pcm, int sampleRate) {
  final wav = Uint8List(44 + pcm.length);
  final data = ByteData.sublistView(wav);
  wav.setRange(0, 4, ascii.encode('RIFF'));
  data.setUint32(4, wav.length - 8, Endian.little);
  wav.setRange(8, 12, ascii.encode('WAVE'));
  wav.setRange(12, 16, ascii.encode('fmt '));
  data.setUint32(16, 16, Endian.little);
  data.setUint16(20, 1, Endian.little);
  data.setUint16(22, 1, Endian.little);
  data.setUint32(24, sampleRate, Endian.little);
  data.setUint32(28, sampleRate * 2, Endian.little);
  data.setUint16(32, 2, Endian.little);
  data.setUint16(34, 16, Endian.little);
  wav.setRange(36, 40, ascii.encode('data'));
  data.setUint32(40, pcm.length, Endian.little);
  wav.setRange(44, wav.length, pcm);
  return wav;
}
