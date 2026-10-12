import 'dart:math' as math;

import '../models/mood_state.dart';

MoodState decayMood(MoodState mood, DateTime now) {
  final elapsed = math.max(0, now.difference(mood.updatedAt).inMilliseconds);
  final days = elapsed / 86400000;
  if (elapsed == 0) return mood;
  final factor = math.exp(-elapsed / 7200000);
  return mood.copyWith(
    valence: (mood.valence * factor) - days * 0.1,
    arousal: (mood.arousal * factor) - days * 0.05,
    updatedAt: now,
    lastEvent: days >= 1 ? '长时间冷落' : mood.lastEvent,
  );
}

MoodState applyMoodEvent(MoodState current, String event, DateTime now) {
  final mood = decayMood(current, now);
  if (event == '厌恶词') {
    final repeat =
        mood.lastNegativeAt != null &&
            mood.repeatedNegativeEvents > 0 &&
            now.difference(mood.lastNegativeAt!) < const Duration(seconds: 30)
        ? mood.repeatedNegativeEvents + 1
        : 1;
    final delta = repeat == 1
        ? -0.3
        : repeat == 2
        ? -0.1
        : 0.0;
    return mood.copyWith(
      valence: mood.valence + delta,
      arousal:
          mood.arousal +
          (repeat == 1
              ? 0.2
              : repeat == 2
              ? 0.1
              : 0),
      lastNegativeAt: now,
      lastEvent: event,
      repeatedNegativeEvents: repeat,
      neutralTurns: 0,
    );
  }
  if (event == '撤回消息' || event == '已读不回') {
    return mood.copyWith(
      valence: mood.valence + (event == '撤回消息' ? -0.1 : -0.15),
      arousal: mood.arousal + (event == '撤回消息' ? 0.15 : 0.1),
      lastEvent: event,
      lastNegativeAt: now,
      neutralTurns: 0,
    );
  }
  final turns = mood.neutralTurns + 1;
  return mood.copyWith(
    valence: mood.valence + (mood.valence < -0.3 && turns >= 2 ? 0.05 : 0),
    lastEvent: event,
    neutralTurns: turns,
    repeatedNegativeEvents: mood.repeatedNegativeEvents,
  );
}

MoodState afterMoodReply(MoodState mood, int affinity, DateTime now) {
  if (mood.zone(affinity) != MoodZone.quarrel) {
    return mood.copyWith(quarrelReplies: 0, updatedAt: now);
  }
  if (mood.quarrelReplies >= 1) {
    return mood.copyWith(
      valence: math.max(-0.25, mood.valence + 0.25),
      arousal: math.min(0.55, mood.arousal - 0.25),
      quarrelReplies: 0,
      lastEvent: '连续拌嘴保护',
      updatedAt: now,
    );
  }
  return mood.copyWith(quarrelReplies: 1, updatedAt: now);
}

String getMoodInstruction(MoodState mood, int affinity) =>
    switch (mood.zone(affinity)) {
      MoodZone.fuse => '【情绪熔断】话少且冷淡，不想争辩。禁止带刺、质问和冲突式表达；仍需回应当前问题。',
      MoodZone.quarrel when affinity >= 70 =>
        '【亲密赌气】对当前这件事感到委屈或失望，可以轻微反问和表达不满。只谈行为，不评价对方的智商、人格或价值。',
      MoodZone.quarrel => '【烦躁不悦】对当前这件事有些不耐烦，可以克制地质疑做法。只谈行为，不贬低对方本人。',
      MoodZone.distant => '【冷淡抵触】简短疏离地回应，不拌嘴、不说带刺的话。',
      MoodZone.mild => '【轻微别扭】可以简短吐槽或轻声抱怨当前事情，不尖锐质问。',
      MoodZone.calm => '',
    };

int adjustAffinityGain(int baseGain, MoodState mood, int affinity) {
  if (baseGain == 0) return 0;
  if (mood.valence < -0.5) {
    if (affinity >= 70) return baseGain < 0 ? 0 : (baseGain * 0.5).toInt();
    return baseGain < 0 ? baseGain : (baseGain * 0.3 - 1).toInt();
  }
  if (mood.valence > 0.5) return (baseGain * 1.2).toInt();
  return baseGain;
}

final _personalAttacks = RegExp(r'笨蛋|傻|废物|蠢货|智障|白痴|弱智|没脑子|垃圾人');
bool containsPersonalAttack(String text) => _personalAttacks.hasMatch(text);

/// Returns true when the current stream ends with the beginning of a banned
/// phrase. This lets streaming UIs hold back only that short suffix until the
/// next chunk confirms whether it becomes a personal attack.
bool endsWithPersonalAttackPrefix(String text) {
  const phrases = ['笨蛋', '傻', '废物', '蠢货', '智障', '白痴', '弱智', '没脑子', '垃圾人'];
  for (final phrase in phrases) {
    for (var length = 1; length < phrase.length; length++) {
      if (text.endsWith(phrase.substring(0, length))) return true;
    }
  }
  return false;
}

bool canEnterConflictScene(MoodState mood, int affinity) =>
    affinity >= 70 && mood.zone(affinity) == MoodZone.quarrel;
