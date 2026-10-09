import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/services/cc_switch_base.dart';

void main() {
  test('parses a Codex config with an extra JSON escape layer', () {
    const config =
        'model = "gpt-6.1-sol"\n'
        '[model_providers.custom]\n'
        'base_url = "https://example.invalid/v1"\n'
        'wire_api = "responses"\n';
    final encoded = jsonEncode(config);
    final provider = parseCcProvider(
      'id',
      'Codex',
      'codex',
      jsonEncode({
        'auth': {'OPENAI_API_KEY': 'secret'},
        'config': encoded.substring(1, encoded.length - 1),
      }),
    );
    expect(provider, isNotNull);
    expect(provider!.baseUrl, 'https://example.invalid/v1');
    expect(provider.model, 'gpt-6.1-sol');
    expect(provider.protocol, 'responses');
  });
  test('parses Codex auth and TOML config providers', () {
    final provider = parseCcProvider(
      'codex-1',
      'BeeAPI',
      'codex',
      jsonEncode({
        'auth': {'OPENAI_API_KEY': 'secret'},
        'config': '''model = "gpt-6.1-sol"
[model_providers.custom]
base_url = "https://beeapi.dev/v1"
wire_api = "responses"
''',
      }),
    );

    expect(provider, isNotNull);
    expect(provider!.apiKey, 'secret');
    expect(provider.baseUrl, 'https://beeapi.dev/v1');
    expect(provider.model, 'gpt-6.1-sol');
    expect(provider.protocol, 'responses');
  });
  test(
    'selects the active Codex provider rather than the first TOML table',
    () {
      final provider = parseCcProvider(
        'id',
        'active',
        'codex',
        jsonEncode({
          'auth': {'OPENAI_API_KEY': 'secret'},
          'config': '''model_provider = "active"
model = "custom-model"
[model_providers.unused]
base_url = "https://unused.invalid"
wire_api = "responses"
[model_providers.active]
base_url = 'https://active.invalid/v1'
wire_api = 'chat'
''',
        }),
      );
      expect(provider!.baseUrl, 'https://active.invalid/v1');
      expect(provider.protocol, 'openai');
    },
  );
  test('keeps Claude env providers working', () {
    final provider = parseCcProvider(
      'id',
      'Claude',
      'claude',
      jsonEncode({
        'env': {
          'ANTHROPIC_BASE_URL': 'https://example.invalid',
          'ANTHROPIC_AUTH_TOKEN': 'secret',
          'ANTHROPIC_MODEL': 'claude-sonnet',
        },
      }),
    );
    expect(provider!.protocol, 'anthropic');
    expect(provider.model, 'claude-sonnet');
  });
}
