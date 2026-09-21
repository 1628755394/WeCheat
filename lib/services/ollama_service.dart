import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 本地 Ollama 服务：直连 127.0.0.1:11434，无后端中转
class OllamaService {
  static const _endpoint = 'http://127.0.0.1:11434/api/chat';
  static const model = 'qwen2.5:7b';

  static const _systemPrompt =
      '你是微信里的 AI 助手，用简洁的中文回答用户的问题。';

  final _client = http.Client();

  /// 流式聊天：传入完整上下文，逐段吐出 AI 生成的文本
  /// systemPrompt 可覆盖默认提示词（角色卡/知识库由调用方组装）
  Stream<String> chat(List<({String role, String content})> history,
      {String? systemPrompt}) async* {
    final request = http.Request('POST', Uri.parse(_endpoint))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'messages': [
          {'role': 'system', 'content': systemPrompt ?? _systemPrompt},
          for (final m in history) {'role': m.role, 'content': m.content},
        ],
      });

    final response =
        await _client.send(request).timeout(const Duration(seconds: 60));
    if (response.statusCode != 200) {
      throw Exception('Ollama 返回 ${response.statusCode}');
    }

    // NDJSON：每行一个 JSON，message.content 为增量文本，done=true 结束
    var buffer = '';
    await for (final chunk in response.stream.transform(utf8.decoder)) {
      buffer += chunk;
      var idx = buffer.indexOf('\n');
      while (idx >= 0) {
        final line = buffer.substring(0, idx).trim();
        buffer = buffer.substring(idx + 1);
        idx = buffer.indexOf('\n');
        if (line.isEmpty) continue;
        final json = jsonDecode(line) as Map<String, dynamic>;
        final content = (json['message'] as Map?)?['content'];
        if (content is String && content.isNotEmpty) yield content;
        if (json['done'] == true) return;
      }
    }
  }
}
