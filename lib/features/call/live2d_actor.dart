import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live2d_flutter/live2d_flutter.dart';

import '../../core/widgets/app_avatar.dart';
import '../../models/ai_profile.dart';
import '../../models/contact.dart';
import '../../services/virtual_actor.dart';

const _modelDir = 'assets/live2d/mao/';
const _modelFile = 'mao_pro.model3.json';

Map<String, double> maoParameters(ActorFrame frame) => {
  'ParamAngleX': frame.gazeX * 15,
  'ParamAngleY': -frame.gazeY * 12,
  'ParamAngleZ': frame.headTilt * 25,
  'ParamBodyAngleX': frame.bodyLean * 20,
  'ParamEyeBallX': frame.gazeX.clamp(-1.0, 1.0),
  'ParamEyeBallY': -frame.gazeY.clamp(-1.0, 1.0),
  'ParamEyeLOpen': (1.0 - frame.blink).clamp(0.0, 1.0),
  'ParamEyeROpen': (1.0 - frame.blink).clamp(0.0, 1.0),
  'ParamEyeLSmile': frame.smile.clamp(0.0, 1.0),
  'ParamEyeRSmile': frame.smile.clamp(0.0, 1.0),
  'ParamBrowLForm': -frame.browTension.clamp(0.0, 1.0),
  'ParamBrowRForm': -frame.browTension.clamp(0.0, 1.0),
  'ParamEyeBallForm': -frame.pupil.clamp(-1.0, 1.0),
  'ParamCheek': frame.blush.clamp(0.0, 1.0),
  'ParamBreath': frame.breath.clamp(0.0, 1.0),
  'ParamA': frame.mouthOpen.clamp(0.0, 1.0),
  'ParamMouthUp': frame.smile.clamp(0.0, 1.0),
  'ParamMouthDown': (-frame.smile).clamp(0.0, 1.0),
};

class Live2DActor extends StatefulWidget {
  const Live2DActor({
    super.key,
    required this.contact,
    required this.actor,
    required this.profile,
  });

  final Contact contact;
  final VirtualActor actor;
  final AiProfile profile;

  @override
  State<Live2DActor> createState() => _Live2DActorState();
}

class _Live2DActorState extends State<Live2DActor> {
  final _controller = Live2DViewController();
  Timer? _ticker;
  Future<void>? _inFlight;
  final _lastValues = <String, double>{};
  bool _disposed = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    unawaited(_load());
    // Cubism's own render loop remains smooth; parameter updates only need to
    // arrive at a modest rate to avoid flooding platform channels.
    _ticker = Timer.periodic(const Duration(milliseconds: 180), (_) {
      if (!_disposed && _inFlight == null && _controller.value.isLoaded) {
        _inFlight = _update();
        unawaited(_inFlight!.whenComplete(() => _inFlight = null));
      }
    });
  }

  void _onControllerChanged() {
    if (!_disposed && mounted && _controller.value.lastError != null) {
      setState(() => _failed = true);
    }
  }

  Future<void> _load() async {
    try {
      await _controller.whenAttached;
      if (!mounted || _disposed) return;
      final loaded = await _controller.loadModel(
        modelDir: _modelDir,
        modelFileName: _modelFile,
      );
      if (!_disposed && mounted && !loaded) setState(() => _failed = true);
    } catch (error) {
      debugPrint('Live2D model load failed: $error');
      if (!_disposed && mounted) setState(() => _failed = true);
    }
  }

  Future<void> _update() async {
    try {
      final values = maoParameters(widget.actor.tick(0.18));
      for (final entry in values.entries) {
        if (_disposed) return;
        final previous = _lastValues[entry.key];
        if (previous != null && (previous - entry.value).abs() < 0.025) {
          continue;
        }
        await _controller.setParameter(entry.key, entry.value);
        _lastValues[entry.key] = entry.value;
      }
    } catch (error) {
      debugPrint('Live2D parameter update failed: $error');
      if (!_disposed && mounted) setState(() => _failed = true);
    }
  }

  @override
  void didUpdateWidget(covariant Live2DActor oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.actor.updateProfile(widget.profile);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _controller.removeListener(_onControllerChanged);
    // The platform view is torn down by Live2DView. Let an in-flight channel
    // call finish first, then release the Dart controller without racing the
    // native view destruction during route pop.
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final supported =
        kIsWeb ||
        defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS;
    if (_failed || !supported || !widget.profile.expressionProfile.animationEnabled) {
      return Center(child: AppAvatar(contact: widget.contact, size: 130));
    }
    return Live2DView(controller: _controller);
  }
}
