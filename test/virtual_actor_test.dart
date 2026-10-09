import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/features/call/live2d_actor.dart';
import 'package:wecheat/models/ai_profile.dart';
import 'package:wecheat/models/expression_profile.dart';
import 'package:wecheat/services/virtual_actor.dart';

void main() {
  test('expression settings survive profile serialization', () {
    final config = const ExpressionProfile().copyWith(
      emotionSensitivity: 0.9,
      bodyMovementIntensity: 0.2,
      animationEnabled: false,
    );
    final restored = AiProfile.fromMap(
      AiProfile(expressionProfile: config).toMap(),
    ).expressionProfile;
    expect(restored.emotionSensitivity, 0.9);
    expect(restored.bodyMovementIntensity, 0.2);
    expect(restored.animationEnabled, isFalse);
    expect(AiProfile.fromMap({}).expressionProfile.animationEnabled, isTrue);
  });

  test('compliment creates a smooth composite reaction', () {
    final actor = VirtualActor(const AiProfile(), random: Random(1));
    actor.hearUser('你好厉害，真漂亮');
    final first = actor.tick(0.05);
    for (var i = 0; i < 15; i++) {
      actor.tick(0.05);
    }
    final later = actor.frame;
    expect(first.smile, greaterThan(0));
    expect(later.smile, greaterThan(first.smile));
    expect(later.blush, greaterThan(0));
    expect(actor.frame.toParameters()['mouthOpen'], 0);
  });

  test('interruption stops speech and silence shifts attention', () {
    final actor = VirtualActor(const AiProfile(), random: Random(2));
    actor.startSpeech();
    actor.tick(0.05);
    expect(actor.frame.mouthOpen, greaterThan(0));
    actor.react(ActorEvent.interruption);
    actor.tick(0.05);
    expect(actor.frame.mouthOpen, 0);
    actor.react(ActorEvent.silence);
    actor.tick(0.05);
    expect(actor.frame.attention, 1);
    for (var i = 0; i < 30; i++) {
      actor.tick(0.05);
    }
    actor.react(ActorEvent.silence);
    actor.tick(0.05);
    expect(actor.frame.attention, lessThan(1));
    actor.hearUser('在吗');
    actor.tick(0.05);
    expect(actor.frame.attention, 1);
  });

  test('speech energy can shape the mouth envelope', () {
    final actor = VirtualActor(const AiProfile(), random: Random(3));
    actor.startSpeech();
    actor.tick(0.05);
    expect(actor.frame.mouthOpen, greaterThan(0));
    actor.setSpeechEnergy(0);
    expect(actor.tick(0.05).mouthOpen, 0);
    actor.setSpeechEnergy(1);
    expect(actor.tick(0.05).mouthOpen, greaterThan(0));
  });

  test('animation off produces neutral static parameters', () {
    final actor = VirtualActor(
      const AiProfile(
        expressionProfile: ExpressionProfile(animationEnabled: false),
      ),
    );
    actor.hearUser('你好厉害');
    expect(actor.tick(0.05).smile, 0);
    expect(actor.frame.mouthOpen, 0);
  });

  test('Mao parameter mapping keeps values in useful ranges', () {
    const frame = ActorFrame(
      blink: 1,
      gazeX: 0.5,
      smile: 0.7,
      browTension: 0.4,
      breath: 0.8,
      mouthOpen: 0.6,
    );
    final parameters = maoParameters(frame);
    expect(parameters['ParamEyeLOpen'], 0);
    expect(parameters['ParamEyeROpen'], 0);
    expect(parameters['ParamEyeBallX'], 0.5);
    expect(parameters['ParamAngleX'], 7.5);
    expect(parameters['ParamMouthUp'], 0.7);
    expect(parameters['ParamBrowLForm'], -0.4);
    expect(parameters['ParamBreath'], 0.8);
    expect(parameters['ParamA'], 0.6);
  });
}
