import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/ai_profile.dart';
import '../models/expression_profile.dart';
import '../models/live2d_model_config.dart';

enum ActorEmotion { happy, shy, angry, sad, surprised, tired, wary }

enum ActorEvent {
  userSpeech,
  compliment,
  insult,
  memory,
  interruption,
  mute,
  unmute,
  silence,
}

class ActorFrame {
  final double breath;
  final double blink;
  final double gazeX;
  final double gazeY;
  final double headTilt;
  final double bodyLean;
  final double smile;
  final double browTension;
  final double pupil;
  final double blush;
  final double mouthOpen;
  final double attention;

  const ActorFrame({
    this.breath = 0,
    this.blink = 0,
    this.gazeX = 0,
    this.gazeY = 0,
    this.headTilt = 0,
    this.bodyLean = 0,
    this.smile = 0,
    this.browTension = 0,
    this.pupil = 0,
    this.blush = 0,
    this.mouthOpen = 0,
    this.attention = 1,
  });

  /// Neutral parameter contract for a future Cubism renderer.
  Map<String, double> toParameters() => {
    'breath': breath,
    'blink': blink,
    'gazeX': gazeX,
    'gazeY': gazeY,
    'headTilt': headTilt,
    'bodyLean': bodyLean,
    'smile': smile,
    'browTension': browTension,
    'pupil': pupil,
    'blush': blush,
    'mouthOpen': mouthOpen,
  };
}

enum ActorAction { wave, nod, cheer, wink, shakeHead, smile, raiseLeg, stop }

class VirtualActor extends ChangeNotifier {
  VirtualActor(AiProfile profile, {Random? random})
    : _random = random ?? Random(),
      config = profile.expressionProfile,
      _baseline = _initialBaseline(profile);

  final Random _random;
  ExpressionProfile config;
  final Map<ActorEmotion, double> _baseline;
  final Map<ActorEmotion, double> _medium = {};
  final Map<ActorEmotion, double> _target = {};
  ActorEvent? _reaction;
  double _reactionLife = 0;
  double _reactionLength = 0;
  double _time = 0;
  double _blinkAt = 2;
  double _blinkLife = 0;
  double _gazeAt = 3;
  double _gazeTarget = 0;
  double _gaze = 0;
  double _attention = 1;
  double _speechPhase = 0;
  bool _speaking = false;
  double _speechEnergy = 1;
  ActorFrame frame = const ActorFrame();
  ActorAction? _requestedAction;
  CustomActorAction? _requestedCustomAction;
  int _actionVersion = 0;

  ActorAction? get requestedAction => _requestedAction;
  CustomActorAction? get requestedCustomAction => _requestedCustomAction;
  int get actionVersion => _actionVersion;

  static ActorAction? parseAction(String text) {
    if (RegExp(r'停止|停下|别动|不要动|stop', caseSensitive: false).hasMatch(text)) {
      return ActorAction.stop;
    }
    if (RegExp(r'不要|别|不用|不许').hasMatch(text)) return null;
    if (RegExp(r'微笑|笑一个|笑一笑|smile', caseSensitive: false).hasMatch(text)) {
      return ActorAction.smile;
    }
    if (RegExp(r'抬腿|踢腿|抬脚').hasMatch(text)) return ActorAction.raiseLeg;
    if (RegExp(r'摇摇头|摇头|shake\s*head', caseSensitive: false).hasMatch(text)) {
      return ActorAction.shakeHead;
    }
    if (RegExp(r'挥挥手|挥手|摆手|招手|打招呼|wave', caseSensitive: false).hasMatch(text)) {
      return ActorAction.wave;
    }
    if (RegExp(r'点点头|点头|颔首|nod', caseSensitive: false).hasMatch(text)) {
      return ActorAction.nod;
    }
    if (RegExp(r'欢呼|跳一下|开心地动|cheer', caseSensitive: false).hasMatch(text)) {
      return ActorAction.cheer;
    }
    if (RegExp(r'眨眨眼|眨眼|wink', caseSensitive: false).hasMatch(text)) {
      return ActorAction.wink;
    }
    return null;
  }

