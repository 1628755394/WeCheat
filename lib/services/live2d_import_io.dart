import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/live2d_model_config.dart';

Future<Live2DModelConfig?> pickLive2dModel() async {
  final selection = await FilePicker.pickFiles(
    type: FileType.custom,
    allowedExtensions: ['json', 'zip'],
    dialogTitle: '导入 Live2D 模型',
  );
  final source = selection.isEmpty ? null : selection.single.path;
  if (source == null) return null;
  final support = await getApplicationSupportDirectory();
  return importLive2dModel(source, p.join(support.path, 'live2d_models'));
}

String _childPath(String root, String relative) {
  final portable = relative.replaceAll('\\', '/');
  if (portable.contains(':') || p.posix.isAbsolute(portable)) {
    throw const FormatException('模型文件路径必须在模型目录内');
  }
  final resolved = p.normalize(p.join(root, portable));
  if (!p.isWithin(root, resolved)) {
    throw const FormatException('模型文件路径超出模型目录');
  }
  return resolved;
}

// Copy only validated references into app storage, so imports survive source
// moves and incomplete imports never replace an existing profile.
Future<Live2DModelConfig> importLive2dModel(
  String source,
  String storage,
) async {
  final sourceFile = File(source);
  if (!await sourceFile.exists()) throw const FormatException('模型文件不存在');
  await Directory(storage).create(recursive: true);
  final target = await Directory(storage).createTemp('model_');
  Directory? unpacked;
  try {
    var definition = sourceFile;
    if (p.extension(source).toLowerCase() == '.zip') {
      unpacked = await Directory(storage).createTemp('unpack_');
      final archive = ZipDecoder().decodeBytes(await sourceFile.readAsBytes());
      var total = 0;
      for (final entry in archive) {
        total += entry.size;
        if (total > 256 * 1024 * 1024 || entry.isSymbolicLink) {
          throw const FormatException('模型包过大或包含链接文件');
        }
        final destination = _childPath(unpacked.path, entry.name);
        if (!entry.isFile) continue;
        final file = File(destination);
        await file.parent.create(recursive: true);
        await file.writeAsBytes(entry.content);
      }
      final definitions = await unpacked
          .list(recursive: true)
          .where(
            (entry) => entry is File && entry.path.endsWith('.model3.json'),
          )
          .cast<File>()
          .toList();
      if (definitions.length != 1) {
        throw const FormatException('每次请选择包含一个 .model3.json 的完整模型包');
      }
      definition = definitions.single;
    }
    if (!definition.path.endsWith('.model3.json')) {
      throw const FormatException('请选择 .model3.json 或完整模型 ZIP');
    }
    final root = await definition.parent.resolveSymbolicLinks();
    final json =
        jsonDecode(await definition.readAsString()) as Map<String, dynamic>;
    if (json['Version'] != 3 || json['FileReferences'] is! Map) {
      throw const FormatException('仅支持 Live2D Cubism 3 模型');
    }
    final refs = json['FileReferences'] as Map;
    if (refs['Moc'] is! String ||
        refs['Textures'] is! List ||
        (refs['Textures'] as List).isEmpty) {
      throw const FormatException('模型缺少 MOC 或纹理');
    }
    final files = <String>{p.basename(definition.path), refs['Moc'] as String};
    files.addAll((refs['Textures'] as List).cast<String>());
    for (final key in ['Physics', 'Pose', 'DisplayInfo', 'UserData']) {
      if (refs[key] is String && (refs[key] as String).isNotEmpty) {
        files.add(refs[key] as String);
      }
    }
    for (final item in (refs['Expressions'] as List? ?? [])) {
      files.add((item as Map)['File'] as String);
    }
    for (final group in (refs['Motions'] as Map? ?? {}).values) {
      for (final item in group as List) {
        files.add((item as Map)['File'] as String);
        if (item['Sound'] is String && (item['Sound'] as String).isNotEmpty) {
          files.add(item['Sound'] as String);
        }
      }
    }
    for (final relative in files) {
      final file = File(_childPath(root, relative));
      if (!await file.exists()) throw FormatException('模型缺少文件：$relative');
      final actual = await file.resolveSymbolicLinks();
      if (!p.isWithin(root, actual)) throw const FormatException('模型引用了目录外的文件');
      if (relative.endsWith('.json')) jsonDecode(await file.readAsString());
      final out = File(_childPath(target.path, relative));
      await out.parent.create(recursive: true);
      await file.copy(out.path);
    }
    final moc = await File(_childPath(target.path, refs['Moc'] as String))
        .open();
    final header = await moc.read(4);
    await moc.close();
    if (ascii.decode(header, allowInvalid: true) != 'MOC3') {
      throw const FormatException('MOC3 文件无效');
    }
    var ids = <String>[];
    final display = refs['DisplayInfo'];
    if (display is String && display.isNotEmpty) {
      final info = jsonDecode(
        await File(_childPath(target.path, display)).readAsString(),
      ) as Map;
      ids = [
        for (final param in (info['Parameters'] as List? ?? []))
          (param as Map)['Id'] as String,
      ];
    }
    if (ids.isEmpty) {
      final parameters = <String>{};
      for (final relative in files.where(
        (file) => file.endsWith('.motion3.json'),
      )) {
        final motion = jsonDecode(
          await File(_childPath(target.path, relative)).readAsString(),
        ) as Map;
        for (final curve in motion['Curves'] as List? ?? []) {
          if (curve['Target'] == 'Parameter' && curve['Id'] is String) {
            parameters.add(curve['Id'] as String);
          }
        }
      }
      ids = parameters.toList();
    }
    final motions = <Live2DMotion>[];
    for (final group in (refs['Motions'] as Map? ?? {}).entries) {
      final entries = group.value as List;
      for (var index = 0; index < entries.length; index++) {
        final file = (entries[index] as Map)['File'] as String;
        final motion = jsonDecode(
          await File(_childPath(target.path, file)).readAsString(),
        ) as Map;
        final duration = ((motion['Meta'] as Map?)?['Duration'] as num?)
            ?.toDouble();
        if (duration == null || !duration.isFinite || duration <= 0) {
          throw FormatException('动画时长无效：$file');
        }
        motions.add(
          Live2DMotion(
            group: group.key as String,
            index: index,
            fileName: p.basename(file),
            duration: duration,
          ),
        );
      }
    }
    return Live2DModelConfig(
      directory: target.path,
      fileName: p.basename(definition.path),
      name: p.basename(definition.path).replaceFirst('.model3.json', ''),
      parameterIds: ids,
      motions: motions,
    );
  } catch (_) {
    await target.delete(recursive: true);
    rethrow;
  } finally {
    if (unpacked != null) await unpacked.delete(recursive: true);
  }
}
