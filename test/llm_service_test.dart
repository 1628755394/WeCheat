import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/services/llm_service.dart';
import 'package:wecheat/services/ollama_service.dart';
import 'package:wecheat/services/remote_llm_service.dart';

class _RemoteSpy extends RemoteLlmService {
  String? receivedProtocol;
  @override
  Stream<String> chat(
    List<({String role, String content})> history, {
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
    String? systemPrompt,
  }) async* {
    receivedProtocol = protocol;
    yield 'remote reply';
  }
}

void main() {
  test('expired remote key gets a clear actionable error', () {
    expect(
      LlmService.friendlyError(Exception('接口返回 403: {"error":"API Key 已过期"}')),
      contains('API Key 已过期或无效'),
    );
  });

  test('local connection errors explain which service to start', () {
    expect(
      LlmService.friendlyError(
        Exception('Connection refused (OS Error: errno = 1225)'),
      ),
      contains('服务未启动'),
    );
  });

  test('Codex Responses profiles route to the remote service', () async {
    final profile = const AiProfile(
      provider: 'responses',
      baseUrl: 'https://example.invalid/v1',
      apiKey: 'expired',
      model: 'gpt-test',
    );
    expect(profile.isRemote, isTrue);
    final remote = _RemoteSpy();
    final reply = await LlmService(
      OllamaService(),
      remote,
    ).chat(profile, const [(role: 'user', content: 'hello')]).toList();
    expect(reply, ['remote reply']);
    expect(remote.receivedProtocol, 'responses');
  });
}
