import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/live2d_model_config.dart';
import 'package:wecheat/repositories/ai_characters.dart';

void main() {
  test('love migration preserves model and voice and allows later relationship edits', () async {
    final directory = await Directory.systemTemp.createTemp('relationship');
    Hive.init(directory.path);
    try {
      final box = await Hive.openBox('ai_profiles');
      final conv = await Hive.openBox('conversations');
      const id = 'conv_char_baoqingfangzhu';
      await box.put(
        id,
        const AiProfile(
          affinity: 16,
          voiceCloneProfileId: 'voice-id',
          live2dModel: Live2DModelConfig(
            directory: 'local-model',
            fileName: 'model.model3.json',
            name: '角色',
          ),
        ).toMap(),
      );
      await AiCharacters.seed(conv, forceProfiles: true);
      var profile = AiProfile.fromMap(box.get(id) as Map);
      expect(profile.affinityStage, '相爱');
      expect(profile.relationship, contains('彼此相爱'));
      expect(profile.live2dModel?.directory, 'local-model');
      expect(profile.voiceCloneProfileId, 'voice-id');
      await box.put(id, profile.copyWith(relationship: '用户后来修改的关系').toMap());
      await AiCharacters.seed(conv, forceProfiles: true);
      profile = AiProfile.fromMap(box.get(id) as Map);
      expect(profile.relationship, '用户后来修改的关系');
    } finally {
      await Hive.close();
      await directory.delete(recursive: true);
    }
  });
}
