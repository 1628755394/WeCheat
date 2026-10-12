enum MoodZone { calm, mild, quarrel, distant, fuse }

class MoodState {
  final double valence;
  final double arousal;
  final DateTime updatedAt;
  final DateTime? lastNegativeAt;
  final String lastEvent;
  final int repeatedNegativeEvents;
  final int neutralTurns;
  final int quarrelReplies;

  MoodState({
    this.valence = 0,
    this.arousal = 0.3,
    DateTime? updatedAt,
    this.lastNegativeAt,
    this.lastEvent = '初始状态',
    this.repeatedNegativeEvents = 0,
    this.neutralTurns = 0,
    this.quarrelReplies = 0,
  }) : updatedAt = updatedAt ?? DateTime.now();

  MoodZone zone(int affinity) {
    final v = double.parse(valence.toStringAsFixed(3));
    final a = double.parse(arousal.toStringAsFixed(3));
    if (v < -0.7 && a > 0.7) return MoodZone.fuse;
    if (v >= -0.7 && v <= -0.3 && a >= 0.6 && a <= 0.9) {
      return affinity < 30 ? MoodZone.distant : MoodZone.quarrel;
    }
    if (v >= -0.3 && v <= -0.1 && a >= 0.4 && a <= 0.6) {
      return MoodZone.mild;
    }
    return MoodZone.calm;
  }

  String get emoji => switch (zone(70)) {
    MoodZone.quarrel => '😒',
    MoodZone.distant => '🙁',
    MoodZone.fuse => '😔',
    MoodZone.mild => '🙁',
    _ => '🙂',
  };

  MoodState copyWith({
    double? valence,
    double? arousal,
    DateTime? updatedAt,
    DateTime? lastNegativeAt,
    String? lastEvent,
    int? repeatedNegativeEvents,
    int? neutralTurns,
    int? quarrelReplies,
  }) => MoodState(
    valence: (valence ?? this.valence).clamp(-1.0, 1.0),
    arousal: (arousal ?? this.arousal).clamp(0.0, 1.0),
    updatedAt: updatedAt ?? this.updatedAt,
    lastNegativeAt: lastNegativeAt ?? this.lastNegativeAt,
    lastEvent: lastEvent ?? this.lastEvent,
    repeatedNegativeEvents:
        repeatedNegativeEvents ?? this.repeatedNegativeEvents,
    neutralTurns: neutralTurns ?? this.neutralTurns,
    quarrelReplies: quarrelReplies ?? this.quarrelReplies,
  );

  Map<String, Object?> toMap() => {
    'valence': valence,
    'arousal': arousal,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
    'lastNegativeAt': lastNegativeAt?.millisecondsSinceEpoch,
    'lastEvent': lastEvent,
    'repeatedNegativeEvents': repeatedNegativeEvents,
    'neutralTurns': neutralTurns,
    'quarrelReplies': quarrelReplies,
  };

  factory MoodState.fromMap(Map raw) => MoodState(
    valence: (raw['valence'] as num?)?.toDouble() ?? 0,
    arousal: (raw['arousal'] as num?)?.toDouble() ?? 0.3,
    updatedAt: DateTime.fromMillisecondsSinceEpoch(
      raw['updatedAt'] as int? ?? DateTime.now().millisecondsSinceEpoch,
    ),
    lastNegativeAt: raw['lastNegativeAt'] is int
        ? DateTime.fromMillisecondsSinceEpoch(raw['lastNegativeAt'] as int)
        : null,
    lastEvent: raw['lastEvent'] as String? ?? '初始状态',
    repeatedNegativeEvents: raw['repeatedNegativeEvents'] as int? ?? 0,
    neutralTurns: raw['neutralTurns'] as int? ?? 0,
    quarrelReplies: raw['quarrelReplies'] as int? ?? 0,
  );
}
