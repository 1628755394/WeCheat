import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/services/voice_api_client.dart';

void main() {
  test('voice session URL uses the server path once', () {
    final client = VoiceApiClient(baseUrl: 'http://192.168.3.15:7072');
    final uri = client.voiceSessionUri(
      const VoiceSessionInfo(
        id: 'session-1',
        path: '/api/v1/voice-sessions/ws',
        ticket: 'one-time-ticket',
        sampleRate: 16000,
      ),
    );

    expect(uri.scheme, 'ws');
    expect(uri.path, '/api/v1/voice-sessions/ws');
    expect(uri.queryParameters['session_id'], 'session-1');
    expect(uri.queryParameters['ticket'], 'one-time-ticket');
    client.close();
  });

  test('SoulNexus voice binding survives profile serialization', () {
    final profile = AiProfile(
      voiceApiBaseUrl: 'http://192.168.1.20:7072',
      voiceCloneProfileId: 'clone-123',
    );

    final restored = AiProfile.fromMap(profile.toMap());

    expect(restored.voiceApiBaseUrl, profile.voiceApiBaseUrl);
    expect(restored.voiceCloneProfileId, profile.voiceCloneProfileId);
    expect(restored.hasSoulNexusVoice, isTrue);
  });

  test('clone profile exposes the selected Volcengine resource', () {
    final clone = VoiceCloneProfile.fromMap({
      'id': 'clone-1',
      'name': '宝青坊主',
      'status': 'pending',
      'speakerId': 'S_test',
      'resourceId': 'seed-icl-1.0',
    });

    expect(clone.resourceId, 'seed-icl-1.0');
  });

  test(
    'PCM16 audio is wrapped as a mono WAV at the negotiated sample rate',
    () {
      final wav = pcm16ToWav(Uint8List.fromList([1, 0, 2, 0]), 16000);

      expect(wav.length, 48);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(wav[24], 0x80);
      expect(wav[25], 0x3e);
      expect(wav.sublist(44), [1, 0, 2, 0]);
    },
  );
}
