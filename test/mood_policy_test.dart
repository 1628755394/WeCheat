import 'package:flutter_test/flutter_test.dart';
import 'package:wecheat/models/mood_state.dart';
import 'package:wecheat/services/mood_policy.dart';

void main() {
  final start = DateTime(2026, 10, 12, 10);

  test('negative trigger diminishes across 30 seconds', () {
    var mood = MoodState(updatedAt: start);
    mood = applyMoodEvent(mood, '厌恶词', start);
    expect(mood.valence, closeTo(-0.3, 0.001));
    mood = applyMoodEvent(mood, '厌恶词', start.add(const Duration(seconds: 5)));
    expect(mood.valence, closeTo(-0.4, 0.001));
    expect(mood.zone(80), MoodZone.quarrel);
    mood = applyMoodEvent(mood, '厌恶词', start.add(const Duration(seconds: 10)));
    expect(mood.valence, closeTo(-0.4, 0.001));
    expect(mood.repeatedNegativeEvents, 3);
  });

  test('fuse overrides quarrel and affinity chooses voice', () {
    final mood = MoodState(valence: -0.8, arousal: 0.8);
    expect(mood.zone(100), MoodZone.fuse);
    expect(getMoodInstruction(mood, 100), contains('禁止带刺'));
    final quarrel = MoodState(valence: -0.5, arousal: 0.7);
    expect(getMoodInstruction(quarrel, 80), contains('亲密赌气'));
    expect(getMoodInstruction(quarrel, 40), contains('烦躁不悦'));
    expect(quarrel.zone(20), MoodZone.distant);
    expect(canEnterConflictScene(quarrel, 70), isTrue);
    expect(canEnterConflictScene(quarrel, 30), isFalse);
  });

  test('two neutral turns rebound and two quarrels calm down', () {
    var mood = MoodState(valence: -0.5, arousal: 0.7, updatedAt: start);
    mood = applyMoodEvent(mood, '普通消息', start);
    expect(mood.valence, -0.5);
    mood = applyMoodEvent(mood, '普通消息', start);
    expect(mood.valence, closeTo(-0.45, 0.001));
    mood = afterMoodReply(mood, 80, start);
    expect(mood.quarrelReplies, 1);
    mood = afterMoodReply(mood, 80, start);
    expect(mood.zone(80), isNot(MoodZone.quarrel));
    expect(mood.quarrelReplies, 0);
    final intense = afterMoodReply(
      MoodState(valence: -0.7, arousal: 0.9, quarrelReplies: 1),
      80,
      start,
    );
    expect(intense.zone(80), isNot(MoodZone.quarrel));
  });

  test('affinity adjustment does not penalize a neutral turn', () {
    final mood = MoodState(valence: -0.6);
    expect(adjustAffinityGain(0, mood, 20), 0);
    expect(adjustAffinityGain(6, mood, 80), 3);
    expect(adjustAffinityGain(-5, mood, 80), 0);
    expect(adjustAffinityGain(6, mood, 20), 0);
  });

  test('personal attack filter catches banned words', () {
    expect(containsPersonalAttack('你是笨蛋'), isTrue);
    expect(containsPersonalAttack('这件事让我失望'), isFalse);
    expect(endsWithPersonalAttackPrefix('你是笨'), isTrue);
    expect(endsWithPersonalAttackPrefix('这件事'), isFalse);
  });
}
