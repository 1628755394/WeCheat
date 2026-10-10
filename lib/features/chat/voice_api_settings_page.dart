import '../../core/widgets/wechat_dialog.dart';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/widgets/app_page_body.dart';
import '../../models/ai_profile.dart';
import '../../providers/ai_profile_provider.dart';
import '../../services/voice_api_client.dart';

const _defaultVoiceCloneResources = <VoiceCloneResourceOption>[
  VoiceCloneResourceOption(id: 'seed-icl-1.0', label: 'ICL 1.0 字符版'),
  VoiceCloneResourceOption(id: 'seed-icl-1.0-concurr', label: 'ICL 1.0 并发版'),
  VoiceCloneResourceOption(id: 'seed-icl-2.0', label: 'ICL 2.0'),
];

class VoiceApiSettingsPage extends ConsumerStatefulWidget {
  const VoiceApiSettingsPage({super.key, required this.conversationId});

  final String conversationId;

  @override
  ConsumerState<VoiceApiSettingsPage> createState() =>
      _VoiceApiSettingsPageState();
}

class _VoiceApiSettingsPageState extends ConsumerState<VoiceApiSettingsPage> {
  late final TextEditingController _urlController;
  late final TextEditingController _tokenController;
  VoiceApiClient? _client;
  List<VoiceCloneProfile> _profiles = [];
  String _selectedId = '';
  String? _error;
  bool _loading = false;
  bool _configured = false;
  String _defaultResourceId = 'seed-icl-2.0';
  List<VoiceCloneResourceOption> _resourceOptions = _defaultVoiceCloneResources;

