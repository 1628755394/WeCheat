import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wecheat/providers/output_mode_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late ProviderContainer container;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('wecheat_output_');
    Hive.init(directory.path);
    container = ProviderContainer();
    await container.read(outputModeProvider.notifier).ensureLoaded();
  });
  tearDown(() async {
    container.dispose();
    await Hive.close();
    await directory.delete(recursive: true);
  });

  test(
    'defaults to speech and text and restores saved global selection',
    () async {
      expect(container.read(outputModeProvider), OutputMode.speechAndText);
      await container.read(outputModeProvider.notifier).select(OutputMode.text);
      container.dispose();
      await Hive.close();
      container = ProviderContainer();
      await container.read(outputModeProvider.notifier).ensureLoaded();
      expect(container.read(outputModeProvider), OutputMode.text);
    },
  );
}
