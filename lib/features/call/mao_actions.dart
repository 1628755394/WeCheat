import 'dart:math' as math;

import '../../services/virtual_actor.dart';

bool supportsModelAction(List<String> ids, ActorAction action) {
  final required = switch (action) {
    ActorAction.wave => ['ParamArmLA01', 'ParamArmLA02', 'ParamArmLA03'],
    ActorAction.nod => ['ParamAngleY'],
    ActorAction.shakeHead => ['ParamAngleX'],
    ActorAction.wink => ['ParamEyeLOpen', 'ParamEyeROpen'],
    ActorAction.smile => ['ParamEyeLSmile', 'ParamEyeRSmile'],
    ActorAction.cheer => ['ParamBodyAngleX', 'ParamAngleZ'],
    ActorAction.raiseLeg => ['__unsupported_leg_animation__'],
    ActorAction.stop => <String>[],
  };
  return required.every(ids.contains);
}

double maoActionDuration(ActorAction action) =>
    action == ActorAction.wave ? 3.6 : 2.4;

// These parameters are declared by mao_pro.cdi3.json. The model has no legs.
Map<String, double> maoActionParameters(ActorAction action, double seconds) {
  final duration = maoActionDuration(action);
  final t = seconds.clamp(0.0, duration);
  final fade = math.min(1.0, math.min(t / 0.25, (duration - t) / 0.3));
  final swing = math.sin(t * math.pi * 3);
  switch (action) {
    case ActorAction.wave:
      final lift = (t / 0.65).clamp(0.0, 1.0);
      final lower = ((duration - t) / 0.65).clamp(0.0, 1.0);
      final raised = math.min(lift, lower);
      final waving = t < 0.65 ? 0.0 : math.sin((t - 0.65) * math.pi * 4);
      return {
        'ParamAngleX': 0,
        'ParamBodyAngleX': 0,
        'ParamBodyAngleY': 0,
        'ParamBodyAngleZ': 0,
        'ParamLeftShoulderUp': 8 * raised,
        'ParamArmLA01': 18 * raised,
        'ParamArmLA02': -20 * raised,
        'ParamArmLA03': (-12 + 6 * waving) * raised,
        'ParamHandLA': 8 * waving * raised,
      };
    case ActorAction.nod:
      return {'ParamAngleY': 18 * swing * fade};
    case ActorAction.shakeHead:
      return {'ParamAngleX': 22 * swing * fade};
    case ActorAction.wink:
      final blink = (1 - math.cos(t * math.pi * 4)) / 2 * fade;
      return {'ParamEyeLOpen': 1 - blink, 'ParamEyeROpen': 1 - blink};
    case ActorAction.smile:
      return {
        'ParamEyeLSmile': fade,
        'ParamEyeRSmile': fade,
        'ParamMouthUp': 0.8 * fade,
        'ParamMouthForm': 0.8 * fade,
        'ParamCheek': 0.3 * fade,
      };
    case ActorAction.cheer:
      return {
        'ParamBodyAngleX': 12 * swing * fade,
        'ParamBodyAngleZ': 8 * swing * fade,
        'ParamAngleZ': -10 * swing * fade,
        'ParamArmLA01': 20 * swing * fade,
        'ParamArmRA01': -20 * swing * fade,
        'ParamArmLA03': 15 * swing * fade,
        'ParamArmRA03': -15 * swing * fade,
      };
    case ActorAction.raiseLeg:
    case ActorAction.stop:
      return {};
  }
}