  AiProfile get _profile => ref.read(aiProfileProvider(widget.conversationId));

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(
      text: ref.read(aiProfileProvider(widget.conversationId)).voiceApiBaseUrl,
    );
    _tokenController = TextEditingController(text: VoiceApiRuntime.bearerToken);
    _selectedId = ref
        .read(aiProfileProvider(widget.conversationId))
        .voiceCloneProfileId;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    _client?.close();
    super.dispose();
  }

  Future<VoiceApiClient> _connect() async {
    final baseUrl = _urlController.text.trim().replaceFirst(RegExp(r'/+$'), '');
    final uri = Uri.tryParse(baseUrl);
    if (uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        !uri.hasAuthority) {
      throw const VoiceApiException(
        '请输入有效的 API 地址，例如 http://192.168.1.10:7072',
      );
    }
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      VoiceApiRuntime.bearerToken = '';
      throw const VoiceApiException('请输入 API Bearer Token');
    }
    _client?.close();
    _client = VoiceApiClient(baseUrl: baseUrl, token: token);
    VoiceApiRuntime.bearerToken = token;
    await ref
        .read(aiProfileProvider(widget.conversationId).notifier)
        .setVoiceApiProfile(
          baseUrl: baseUrl,
          cloneProfileId: _profile.voiceCloneProfileId,
        );
    return _client!;
  }

  Future<void> _reload() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await _connect();
      final config = await api.loadConfig();
      final configData = config['data'];
      if (configData is Map) {
        _configured = configData['enabled'] as bool? ?? false;
        _defaultResourceId =
            configData['defaultResourceId'] as String? ?? _defaultResourceId;
        final rawOptions = configData['resourceOptions'];
        if (rawOptions is List) {
          final options = [
            for (final row in rawOptions)
              if (row is Map) VoiceCloneResourceOption.fromMap(row),
          ];
          if (options.isNotEmpty) _resourceOptions = options;
        }
      }
      _profiles = await api.listClones();
      if (!_profiles.any((p) => p.id == _selectedId && p.status == 'success')) {
        _selectedId = '';
      }
    } catch (error) {
      _error = error is VoiceApiException
          ? error.message
          : '音色服务连接失败，请确认服务已启动（默认 127.0.0.1:7072）';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _createProfile() async {
    final values =
        await showDialog<
          ({String name, String speakerId, String trainText, String resourceId})
        >(
          context: context,
          builder: (context) => _CreateCloneDialog(
            resourceOptions: _resourceOptions,
            initialResourceId: _defaultResourceId,
          ),
        );
    if (values == null) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await _connect();
      await api.createClone(
        name: values.name,
        speakerId: values.speakerId,
        resourceId: values.resourceId,
        trainText: values.trainText,
      );
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _upload(VoiceCloneProfile profile) async {
    final files = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'ogg', 'm4a', 'aac'],
      dialogTitle: '选择火山音色训练音频',
    );
    if (files.isEmpty) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final file = files.first;
      final format = file.name.split('.').last.toLowerCase();
      if (!const {'wav', 'mp3', 'ogg', 'm4a', 'aac'}.contains(format)) {
        throw const VoiceApiException('仅支持 WAV、MP3、OGG、M4A、AAC 音频');
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
        throw const VoiceApiException('音频为空或超过 10 MB');
      }
      final api = await _connect();
      await api.uploadTrainingAudio(profile.id, file.name, bytes);
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _sync(VoiceCloneProfile profile) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await _connect();
      await api.syncClone(profile.id);
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editResource(VoiceCloneProfile profile) async {
    final currentResourceId = profile.resourceId.isEmpty
        ? _defaultResourceId
        : profile.resourceId;
    final resourceId = await showDialog<String>(
      context: context,
      builder: (context) => _ResourcePickerDialog(
        title: '修改音色资源版本',
        options: _resourceOptions,
        initialResourceId: currentResourceId,
      ),
    );
    if (resourceId == null || resourceId == currentResourceId) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = await _connect();
      await api.updateCloneResource(profile.id, resourceId);
      await _reload();
    } catch (error) {
      if (mounted) setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _resourceLabel(String resourceId) {
    for (final option in _resourceOptions) {
      if (option.id == resourceId) return option.label;
    }
    return resourceId;
  }

  Future<void> _select(VoiceCloneProfile profile) async {
    VoiceApiRuntime.bearerToken = _tokenController.text.trim();
    await ref
        .read(aiProfileProvider(widget.conversationId).notifier)
        .setVoiceApiProfile(
          baseUrl: _urlController.text.trim().replaceFirst(RegExp(r'/+$'), ''),
          cloneProfileId: profile.id,
        );
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _clearSelection() async {
    if (!await _confirmDelete('删除当前角色的音色绑定？', '删除后使用系统语音，服务端音色档案仍然保留。')) {
      return;
    }
    await ref
        .read(aiProfileProvider(widget.conversationId).notifier)
        .clearAllVoice();
    if (mounted) {
      setState(() => _selectedId = '');
      Navigator.of(context).pop();
    }
  }

  Future<bool> _confirmDelete(String title, String description) async =>
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => WeChatDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('删除', style: TextStyle(color: Colors.red)),
            ),
          ],
        ),
      ) ??
      false;

  Future<void> _deleteProfile(VoiceCloneProfile item) async {
    if (!await _confirmDelete(
      '删除音色“${item.name}”？',
      '将删除服务端的克隆档案，使用该音色的角色需要重新选择音色。此操作无法撤销。',
    )) {
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final api = _client ?? await _connect();
      await api.deleteClone(item.id);
      final current = ref.read(aiProfileProvider(widget.conversationId));
      if (current.voiceCloneProfileId == item.id) {
        await ref
            .read(aiProfileProvider(widget.conversationId).notifier)
            .clearVoiceApiProfile();
      }
      if (mounted) {
        setState(() {
          _profiles.removeWhere((profile) => profile.id == item.id);
          if (_selectedId == item.id) _selectedId = '';
        });
      }
    } catch (error) {
      if (mounted) setState(() => _error = '删除失败：$error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _statusLabel(VoiceCloneProfile profile) => switch (profile.status) {
    'success' => '已完成',
    'training' => '训练中 ${profile.progress.toStringAsFixed(0)}%',
    'failed' => '失败',
    _ => '待上传训练音频',
  };

  @override
  Widget build(BuildContext context) {
    final profile = ref.watch(aiProfileProvider(widget.conversationId));
    return Scaffold(
      backgroundColor: AppColors.searchBg,
      appBar: AppBar(
        title: const Text('SoulNexus 克隆音色'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _createProfile,
            icon: const Icon(Icons.add),
            tooltip: '新建克隆音色',
          ),
        ],
      ),
      body: AppPageBody(
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _urlController,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: '语音 API 地址',
                        hintText: 'http://电脑局域网地址:7072',
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: _tokenController,
                      obscureText: true,
                      autocorrect: false,
                      enableSuggestions: false,
                      decoration: const InputDecoration(
                        labelText: 'Bearer Token（仅保存在内存）',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: _loading ? null : _reload,
                      icon: const Icon(Icons.sync),
                      label: Text(_loading ? '连接中…' : '连接并刷新音色'),
                    ),
                    if (_configured)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: Text(
                          '已连接火山引擎克隆服务',
                          style: TextStyle(color: AppColors.primary),
                        ),
                      ),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            if (_profiles.isEmpty && !_loading)
              const Card(
                child: Padding(
                  padding: EdgeInsets.all(18),
                  child: Text('暂无音色。新建时填写火山控制台提供的 Speaker ID。'),
                ),
              ),
            for (final item in _profiles)
              Card(
                child: ListTile(
                  leading: Icon(
                    item.status == 'success'
                        ? Icons.record_voice_over
                        : Icons.hourglass_top,
                    color: item.status == 'success'
                        ? AppColors.primary
                        : AppColors.textSecondary,
                  ),
                  title: Text(item.name),
                  subtitle: Text(
                    '${item.assetId.isEmpty ? item.speakerId : item.assetId} · ${_resourceLabel(item.resourceId.isEmpty ? _defaultResourceId : item.resourceId)} · ${_statusLabel(item)}${item.failedReason.isEmpty ? '' : '\n${item.failedReason}'}',
                  ),
                  isThreeLine: item.failedReason.isNotEmpty,
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.status == 'success')
                        Icon(
                          _selectedId == item.id
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          color: AppColors.primary,
                        ),
                      PopupMenuButton<String>(
                        onSelected: (action) {
                          if (action == 'resource') _editResource(item);
                          if (action == 'upload') _upload(item);
                          if (action == 'sync') _sync(item);
                          if (action == 'delete') _deleteProfile(item);
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'delete',
                            child: Text(
                              '删除音色',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'resource',
                            child: Text('修改资源版本'),
                          ),
                          if (item.status != 'training' &&
                              item.status != 'success')
                            const PopupMenuItem(
                              value: 'upload',
                              child: Text('上传训练音频'),
                            ),
                          if (item.status != 'pending' &&
                              item.status != 'success')
                            const PopupMenuItem(
                              value: 'sync',
                              child: Text('查询训练状态'),
                            ),
                        ],
                      ),
                    ],
                  ),
                  onTap: item.status == 'success' ? () => _select(item) : null,
                ),
              ),
            if (profile.hasSoulNexusVoice)
              OutlinedButton.icon(
                onPressed: _clearSelection,
                icon: const Icon(Icons.clear),
                label: const Text('取消当前角色的音色绑定'),
              ),
            const Padding(
              padding: EdgeInsets.all(8),
              child: Text(
                'API Token 仅保存在当前运行进程内，退出应用后需重新输入。火山引擎密钥由 API 服务端配置；Speaker ID 需先在火山控制台创建。训练音频支持 WAV、MP3、OGG、M4A、AAC，文件不超过 10MB；推荐 16kHz 单声道 WAV。',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CreateCloneDialog extends StatefulWidget {
  const _CreateCloneDialog({
    required this.resourceOptions,
    required this.initialResourceId,
  });

  final List<VoiceCloneResourceOption> resourceOptions;
  final String initialResourceId;

  @override
  State<_CreateCloneDialog> createState() => _CreateCloneDialogState();
}

class _CreateCloneDialogState extends State<_CreateCloneDialog> {
  final _name = TextEditingController();
  final _speakerId = TextEditingController();
  final _trainText = TextEditingController();
  late String _resourceId;

  @override
  void initState() {
    super.initState();
    _resourceId =
        widget.resourceOptions.any(
          (option) => option.id == widget.initialResourceId,
        )
        ? widget.initialResourceId
        : widget.resourceOptions.first.id;
  }

  @override
  void dispose() {
    _name.dispose();
    _speakerId.dispose();
    _trainText.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WeChatDialog(
    title: const Text('新建克隆音色'),
    content: SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: '名称'),
          ),
          TextField(
            controller: _speakerId,
            decoration: const InputDecoration(labelText: '火山 Speaker ID'),
          ),
          DropdownButtonFormField<String>(
            initialValue: _resourceId,
            decoration: const InputDecoration(
              labelText: '音色版本（必须匹配 Speaker ID）',
            ),
            items: [
              for (final option in widget.resourceOptions)
                DropdownMenuItem(value: option.id, child: Text(option.label)),
            ],
            onChanged: (value) {
              if (value != null) setState(() => _resourceId = value);
            },
          ),
          TextField(
            controller: _trainText,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '训练音频对应文本（可选）'),
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () {
          final name = _name.text.trim();
          final speakerId = _speakerId.text.trim();
          if (name.isEmpty || speakerId.isEmpty) return;
          Navigator.pop(context, (
            name: name,
            speakerId: speakerId,
            trainText: _trainText.text.trim(),
            resourceId: _resourceId,
          ));
        },
        child: const Text('创建'),
      ),
    ],
  );
}

class _ResourcePickerDialog extends StatefulWidget {
  const _ResourcePickerDialog({
    required this.title,
    required this.options,
    required this.initialResourceId,
  });

  final String title;
  final List<VoiceCloneResourceOption> options;
  final String initialResourceId;

  @override
  State<_ResourcePickerDialog> createState() => _ResourcePickerDialogState();
}

class _ResourcePickerDialogState extends State<_ResourcePickerDialog> {
  late String _resourceId;

  @override
  void initState() {
    super.initState();
    _resourceId =
        widget.options.any((option) => option.id == widget.initialResourceId)
        ? widget.initialResourceId
        : widget.options.first.id;
  }

  @override
  Widget build(BuildContext context) => WeChatDialog(
    title: Text(widget.title),
    content: DropdownButtonFormField<String>(
      initialValue: _resourceId,
      items: [
        for (final option in widget.options)
          DropdownMenuItem(value: option.id, child: Text(option.label)),
      ],
      onChanged: (value) {
        if (value != null) setState(() => _resourceId = value);
      },
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      TextButton(
        onPressed: () => Navigator.pop(context, _resourceId),
        child: const Text('保存'),
      ),
    ],
  );
}
