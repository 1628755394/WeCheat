import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'web_client_stub.dart'
    if (dart.library.js_interop) 'web_client_web.dart';

/// 远程大模型服务：Anthropic Messages / OpenAI 兼容接口，SSE 流式
/// 供 cc-switch 服务商与手动填写的密钥使用
class RemoteLlmService {
  /// protocol: 'anthropic'（/v1/messages）或 'openai'（/v1/chat/completions）
  Stream<String> chat(
    List<({String role, String content})> history, {
    required String protocol,
    required String baseUrl,
    required String apiKey,
    required String model,
    String? systemPrompt,
  }) {
    return switch (protocol) {
      'anthropic' => _anthropic(history, baseUrl, apiKey, model, systemPrompt),
      'responses' => _responses(history, baseUrl, apiKey, model, systemPrompt),
      _ => _openai(history, baseUrl, apiKey, model, systemPrompt),
    };
  }

  /// Claude Code 风格地址处理：base 已含 /v1 则直接接 /messages
  String _anthropicUrl(String base) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return b.endsWith('/v1') ? '$b/messages' : '$b/v1/messages';
  }

  String _openaiUrl(String base) {
    final b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    return b.endsWith('/v1')
        ? '$b/chat/completions'
        : '$b/v1/chat/completions';
  }

  /// Responses API 地址：base 含 /v1 直接接；/anthropic、/claude 这类渠道
  /// 前缀段剥掉（Responses 端点在根 /v1 下，不在渠道前缀下）
  String _responsesUrl(String base) {
    var b = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
    if (b.endsWith('/v1')) return '$b/responses';
    for (final seg in ['/anthropic', '/claude', '/gemini', '/openai']) {
      if (b.endsWith(seg)) {
        b = b.substring(0, b.length - seg.length);
        break;
      }
    }
    return '$b/v1/responses';
  }

  Future<http.StreamedResponse> _send(http.Request request) =>
      _client.send(request).timeout(const Duration(seconds: 30));

  /// Web 端默认 XHR 拿不到流式响应，用 fetch_client 才能逐 token 返回
  static final _client = kIsWeb ? createWebClient() : http.Client();

  Stream<String> _anthropic(
    List<({String role, String content})> history,
    String baseUrl,
    String apiKey,
    String model,
    String? systemPrompt,
  ) async* {
    final request = http.Request('POST', Uri.parse(_anthropicUrl(baseUrl)))
      ..headers.addAll({
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'authorization': 'Bearer $apiKey',
        'anthropic-version': '2023-06-01',
      })
      ..body = jsonEncode({
        'model': model,
        'max_tokens': 4096,
        'stream': true,
        'temperature': 0.8,
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          'system': systemPrompt,
        'messages': [
          for (final m in history) {'role': m.role, 'content': m.content},
        ],
      });

    final response = await _send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('接口返回 ${response.statusCode}: ${_brief(body)}');
    }

    await for (final data in _sseData(response.stream)) {
      final json = jsonDecode(data) as Map<String, dynamic>;
      switch (json['type']) {
        case 'content_block_delta':
          final delta = json['delta'] as Map?;
          final text = delta?['text'];
          if (text is String && text.isNotEmpty) yield text;
        case 'message_stop':
          return;
        case 'error':
          throw Exception('接口错误: ${_brief(data)}');
      }
    }
  }

  Stream<String> _openai(
    List<({String role, String content})> history,
    String baseUrl,
    String apiKey,
    String model,
    String? systemPrompt,
  ) async* {
    final request = http.Request('POST', Uri.parse(_openaiUrl(baseUrl)))
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'temperature': 0.8,
        'top_p': 0.9,
        'presence_penalty': 0.6,
        'frequency_penalty': 0.4,
        'messages': [
          if (systemPrompt != null && systemPrompt.isNotEmpty)
            {'role': 'system', 'content': systemPrompt},
          for (final m in history)
            {'role': m.role, 'content': m.content},
        ],
      });

    final response = await _send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('接口返回 ${response.statusCode}: ${_brief(body)}');
    }

    await for (final data in _sseData(response.stream)) {
      if (data == '[DONE]') return;
      final json = jsonDecode(data) as Map<String, dynamic>;
      final choices = json['choices'] as List?;
      final delta = (choices?.firstOrNull as Map?)?['delta'] as Map?;
      final text = delta?['content'];
      if (text is String && text.isNotEmpty) yield text;
    }
  }

  /// OpenAI Responses API（Codex 渠道）：POST /v1/responses，SSE 流式
  Stream<String> _responses(
    List<({String role, String content})> history,
    String baseUrl,
    String apiKey,
    String model,
    String? systemPrompt,
  ) async* {
    final request = http.Request('POST', Uri.parse(_responsesUrl(baseUrl)))
      ..headers.addAll({
        'content-type': 'application/json',
        'authorization': 'Bearer $apiKey',
      })
      ..body = jsonEncode({
        'model': model,
        'stream': true,
        'temperature': 0.8,
        if (systemPrompt != null && systemPrompt.isNotEmpty)
          'instructions': systemPrompt,
        'input': [
          for (final m in history)
            {
              'type': 'message',
              'role': m.role,
              'content': [
                {
                  'type': m.role == 'assistant'
                      ? 'output_text'
                      : 'input_text',
                  'text': m.content,
                },
              ],
            },
        ],
      });

    final response = await _send(request);
    if (response.statusCode != 200) {
      final body = await response.stream.bytesToString();
      throw Exception('接口返回 ${response.statusCode}: ${_brief(body)}');
    }

    await for (final data in _sseData(response.stream)) {
      if (data == '[DONE]') return;
      final json = jsonDecode(data) as Map<String, dynamic>;
      switch (json['type']) {
        case 'response.output_text.delta':
          final text = json['delta'];
          if (text is String && text.isNotEmpty) yield text;
        case 'response.completed':
        case 'response.done':
          return;
        case 'response.failed':
        case 'error':
          throw Exception('接口错误: ${_brief(data)}');
      }
    }
  }

  /// SSE 拆包：按空行分隔事件，取每段 data: 行内容
  Stream<String> _sseData(Stream<List<int>> stream) async* {
    var buffer = '';
    await for (final chunk in stream.transform(utf8.decoder)) {
      buffer += chunk;
      var idx = buffer.indexOf('\n\n');
      while (idx >= 0) {
        final event = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        idx = buffer.indexOf('\n\n');
        for (final line in event.split('\n')) {
          final l = line.trim();
          if (l.startsWith('data:')) {
            yield l.substring(5).trim();
          }
        }
      }
    }
  }

  String _brief(String body) =>
      body.length <= 200 ? body : body.substring(0, 200);
}