  bool requestAction(ActorAction action) {
    if (!config.animationEnabled || action == ActorAction.raiseLeg) {
      return false;
    }
    _requestedAction = action;
    _requestedCustomAction = null;
    _actionVersion++;
    notifyListeners();
    return true;
  }

  bool requestCustomAction(CustomActorAction action) {
    if (!config.animationEnabled) return false;
    _requestedAction = null;
    _requestedCustomAction = action;
    _actionVersion++;
    notifyListeners();
    return true;
  }

  static Map<ActorEmotion, double> _initialBaseline(AiProfile profile) => {
    ActorEmotion.happy: ((profile.affinity + 100) / 200 * 0.18).clamp(0, 0.18),
    ActorEmotion.wary: profile.affinity < 0 ? 0.2 : 0,
    ActorEmotion.tired: 0,
  };

  void updateProfile(AiProfile profile) {
    config = profile.expressionProfile;
    _baseline.addAll(_initialBaseline(profile));
  }

  void hearUser(String text, {List<String> memories = const []}) {
    _attention = 1;
    react(ActorEvent.userSpeech);
    if (RegExp(r'喜欢你|谢谢你|真棒|好厉害|真好看|可爱|漂亮|夸夸').hasMatch(text)) {
      react(ActorEvent.compliment);
      _target[ActorEmotion.happy] = 0.65;
      _target[ActorEmotion.shy] = 0.4;
    } else if (RegExp(r'讨厌你|闭嘴|滚开|烦死|笨蛋|废物').hasMatch(text)) {
      react(ActorEvent.insult);
      _target[ActorEmotion.angry] = 0.55;
      _target[ActorEmotion.sad] = 0.25;
    }
    if (config.memoryEmotionTrigger &&
        text.length >= 2 &&
        memories.any(
          (entry) =>
              entry.length >= 4 &&
              entry
                  .split(RegExp(r'[，。；;：:\s]'))
                  .any((part) => part.length >= 2 && text.contains(part)),
        )) {
      react(ActorEvent.memory);
    }
  }

  void hearAi(String text) {
    _target.clear();
    if (RegExp(r'开心|高兴|喜欢|太好|谢谢|哈哈').hasMatch(text)) {
      _target[ActorEmotion.happy] = 0.65;
    }
    if (RegExp(r'害羞|脸红|不好意思').hasMatch(text)) {
      _target[ActorEmotion.shy] = 0.55;
    }
    if (RegExp(r'生气|讨厌|别闹|够了').hasMatch(text)) {
      _target[ActorEmotion.angry] = 0.55;
    }
    if (RegExp(r'难过|抱歉|对不起|委屈|想哭').hasMatch(text)) {
      _target[ActorEmotion.sad] = 0.55;
    }
    if (RegExp(r'什么[？?]|怎么会|没想到').hasMatch(text)) {
      _target[ActorEmotion.surprised] = 0.45;
    }
    if (RegExp(r'累了|困了|疲惫').hasMatch(text)) {
      _target[ActorEmotion.tired] = 0.5;
    }
  }

  void react(ActorEvent event) {
    const priority = {
      ActorEvent.userSpeech: 1,
      ActorEvent.silence: 1,
      ActorEvent.mute: 2,
      ActorEvent.unmute: 2,
      ActorEvent.memory: 3,
      ActorEvent.compliment: 4,
      ActorEvent.insult: 4,
      ActorEvent.interruption: 5,
    };
    if (_reactionLife > 0 && priority[event]! < priority[_reaction]!) return;
    _reaction = event;
    _reactionLength = 0.35 + (1 - config.reactionSpeed) * 1.1;
    _reactionLife = _reactionLength;
    if (event == ActorEvent.interruption) _speaking = false;
    if (event == ActorEvent.silence) _attention = 0.25;
    if (event == ActorEvent.unmute) _attention = 1;
  }

