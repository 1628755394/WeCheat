import 'dart:convert';
import 'dart:io';

import 'cc_switch_base.dart';

/// 桌面端：直读 ~/.cc-switch/cc-switch.db（借 sqlite3 命令行解析，不引原生依赖）

const _sqliteCandidates = <String>[
  'sqlite3',
  r'C:\Android\sdk\platform-tools\sqlite3.exe',
];

String? get _dbPath {
  final home =
      Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'];
  return home == null ? null : '$home/.cc-switch/cc-switch.db';
}

/// cc-switch 安装位置候选
String? get _exePath {
  final local = Platform.environment['LOCALAPPDATA'];
  for (final p in [
    if (local != null) '$local\\Programs\\CC Switch\\cc-switch.exe',
    r'C:\Program Files\CC Switch\cc-switch.exe',
  ]) {
    if (File(p).existsSync()) return p;
  }
  return null;
}

/// 能否启动 cc-switch 应用（仅桌面端 true）
bool get canOpenCcSwitch => _exePath != null;

/// 打开 cc-switch 主程序（用户在里头改完配置后回 App 重开选择面板即可）
Future<bool> openCcSwitchApp() async {
  final exe = _exePath;
  if (exe == null) return false;
  await Process.start(exe, const [], mode: ProcessStartMode.detached);
  return true;
}

Future<List<CcProvider>> loadCcProviders() async {
  final db = _dbPath;
  if (db == null || !File(db).existsSync()) return const [];
  for (final exe in _sqliteCandidates) {
    try {
      final r = await Process.run(exe, [
        '-json',
        db,
        'SELECT id, name, app_type, settings_config FROM providers;'
      ]);
      if (r.exitCode != 0) continue;
      final out = <CcProvider>[];
      for (final row in jsonDecode(r.stdout as String) as List) {
        if (row is! Map) continue;
        final p = parseCcProvider(
          '${row['id']}',
          '${row['name']}',
          '${row['app_type']}',
          '${row['settings_config']}',
        );
        if (p != null) out.add(p);
      }
      return out;
    } catch (_) {
      continue;
    }
  }
  return const [];
}
