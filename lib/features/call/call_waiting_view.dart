import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/widgets/app_avatar.dart';
import '../../models/contact.dart';

class CallWaitingView extends StatelessWidget {
  const CallWaitingView({
    super.key,
    required this.contact,
    required this.name,
    required this.isVideo,
    required this.animationsEnabled,
    required this.reducedEffects,
  });
  final Contact? contact;
  final String name;
  final bool isVideo;
  final bool animationsEnabled;
  final bool reducedEffects;

  @override
  Widget build(BuildContext context) => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contact != null)
            CallAvatar(
              contact: contact!,
              animationsEnabled: animationsEnabled,
              reducedEffects: reducedEffects,
            ),
          const SizedBox(height: 24),
          Text(
            name,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 24),
          ),
          const SizedBox(height: 14),
          Text(
            isVideo ? '等待对方接受视频通话邀请' : '等待对方接受语音通话邀请',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white70, fontSize: 15),
          ),
          const SizedBox(height: 24),
          _WaitingDots(animate: animationsEnabled && !reducedEffects),
        ],
      ),
    ),
  );
}

class CallAvatar extends StatefulWidget {
  const CallAvatar({
    super.key,
    required this.contact,
    required this.animationsEnabled,
    required this.reducedEffects,
  });
  final Contact contact;
  final bool animationsEnabled;
  final bool reducedEffects;

  @override
  State<CallAvatar> createState() => _CallAvatarState();
}

class _CallAvatarState extends State<CallAvatar> {
  Timer? _timer;
  final _clock = Stopwatch()..start();
  double _scale = 1;

  @override
  void initState() {
    super.initState();
    _configure();
  }

  void _configure() {
    _timer?.cancel();
    _scale = 1;
    if (!widget.animationsEnabled) return;
    _timer = Timer.periodic(
      Duration(milliseconds: widget.reducedEffects ? 250 : 80),
      (_) {
        if (!mounted) return;
        setState(
          () => _scale =
              1 +
              0.018 *
                  (1 + math.sin(_clock.elapsedMilliseconds / 1000 * math.pi)) /
                  2,
        );
      },
    );
  }

  @override
  void didUpdateWidget(covariant CallAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationsEnabled != widget.animationsEnabled ||
        oldWidget.reducedEffects != widget.reducedEffects) {
      _configure();
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    height: 150,
    child: Center(
      child: Transform.scale(
        scale: _scale,
        child: RepaintBoundary(
          child: AppAvatar(contact: widget.contact, size: 130, radius: 8),
        ),
      ),
    ),
  );
}

class _WaitingDots extends StatefulWidget {
  const _WaitingDots({required this.animate});
  final bool animate;
  @override
  State<_WaitingDots> createState() => _WaitingDotsState();
}

class _WaitingDotsState extends State<_WaitingDots>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  );
  @override
  void initState() {
    super.initState();
    if (widget.animate) _controller.repeat();
  }

  @override
  void didUpdateWidget(covariant _WaitingDots oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.animate) {
      _controller.repeat();
    } else {
      _controller.stop();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 64,
    height: 24,
    child: AnimatedBuilder(
      animation: _controller,
      builder: (_, _) => Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          for (var i = 0; i < 3; i++)
            Transform.translate(
              offset: Offset(
                0,
                widget.animate
                    ? -5 *
                          math.max(
                            0,
                            math.sin(
                              (_controller.value - i * 0.16) * 2 * math.pi,
                            ),
                          )
                    : 0,
              ),
              child: const DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white70,
                  shape: BoxShape.circle,
                ),
                child: SizedBox(width: 7, height: 7),
              ),
            ),
        ],
      ),
    ),
  );
}
