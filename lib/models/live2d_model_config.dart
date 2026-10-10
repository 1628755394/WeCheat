class Live2DModelConfig {
  const Live2DModelConfig({
    required this.directory,
    required this.fileName,
    required this.name,
    this.parameterIds = const [],
    this.motions = const [],
    this.actions = const [],
  });

  final String directory;
  final String fileName;
  final String name;
  final List<String> parameterIds;
  final List<Live2DMotion> motions;
  final List<CustomActorAction> actions;

  Live2DModelConfig withActions(List<CustomActorAction> actions) =>
      Live2DModelConfig(
        directory: directory,
        fileName: fileName,
        name: name,
        parameterIds: parameterIds,
        motions: motions,
        actions: actions,
      );

  Live2DMotion? motionFor(CustomActorAction action) {
    for (final motion in motions) {
      if (motion.group == action.group && motion.index == action.index) {
        return motion;
      }
    }
    return null;
  }

  CustomActorAction? matchAction(String text) {
    if (RegExp(r'停止|停下|别动|不要动|stop', caseSensitive: false).hasMatch(text) ||
        RegExp(r'不要|别|不用|不许').hasMatch(text)) {
      return null;
    }
    final query = text.trim().toLowerCase();
    // Exact names take precedence over a shorter trigger in another action.
    for (final action in actions) {
      if (action.name.toLowerCase() == query && motionFor(action) != null) {
        return action;
      }
    }
    for (final action in actions) {
      if (motionFor(action) != null &&
          [action.name, ...action.triggers].any(
            (word) =>
                word.trim().isNotEmpty && query.contains(word.toLowerCase()),
          )) {
        return action;
      }
    }
    return null;
  }

  Map<String, dynamic> toMap() => {
    'directory': directory,
    'fileName': fileName,
    'name': name,
    'parameterIds': parameterIds,
    'motions': motions.map((motion) => motion.toMap()).toList(),
    'actions': actions.map((action) => action.toMap()).toList(),
  };

  factory Live2DModelConfig.fromMap(Map map) => Live2DModelConfig(
    directory: map['directory'] as String,
    fileName: map['fileName'] as String,
    name: map['name'] as String,
    parameterIds: (map['parameterIds'] as List?)?.cast<String>() ?? const [],
    motions: [
      for (final item in map['motions'] as List? ?? [])
        Live2DMotion.fromMap(item as Map),
    ],
    actions: [
      for (final item in map['actions'] as List? ?? [])
        CustomActorAction.fromMap(item as Map),
    ],
  );
}

class Live2DMotion {
  const Live2DMotion({
    required this.group,
    required this.index,
    required this.fileName,
    required this.duration,
  });
  final String group;
  final int index;
  final String fileName;
  final double duration;
  String get label => '${group.isEmpty ? '默认' : group} · $fileName';
  Map<String, dynamic> toMap() => {
    'group': group,
    'index': index,
    'fileName': fileName,
    'duration': duration,
  };
  factory Live2DMotion.fromMap(Map map) => Live2DMotion(
    group: map['group'] as String,
    index: map['index'] as int,
    fileName: map['fileName'] as String,
    duration: (map['duration'] as num).toDouble(),
  );
}

class CustomActorAction {
  const CustomActorAction({
    required this.id,
    required this.name,
    required this.group,
    required this.index,
    this.triggers = const [],
    this.speed = 1,
  });
  final String id;
  final String name;
  final String group;
  final int index;
  final List<String> triggers;
  final double speed;
  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'group': group,
    'index': index,
    'triggers': triggers,
    'speed': speed,
  };
  factory CustomActorAction.fromMap(Map map) => CustomActorAction(
    id: map['id'] as String,
    name: map['name'] as String,
    group: map['group'] as String,
    index: map['index'] as int,
    triggers: (map['triggers'] as List?)?.cast<String>() ?? [],
    speed: ((map['speed'] as num?)?.toDouble() ?? 1).clamp(0.5, 2),
  );
}
