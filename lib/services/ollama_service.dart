import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// 本地 Ollama 服务：直连 127.0.0.1:11434，无后端中转
class OllamaService {
  static const _endpoint = 'http://127.0.0.1:11434/api/chat';
  static const _tagsEndpoint = 'http://127.0.0.1:11434/api/tags';
  static const defaultModel = 'qwen3:8b';

  static const _systemPrompt = '你是微信里的 AI 助手，用简洁的中文回答用户的问题。';

  final _client = http.Client();

  /// 列出本机已安装的模型名
  Future<List<String>> listModels() async {
    final response = await _client
        .get(Uri.parse(_tagsEndpoint))
        .timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) return const [];
    final json = jsonDecode(response.body) as Map<String, dynamic>;
    return [
      for (final m in (json['models'] as List? ?? []))
        (m as Map)['name'] as String,
    ];
  }

  Future<http.StreamedResponse> _send(
    String model,
    List<({String role, String content})> history,
    String? systemPrompt,
  ) {
    final request = http.Request('POST', Uri.parse(_endpoint))
      ..headers['Content-Type'] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        // qwen3 的思维链在 think:true 时走独立的 message.thinking 字段，
        // content 保持干净；think:false 在此版本反而把思维链混进 content
        'think': true,
        // 小模型容易抓人设关键词反复复读：重复惩罚 + 收敛采样压一压
        'options': {
          'temperature': 0.7,
          'top_p': 0.9,
          'repeat_penalty': 1.15,
          // 鼓励引入新话题/新措辞，抑制整段复读上一轮
          'presence_penalty': 0.5,
        },
        'messages': [
          {'role': 'system', 'content': systemPrompt ?? _systemPrompt},
          for (final m in history) {'role': m.role, 'content': m.content},
        ],
      });
    return _client.send(request).timeout(const Duration(seconds: 30));
  }

  /// 流式聊天：传入完整上下文，逐段吐出 AI 生成的文本
  /// systemPrompt/model 可覆盖默认值（角色卡/知识库/模型由调用方指定）
  /// 所选模型已被卸载（404）时自动回落 defaultModel，避免历史配置失效
  Stream<String> chat(
    List<({String role, String content})> history, {
    String? systemPrompt,
    String? model,
  }) async* {
    var useModel = (model == null || model.isEmpty) ? defaultModel : model;
    var response = await _send(useModel, history, systemPrompt);
    if (response.statusCode != 200 && useModel != defaultModel) {
      await response.stream.drain();
      useModel = defaultModel;
      response = await _send(useModel, history, systemPrompt);
    }
    if (response.statusCode != 200) {
      await response.stream.drain();
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
