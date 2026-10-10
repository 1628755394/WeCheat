import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/live2d_model_config.dart';
import 'package:wecheat/services/live2d_import_io.dart';

void main() {
  late Directory temp;
  setUp(() async {
    temp = await Directory.systemTemp.createTemp('model_test_');
  });
  tearDown(() async {
    await temp.delete(recursive: true);
  });

  test(
    'import copies a complete model and persists per-character configuration',
    () async {
      final model = await importLive2dModel(
        p.absolute('assets/live2d/mao/mao_pro.model3.json'),
        temp.path,
      );
      expect(
        await File(p.join(model.directory, model.fileName)).exists(),
        isTrue,
      );
      expect(
        await File(p.join(model.directory, 'mao_pro.4096', 'texture_00.png'))
            .exists(),
        isTrue,
      );
      expect(model.parameterIds, contains('ParamArmLA01'));
      expect(model.motions.length, 7);
      final motion = model.motions.last;
      expect(motion.duration, greaterThan(0));
      final action = CustomActorAction(
        id: 'test',
        name: '我的动作',
        group: motion.group,
        index: motion.index,
        triggers: ['抱抱'],
        speed: 1.5,
      );
      final profile = AiProfile(live2dModel: model.withActions([action]));
      final restored = AiProfile.fromMap(profile.toMap());
      expect(restored.live2dModel!.actions.single.speed, 1.5);
      expect(restored.live2dModel!.matchAction('可以抱抱我吗')?.name, '我的动作');
      expect(restored.live2dModel!.matchAction('不要抱抱'), isNull);
      expect(restored.live2dModel!.matchAction('停止我的动作'), isNull);
      expect(
        restored.live2dModel!.motionFor(action)?.fileName,
        motion.fileName,
      );
      expect(restored.live2dModel!.directory, model.directory);
      expect(restored.copyWith(persona: '角色').live2dModel, isNotNull);
      expect(restored.copyWith(clearLive2dModel: true).live2dModel, isNull);
      expect(AiProfile.fromMap({}).live2dModel, isNull);
    },
  );

  test('ZIP import preserves nested model references', () async {
    final archive = Archive();
    archive.add(
      ArchiveFile.string(
        'model/test.model3.json',
        jsonEncode({
          'Version': 3,
          'FileReferences': {
            'Moc': 'test.moc3',
            'Textures': ['tex/a.png'],
          },
        }),
      ),
    );
    archive.add(ArchiveFile.bytes('model/test.moc3', ascii.encode('MOC3test')));
    archive.add(ArchiveFile.bytes('model/tex/a.png', [1, 2, 3]));
    final zip = File(p.join(temp.path, 'model.zip'));
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    final model = await importLive2dModel(zip.path, p.join(temp.path, 'store'));
    expect(model.fileName, 'test.model3.json');
    expect(await File(p.join(model.directory, 'tex', 'a.png')).readAsBytes(), [
      1,
      2,
      3,
    ]);
  });

  test('incomplete models and unsafe archive paths fail without leaving partial imports', () async {
    final store = p.join(temp.path, 'store');
    final definition = File(p.join(temp.path, 'test.model3.json'));
    await definition.writeAsString(
      jsonEncode({
        'Version': 3,
        'FileReferences': {
          'Moc': 'missing.moc3',
          'Textures': ['missing.png'],
        },
      }),
    );
    await expectLater(
      importLive2dModel(definition.path, store),
      throwsFormatException,
    );
    expect(await Directory(store).list().toList(), isEmpty);
    final archive = Archive()..add(ArchiveFile.string('../escaped.txt', 'no'));
    final zip = File(p.join(temp.path, 'bad.zip'));
    await zip.writeAsBytes(ZipEncoder().encode(archive));
    await expectLater(
      importLive2dModel(zip.path, store),
      throwsFormatException,
    );
    expect(await Directory(store).list().toList(), isEmpty);
    expect(await File(p.join(temp.path, 'escaped.txt')).exists(), isFalse);
  });
}
