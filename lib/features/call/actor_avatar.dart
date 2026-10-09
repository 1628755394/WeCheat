import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/widgets/app_avatar.dart';
import '../../models/ai_profile.dart';
import '../../models/contact.dart';
import '../../services/virtual_actor.dart';

class ActorAvatar extends StatefulWidget {
  const ActorAvatar({
    super.key,
    required this.contact,
    required this.actor,
    required this.profile,
    this.size = 190,
  });

  final Contact contact;
  final VirtualActor actor;
  final AiProfile profile;
  final double size;

  @override
  State<ActorAvatar> createState() => _ActorAvatarState();
}

class _ActorAvatarState extends State<ActorAvatar> {
  Timer? _ticker;
  ActorFrame _frame = const ActorFrame();

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 50), (_) {
      if (mounted && widget.profile.expressionProfile.animationEnabled) {
        setState(() => _frame = widget.actor.tick(0.05));
      }
    });
  }

  @override
  void didUpdateWidget(covariant ActorAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.actor.updateProfile(widget.profile);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.profile.expressionProfile.animationEnabled;
    final movement = enabled ? _frame : const ActorFrame();
    final scale = 1 + movement.breath * 0.025;
    return SizedBox(
      width: widget.size + 36,
      height: widget.size + 40,
      child: Center(
        child: Transform.translate(
          offset: Offset(
            movement.gazeX * 8 + movement.bodyLean * 18,
            movement.breath * -3 + movement.gazeY * 5,
          ),
          child: Transform.rotate(
            angle: movement.headTilt * 0.15,
            child: Transform.scale(
              scale: scale,
              child: AppAvatar(
                contact: widget.contact,
                size: widget.size,
                radius: widget.size / 2,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
