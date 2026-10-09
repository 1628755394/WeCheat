import 'dart:convert';

import 'package:toml/toml.dart';

/// cc-switch 服务商条目（桌面直读 db / Web 导出文件共用结构）
class CcProvider {
  final String id;
  final String name;
  final String appType;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 导出文件里可显式指定协议，覆盖下面的启发式推断
  final String? protocolOverride;

  const CcProvider({
    required this.id,
    required this.name,
    required this.appType,
    required this.baseUrl,
    required this.apiKey,
    required this.model,
    this.protocolOverride,
  });

  factory CcProvider.fromMap(Map m) => CcProvider(
    id: (m['id'] as String?) ?? '',
    name: (m['name'] as String?) ?? '',
    appType: (m['appType'] as String?) ?? '',
    baseUrl: (m['baseUrl'] as String?) ?? '',
    apiKey: (m['apiKey'] as String?) ?? '',
    model: (m['model'] as String?) ?? '',
    protocolOverride: (m['protocol'] as String?),
  );

  /// claude 系走 Anthropic Messages；gpt/codex 系模型走 OpenAI Responses
  /// （cc-switch 里的 Codex 渠道即使 appType 标 claude 也只支持 Responses API）
  String get protocol {
    if (protocolOverride != null && protocolOverride!.isNotEmpty) {
      return protocolOverride!;
    }
    if (RegExp(r'^(gpt|codex|o\d)').hasMatch(model)) return 'responses';
    if (RegExp(r'^(deepseek|qwen|glm|kimi|moonshot|doubao)').hasMatch(model)) {
      return 'openai';
    }
    if (appType.toLowerCase().contains('codex')) return 'responses';
    return appType.startsWith('claude') ? 'anthropic' : 'openai';
  }
}

/// 从 cc-switch providers 表的 settings_config JSON 提取地址/密钥/模型
CcProvider? parseCcProvider(
  String id,
  String name,
  String appType,
  String settingsConfig,
) {
  try {
    final settings = jsonDecode(settingsConfig) as Map;
    final env = settings['env'] as Map?;
    final auth = settings['auth'] as Map?;
    final rawConfig = settings['config'];
    Map config = const {};
    if (rawConfig is Map) config = rawConfig;
    if (rawConfig is String && rawConfig.trim().isNotEmpty) {
      try {
        config = TomlDocument.parse(rawConfig).toMap();
      } catch (_) {
        // Some older cc-switch exports contain an extra JSON escape layer.
        final decoded = jsonDecode('"$rawConfig"') as String;
        config = TomlDocument.parse(decoded).toMap();
      }
    }
    final providers = config['model_providers'] as Map?;
    final selected = config['model_provider'];
    final providerConfig =
        providers?[selected] ??
        (providers?.length == 1 ? providers!.values.single : null);
    String? configValue(String key) {
      final value = key == 'model'
          ? config[key]
          : (providerConfig is Map ? providerConfig[key] : null) ?? config[key];
      return value is String && value.isNotEmpty ? value : null;
    }

    String? pick(List<String> keys) {
      for (final k in keys) {
        final v = env?[k] ?? auth?[k];
        if (v is String && v.isNotEmpty) return v;
      }
      return null;
    }

    final base =
        pick(const [
          'ANTHROPIC_BASE_URL',
          'OPENAI_BASE_URL',
          'GOOGLE_GEMINI_BASE_URL',
        ]) ??
        configValue('base_url');
    final key =
        pick(const [
          'ANTHROPIC_AUTH_TOKEN',
          'ANTHROPIC_API_KEY',
          'OPENAI_API_KEY',
          'GEMINI_API_KEY',
        ]) ??
        configValue('api_key');
    final model =
        pick(const [
          'ANTHROPIC_MODEL',
          'ANTHROPIC_DEFAULT_SONNET_MODEL',
          'OPENAI_MODEL',
        ]) ??
        configValue('model') ??
        '';
    final wireApi = configValue('wire_api');
    if (base == null || key == null) return null;
    return CcProvider(
      id: id,
      name: name,
      appType: appType,
      baseUrl: base,
      apiKey: key,
      model: model,
      protocolOverride: wireApi == 'chat' ? 'openai' : wireApi,
    );
  } catch (_) {
    return null;
  }
}
