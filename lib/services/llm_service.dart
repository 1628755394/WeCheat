import '../models/ai_profile.dart';
import 'ollama_service.dart';
import 'remote_llm_service.dart';

/// 大模型调用网关：按 AI 资料的 provider 分发到本地 Ollama 或远程接口
class LlmService {
  final OllamaService _ollama;
  final RemoteLlmService _remote;

  LlmService(this._ollama, this._remote);

  Stream<String> chat(
    AiProfile profile,
    List<({String role, String content})> history, {
    String? systemPrompt,
  }) async* {
    final source = _chat(profile, history, systemPrompt: systemPrompt);
    var receivedText = false;
    await for (final chunk in source.timeout(const Duration(seconds: 45))) {
      if (chunk.trim().isNotEmpty) receivedText = true;
      yield chunk;
    }
    if (!receivedText) throw StateError('模型未返回文字内容，请重试或更换模型。');
  }

  Stream<String> _chat(
    AiProfile profile,
    List<({String role, String content})> history, {
    String? systemPrompt,
  }) {
    if (profile.isRemote) {
      // 旧配置兼容：gpt/codex 系模型一律走 Responses API
      // （cc-switch 里部分 Codex 渠道 appType 标的是 claude，实际不支持 /messages）
      var protocol = profile.provider;
      if (protocol != 'responses' &&
          RegExp(r'^(gpt|codex|o\d)').hasMatch(profile.model)) {
        protocol = 'responses';
      }
      return _remoteWithLocalFallback(
        profile,
        history,
        protocol: protocol,
        systemPrompt: systemPrompt,
      );
    }
    return _ollama.chat(
      history,
      systemPrompt: systemPrompt,
      model: profile.model,
    );
  }

  Stream<String> _remoteWithLocalFallback(
    AiProfile profile,
    List<({String role, String content})> history, {
    required String protocol,
    String? systemPrompt,
  }) async* {
    try {
      yield* _remote.chat(
        history,
        protocol: protocol,
        baseUrl: profile.baseUrl,
        apiKey: profile.apiKey,
        model: profile.model,
        systemPrompt: systemPrompt,
      );
    } catch (error) {
      // Expired/invalid remote keys should not make the chat unusable when
      // the local Ollama service is available.
      if (!_isRecoverableRemoteError(error)) rethrow;
      yield* _ollama.chat(history, systemPrompt: systemPrompt, model: '');
    }
  }

  static bool _isRecoverableRemoteError(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('401') ||
        text.contains('403') ||
        text.contains('api key') ||
        text.contains('expired') ||
        text.contains('unauthorized') ||
        text.contains('forbidden');
  }

  static String friendlyError(Object error) {
    final text = error.toString();
    final lower = text.toLowerCase();
    if (lower.contains('api key') ||
        lower.contains('expired') ||
        lower.contains('接口返回 401') ||
        lower.contains('接口返回 403')) {
      return '远程模型 API Key 已过期或无效，请在 AI 设置中更新密钥，或切换到本地 Ollama。';
    }
    if (lower.contains('connection refused') ||
        lower.contains('errno = 1225')) {
      return '服务未启动，请检查本地 Ollama 或音色服务。';
    }
    return text.length > 160 ? '${text.substring(0, 160)}…' : text;
  }
}
