import '../../core/widgets/wechat_dialog.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../providers/chat_provider.dart';
import '../../services/cc_switch.dart';
import '../../services/ollama_service.dart';

final ccProvidersLoaderProvider = Provider<Future<List<CcProvider>> Function()>(
  (ref) => loadCcProviders,
);

/// 模型选择结果：本地 Ollama / cc-switch 服务商 / 手动密钥 三种来源
class ModelChoice {
  /// ''/'ollama' 本地；'anthropic'/'openai' 远程协议
  final String provider;
  final String baseUrl;
  final String apiKey;
  final String model;

  /// 来源显示名（cc-switch 服务商名等）
  final String providerName;

  const ModelChoice({
    this.provider = 'ollama',
    this.baseUrl = '',
    this.apiKey = '',
    this.model = '',
    this.providerName = '',
  });
}

/// 模型来源的显示标签（列表尾部展示当前选择）
String modelChoiceLabel(ModelChoice c) {
  if (c.provider.isEmpty || c.provider == 'ollama') {
    return c.model.isEmpty ? '默认 ${OllamaService.defaultModel}' : c.model;
  }
  final name = c.providerName.isEmpty ? '远程接口' : c.providerName;
  return c.model.isEmpty ? name : '$name · ${c.model}';
}

/// cc-switch 服务商：桌面端直读 cc-switch.db；Web 端读导出 JSON
/// 导入逻辑见 services/cc_switch.dart

