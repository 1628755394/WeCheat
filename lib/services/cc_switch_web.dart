import 'dart:convert';

import 'package:http/http.dart' as http;

import 'cc_switch_base.dart';

/// Web 端读不了本地 SQLite：读 tool/export_ccswitch.ps1 导出的 JSON
/// （改了 cc-switch 服务商后需重跑脚本刷新该文件）
Future<List<CcProvider>> loadCcProviders() async {
  try {
    final resp = await http
        .get(Uri.base.resolve('ccswitch_providers.json'))
        .timeout(const Duration(seconds: 10));
    if (resp.statusCode != 200) return const [];
    return [
      for (final m in jsonDecode(utf8.decode(resp.bodyBytes)) as List)
        CcProvider.fromMap(m as Map),
    ];
  } catch (_) {
    return const [];
  }
}

/// Web 端无法启动本地应用
const bool canOpenCcSwitch = false;
const String ccSwitchEmptyHint = '未找到服务商配置，请先运行 tool\\export_ccswitch.ps1';

Future<bool> openCcSwitchApp() async => false;
