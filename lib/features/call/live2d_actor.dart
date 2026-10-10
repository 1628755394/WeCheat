import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:live2d_flutter/live2d_flutter.dart';

import '../../core/widgets/app_avatar.dart';
import '../../models/ai_profile.dart';
import '../../models/contact.dart';
import '../../services/virtual_actor.dart';
import 'mao_actions.dart';

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
    this.onUnavailable,
    this.onReady,
    this.onInteraction,
  });

  final Contact contact;
  final VirtualActor actor;
  final AiProfile profile;
  final VoidCallback? onUnavailable;
  final VoidCallback? onReady;
  final VoidCallback? onInteraction;

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
  bool _loaded = false;
  bool _readyNotified = false;
  int _lastActionVersion = 0;
  ActorAction? _activeAction;
  final _actionClock = Stopwatch();
  final _actionKeys = <String>{};
  double? _customDuration;
  bool _switchingMotion = false;
  Future<void> _motionTransition = Future<void>.value();
  int? _pointer;
  Offset? _pointerStart;
  Offset? _pointerGaze;
  bool _pointerDragged = false;

  void _pointerDown(PointerDownEvent event, Size size) {
    if (!_loaded || _disposed || _pointer != null) return;
    _pointer = event.pointer;
    _pointerStart = event.localPosition;
    _pointerDragged = false;
    _followPointer(event.localPosition, size);
    widget.onInteraction?.call();
  }

  void _followPointer(Offset position, Size size) {
    if (size.isEmpty) return;
    _pointerGaze = Offset(
      (position.dx / size.width * 2 - 1).clamp(-1.0, 1.0),
      (position.dy / size.height * 2 - 1).clamp(-1.0, 1.0),
    );
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer != _pointer) return;
    final tapped =
        !_pointerDragged &&
        (event.localPosition - _pointerStart!).distance <= 12;
    _pointer = null;
    _pointerStart = null;
    _pointerGaze = null;
    if (!tapped || !_loaded || _disposed) return;
    widget.actor.react(ActorEvent.compliment);
    final ids = widget.profile.live2dModel!.parameterIds;
    for (final action in [ActorAction.wink, ActorAction.nod]) {
      if (supportsModelAction(ids, action)) {
        widget.actor.requestAction(action);
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onControllerChanged);
    widget.actor.addListener(_onActorChanged);
    unawaited(_load());
    // Cubism's own render loop remains smooth; parameter updates only need to
    // arrive at a modest rate to avoid flooding platform channels.
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (!_disposed && _inFlight == null && _controller.value.isLoaded) {
        _inFlight = _update();
        unawaited(_inFlight!.whenComplete(() => _inFlight = null));
      }
    });
  }

  void _onActorChanged() {
    if (_disposed || !_controller.value.isLoaded) return;
    final version = widget.actor.actionVersion;
    if (version == _lastActionVersion) return;
    _lastActionVersion = version;
    _motionTransition = _motionTransition.then((_) => _switchAction(version));
  }

  Future<void> _switchAction(int version) async {
    _switchingMotion = true;
    try {
      final pending = _inFlight;
      if (pending != null) await pending;
      if (_disposed || version != widget.actor.actionVersion) return;
      final custom = widget.actor.requestedCustomAction;
      final action = widget.actor.requestedAction;
      await _controller.stopMotions();
      if (_disposed || version != widget.actor.actionVersion) return;
      _lastValues.clear();
      _actionKeys.clear();
      _activeAction = action == ActorAction.stop ? null : action;
      _customDuration = null;
      if (custom != null) {
        final motion = widget.profile.live2dModel!.motionFor(custom);
        if (motion != null) {
          await _controller.setMotionSpeed(custom.speed);
          if (_disposed) return;
          await _controller.startMotion(
            group: motion.group,
            index: motion.index,
            priority: 3,
          );
          _customDuration = motion.duration / custom.speed;
        }
      }
      _actionClock
        ..reset()
        ..start();
    } catch (error) {
      debugPrint('Live2D action failed: $error');
    } finally {
      _switchingMotion = false;
    }
  }

  void _onControllerChanged() {
    if (_disposed || !mounted) return;
    final loaded = _controller.value.isLoaded;
    final failed = _controller.value.lastError != null;
    if (loaded != _loaded || failed != _failed) {
      setState(() {
        _loaded = loaded;
        _failed = failed;
      });
    }
    if (loaded) _onActorChanged();
    if (loaded && !_readyNotified) {
      _readyNotified = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) widget.onReady?.call();
      });
    }
    if (failed) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_disposed) widget.onUnavailable?.call();
      });
    }
  }

  Future<void> _load() async {
    try {
      await _controller.whenAttached;
      if (!mounted || _disposed) return;
      final loaded = await _controller.loadModel(
        modelDir: widget.profile.live2dModel!.directory,
        modelFileName: widget.profile.live2dModel!.fileName,
      );
      if (!_disposed && mounted && !loaded) setState(() => _failed = true);
      if (!_disposed && mounted && !loaded) widget.onUnavailable?.call();
    } catch (error) {
      debugPrint('Live2D model load failed: $error');
      if (!_disposed && mounted) setState(() => _failed = true);
      if (!_disposed && mounted) widget.onUnavailable?.call();
    }
  }

  Future<void> _update() async {
    try {
      if (_switchingMotion) return;
      if (_customDuration != null &&
          _actionClock.elapsedMicroseconds / 1000000 >= _customDuration!) {
        _customDuration = null;
        await _controller.stopMotions();
        _lastValues.clear();
      }
      final values = maoParameters(widget.actor.tick(0.05));
      final gaze = _pointerGaze;
      if (gaze != null) {
        values.addAll({
          'ParamAngleX': gaze.dx * 25,
          'ParamAngleY': -gaze.dy * 20,
          'ParamEyeBallX': gaze.dx,
          'ParamEyeBallY': -gaze.dy,
        });
      }
      if (_customDuration != null) {
        values.removeWhere((key, _) => key != 'ParamA');
      }
      if (widget.profile.live2dModel!.parameterIds.contains(
        'ParamMouthOpenY',
      )) {
        values['ParamMouthOpenY'] = values.remove('ParamA')!;
      }
      // Reset parameters owned by the previous command before blending the
      // next command. Normal breathing and speech keep running independently.
      for (final key in _actionKeys) {
        values.putIfAbsent(key, () => 0);
      }
      final action = _activeAction;
      if (action != null) {
        final seconds = _actionClock.elapsedMicroseconds / 1000000;
        final command = maoActionParameters(action, seconds);
        _actionKeys.addAll(command.keys);
        values.addAll(command);
        if (seconds >= maoActionDuration(action)) _activeAction = null;
      }
      for (final entry in values.entries) {
        if (!widget.profile.live2dModel!.parameterIds.contains(entry.key)) {
          continue;
        }
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
    if (oldWidget.actor != widget.actor) {
      oldWidget.actor.removeListener(_onActorChanged);
      _lastActionVersion = 0;
      widget.actor.addListener(_onActorChanged);
    }
    widget.actor.updateProfile(widget.profile);
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    widget.actor.removeListener(_onActorChanged);
    _controller.removeListener(_onControllerChanged);
    // Live2DView owns native teardown; the controller guards late callbacks.
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
    if (_failed ||
        !supported ||
        !widget.profile.expressionProfile.animationEnabled) {
      return Center(child: AppAvatar(contact: widget.contact, size: 130));
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        Live2DView(controller: _controller),
        if (_loaded)
          LayoutBuilder(
            builder: (context, constraints) => Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (event) =>
                  _pointerDown(event, constraints.biggest),
              onPointerMove: (event) {
                if (event.pointer != _pointer) return;
                if ((event.localPosition - _pointerStart!).distance > 12) {
                  _pointerDragged = true;
                }
                _followPointer(event.localPosition, constraints.biggest);
              },
              onPointerUp: _pointerUp,
              onPointerCancel: (event) {
                if (event.pointer != _pointer) return;
                _pointer = null;
                _pointerStart = null;
                _pointerGaze = null;
              },
              child: const SizedBox.expand(),
            ),
          ),
        if (!_loaded)
          Center(child: AppAvatar(contact: widget.contact, size: 130)),
      ],
    );
  }
}