  void startSpeech() {
    _speaking = true;
    _speechEnergy = 1;
  }

  void setSpeechEnergy(double value) {
    _speechEnergy = value.clamp(0.0, 1.0);
  }

  void stopSpeech() {
    _speaking = false;
    _speechEnergy = 0;
  }

  ActorFrame tick(double seconds) {
    if (!config.animationEnabled) return frame = const ActorFrame();
    final dt = seconds.clamp(0.0, 0.1);
    _time += dt;
    _reactionLife = max(0, _reactionLife - dt);
    if (_reactionLife == 0) _reaction = null;
    _speechPhase += dt * 15;

    for (final emotion in ActorEmotion.values) {
      final current = _medium[emotion] ?? 0;
      final desired = (_target[emotion] ?? 0) * config.emotionSensitivity;
      _medium[emotion] = _approach(
        current,
        desired,
        dt * (0.7 + config.reactionSpeed),
      );
      _target[emotion] = max(0, (_target[emotion] ?? 0) - dt * 0.07);
    }
    final happy =
        (_baseline[ActorEmotion.happy] ?? 0) +
        (_medium[ActorEmotion.happy] ?? 0);
    final shy = _medium[ActorEmotion.shy] ?? 0;
    final angry = _medium[ActorEmotion.angry] ?? 0;
    final sad = _medium[ActorEmotion.sad] ?? 0;
    final tired = _medium[ActorEmotion.tired] ?? 0;
    final surprise = _medium[ActorEmotion.surprised] ?? 0;
    final reaction = _reactionLife == 0
        ? 0.0
        : sin(pi * _reactionLife / _reactionLength);

    if (_time >= _blinkAt) {
      _blinkLife = 0.15;
      _blinkAt =
          _time + 1.3 + _random.nextDouble() * (4 - config.blinkBaseRate * 2);
    }
    _blinkLife = max(0, _blinkLife - dt);
    if (_time >= _gazeAt) {
      _gazeTarget = (_random.nextDouble() * 2 - 1) * config.gazeWanderAmount;
      _gazeAt = _time + 1.8 + _random.nextDouble() * 3;
    }
    _gaze = _approach(_gaze, _gazeTarget * (1 - _attention), dt * 0.6);
    final breathSpeed = 0.19 + config.breathSpeedBase * 0.23 + angry * 0.2;
    final breath = (sin(_time * 2 * pi * breathSpeed) + 1) / 2;
    final mouth = _speaking
        ? (0.16 + 0.62 * (sin(_speechPhase) + 1) / 2) * _speechEnergy
        : 0.0;

    return frame = ActorFrame(
      breath: breath,
      blink: _blinkLife > 0 ? sin(pi * _blinkLife / 0.15) : 0,
      gazeX: _gaze - shy * 0.2,
      gazeY: tired * 0.3 + sad * 0.2,
      headTilt: (shy * 0.2 + reaction * 0.08) * config.bodyMovementIntensity,
      bodyLean:
          (happy * 0.15 - angry * 0.2 - sad * 0.1) *
          config.bodyMovementIntensity,
      smile: (happy + shy * 0.2 - angry * 0.4 - sad * 0.3).clamp(-1, 1),
      browTension: (angry + sad * 0.35 + reaction * 0.2).clamp(0, 1),
      pupil:
          (surprise +
                  (_reaction == ActorEvent.compliment ? reaction * 0.5 : 0) -
                  angry * 0.2)
              .clamp(-1, 1),
      blush: shy.clamp(0, 1),
      mouthOpen: mouth,
      attention: _attention,
    );
  }

  static double _approach(double current, double target, double step) =>
      current + (target - current) * step.clamp(0.0, 1.0);
}