/// 通用模型选择面板：本地 Ollama 模型 / cc-switch 服务商 / 手动密钥
Future<ModelChoice?> showModelPicker(
  BuildContext context,
  WidgetRef ref,
  ModelChoice current,
) {
  // Attach error handlers before the sheet's opening animation builds its
  // FutureBuilders; an offline service can fail immediately.
  final localModels = Future.sync(
    () => ref.read(ollamaServiceProvider).listModels(),
  ).catchError((Object _) => <String>[]);
  final providers = Future.sync(ref.read(ccProvidersLoaderProvider))
      .timeout(const Duration(seconds: 10))
      .then<({List<CcProvider>? items, Object? error})>(
        (items) => (items: items, error: null),
        onError: (Object error) => (items: null, error: error),
      );
  return showModalBottomSheet<ModelChoice>(
    context: context,
    isScrollControlled: true,
    builder: (sheetContext) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(sheetContext).size.height * 0.7,
        ),
        child: ListView(
          shrinkWrap: true,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
              child: Text(
                '选择模型',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
              ),
            ),
            const _Header('本地模型（Ollama）'),
            ListTile(
              title: const Text('使用默认模型'),
              subtitle: const Text(OllamaService.defaultModel),
              onTap: () => Navigator.pop(sheetContext, const ModelChoice()),
            ),
            FutureBuilder<List<String>>(
              future: localModels,
              builder: (context, snapshot) {
                final models = snapshot.data ?? const <String>[];
                if (snapshot.hasError || (snapshot.hasData && models.isEmpty)) {
                  return const _Hint('无法获取模型列表，请确认 Ollama 正在运行');
                }
                if (!snapshot.hasData) {
                  return const _Hint('加载中…');
                }
                return Column(
                  children: [
                    for (final m in models)
                      ListTile(
                        dense: true,
                        title: Text(m, style: const TextStyle(fontSize: 15)),
                        trailing: _isCurrent(current, 'ollama', '', m)
                            ? const Icon(
                                Icons.check,
                                color: AppColors.primary,
                                size: 20,
                              )
                            : null,
                        onTap: () => Navigator.pop(
                          sheetContext,
                          ModelChoice(provider: 'ollama', model: m),
                        ),
                      ),
                  ],
                );
              },
            ),
            _Header(
              'cc-switch 服务商',
              action: TextButton(
                onPressed: () async {
                  final ok = await openCcSwitchApp();
                  if (!ok && sheetContext.mounted) {
                    ScaffoldMessenger.of(sheetContext).showSnackBar(
                      const SnackBar(
                        content: Text('未找到 cc-switch 应用或不受当前平台支持'),
                      ),
                    );
                  }
                },
                child: const Text('打开 cc-switch'),
              ),
            ),
            FutureBuilder<({List<CcProvider>? items, Object? error})>(
              future: providers,
              builder: (context, snapshot) {
                if (snapshot.data?.error != null) {
                  return const _Hint('服务商配置读取失败，请检查 cc-switch，或手动填写接口');
                }
                if (!snapshot.hasData) return const _Hint('加载中…');
                final providers = snapshot.data!.items!;
                if (providers.isEmpty) {
                  return _Hint(
                    canOpenCcSwitch
                        ? '未读取到服务商，可先点上方「打开 cc-switch」检查配置'
                        : '未找到服务商配置，先运行 tool\\export_ccswitch.ps1',
                  );
                }
                return Column(
                  children: [
                    for (final p in providers)
                      ListTile(
                        dense: true,
                        title: Text(
                          '${p.name}（${p.appType}）',
                          style: const TextStyle(fontSize: 15),
                        ),
                        subtitle: Text(
                          '${p.model.isEmpty ? '未配置模型名' : p.model} · ${p.baseUrl}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        trailing:
                            _isCurrent(current, p.protocol, p.baseUrl, p.model)
                            ? const Icon(
                                Icons.check,
                                color: AppColors.primary,
                                size: 20,
                              )
                            : null,
                        onTap: () => Navigator.pop(
                          sheetContext,
                          ModelChoice(
                            provider: p.protocol,
                            baseUrl: p.baseUrl,
                            apiKey: p.apiKey,
                            model: p.model,
                            providerName: p.name,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const _Header('自定义接口'),
            ListTile(
              dense: true,
              leading: const Icon(Icons.key, color: AppColors.primary),
              title: const Text(
                '手动填写 Base URL + 密钥',
                style: TextStyle(fontSize: 15),
              ),
              onTap: () async {
                final choice = await _showCustomKeyDialog(sheetContext);
                if (choice != null && sheetContext.mounted) {
                  Navigator.pop(sheetContext, choice);
                }
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
}

bool _isCurrent(ModelChoice c, String provider, String baseUrl, String model) =>
    (c.provider.isEmpty ? 'ollama' : c.provider) == provider &&
    c.baseUrl == baseUrl &&
    (c.model == model ||
        (c.model.isEmpty &&
            provider == 'ollama' &&
            model == OllamaService.defaultModel));

/// 手动密钥表单：协议 + Base URL + API Key + 模型名
Future<ModelChoice?> _showCustomKeyDialog(BuildContext context) {
  final urlController = TextEditingController();
  final keyController = TextEditingController();
  final modelController = TextEditingController();
  var protocol = 'openai';

  return showDialog<ModelChoice>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (context, setState) => WeChatDialog(
        title: const Text('自定义接口'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            DropdownButtonFormField<String>(
              initialValue: protocol,
              decoration: const InputDecoration(labelText: '接口协议'),
              items: const [
                DropdownMenuItem(value: 'openai', child: Text('OpenAI 兼容')),
                DropdownMenuItem(
                  value: 'responses',
                  child: Text('OpenAI Responses'),
                ),
                DropdownMenuItem(
                  value: 'anthropic',
                  child: Text('Claude / Anthropic'),
                ),
              ],
              onChanged: (v) => setState(() => protocol = v ?? 'openai'),
            ),
            TextField(
              controller: urlController,
              decoration: const InputDecoration(
                labelText: 'Base URL',
                hintText: 'https://api.example.com/v1',
              ),
            ),
            TextField(
              controller: keyController,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'API Key',
                hintText: 'sk-...',
              ),
            ),
            TextField(
              controller: modelController,
              decoration: const InputDecoration(
                labelText: '模型名',
                hintText: 'gpt-4o-mini / claude-sonnet-4',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final url = urlController.text.trim();
              final key = keyController.text.trim();
              final model = modelController.text.trim();
              if (url.isEmpty || key.isEmpty || model.isEmpty) return;
              Navigator.pop(
                dialogContext,
                ModelChoice(
                  provider: protocol,
                  baseUrl: url,
                  apiKey: key,
                  model: model,
                  providerName: '自定义',
                ),
              );
            },
            child: const Text('保存'),
          ),
        ],
      ),
    ),
  );
}

class _Header extends StatelessWidget {
  final String text;
  final Widget? action;
  const _Header(this.text, {this.action});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 14, 16, 2),
    child: Row(
      children: [
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 13,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        ?action,
      ],
    ),
  );
}

class _Hint extends StatelessWidget {
  final String text;
  const _Hint(this.text);

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    child: Text(
      text,
      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
    ),
  );
}
