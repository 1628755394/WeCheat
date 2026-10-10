import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

class CallPerformance {
  const CallPerformance({
    this.animationsEnabled = true,
    this.reducedEffects = false,
  });
  final bool animationsEnabled;
  final bool reducedEffects;
  bool get rendersModel => animationsEnabled && !reducedEffects;
}

class CallPerformanceNotifier extends Notifier<CallPerformance> {
  Future<void>? _loading;

  @override
  CallPerformance build() {
    _loading = _load();
    return const CallPerformance();
  }

  Future<void> ensureLoaded() => _loading!;

  Future<void> _load() async {
    final box = await Hive.openBox('app_settings');
    state = CallPerformance(
      animationsEnabled: box.get('callAnimations', defaultValue: true) as bool,
    );
  }

  Future<void> select(bool enabled) async {
    await ensureLoaded();
    state = CallPerformance(animationsEnabled: enabled);
    await Hive.box('app_settings').put('callAnimations', enabled);
  }

  void reduceEffects() {
    if (state.reducedEffects) return;
    state = CallPerformance(
      animationsEnabled: state.animationsEnabled,
      reducedEffects: true,
    );
  }
}

final callPerformanceProvider =
    NotifierProvider<CallPerformanceNotifier, CallPerformance>(
      CallPerformanceNotifier.new,
    );
