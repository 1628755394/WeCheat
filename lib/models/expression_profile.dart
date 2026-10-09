class ExpressionProfile {
  final double emotionSensitivity;
  final double reactionSpeed;
  final double blinkBaseRate;
  final double breathSpeedBase;
  final double gazeWanderAmount;
  final double bodyMovementIntensity;
  final bool memoryEmotionTrigger;
  final bool animationEnabled;

  const ExpressionProfile({
    this.emotionSensitivity = 0.65,
    this.reactionSpeed = 0.7,
    this.blinkBaseRate = 0.3,
    this.breathSpeedBase = 0.4,
    this.gazeWanderAmount = 0.45,
    this.bodyMovementIntensity = 0.5,
    this.memoryEmotionTrigger = true,
    this.animationEnabled = true,
  });

  factory ExpressionProfile.fromMap(Map? map) {
    double value(String key, double fallback) =>
        ((map?[key] as num?)?.toDouble() ?? fallback).clamp(0.0, 1.0);
    return ExpressionProfile(
      emotionSensitivity: value('emotionSensitivity', 0.65),
      reactionSpeed: value('reactionSpeed', 0.7),
      blinkBaseRate: value('blinkBaseRate', 0.3),
      breathSpeedBase: value('breathSpeedBase', 0.4),
      gazeWanderAmount: value('gazeWanderAmount', 0.45),
      bodyMovementIntensity: value('bodyMovementIntensity', 0.5),
      memoryEmotionTrigger: map?['memoryEmotionTrigger'] as bool? ?? true,
      animationEnabled: map?['animationEnabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() => {
    'emotionSensitivity': emotionSensitivity,
    'reactionSpeed': reactionSpeed,
    'blinkBaseRate': blinkBaseRate,
    'breathSpeedBase': breathSpeedBase,
    'gazeWanderAmount': gazeWanderAmount,
    'bodyMovementIntensity': bodyMovementIntensity,
    'memoryEmotionTrigger': memoryEmotionTrigger,
    'animationEnabled': animationEnabled,
  };

  ExpressionProfile copyWith({
    double? emotionSensitivity,
    double? reactionSpeed,
    double? blinkBaseRate,
    double? breathSpeedBase,
    double? gazeWanderAmount,
    double? bodyMovementIntensity,
    bool? memoryEmotionTrigger,
    bool? animationEnabled,
  }) => ExpressionProfile(
    emotionSensitivity: emotionSensitivity ?? this.emotionSensitivity,
    reactionSpeed: reactionSpeed ?? this.reactionSpeed,
    blinkBaseRate: blinkBaseRate ?? this.blinkBaseRate,
    breathSpeedBase: breathSpeedBase ?? this.breathSpeedBase,
    gazeWanderAmount: gazeWanderAmount ?? this.gazeWanderAmount,
    bodyMovementIntensity: bodyMovementIntensity ?? this.bodyMovementIntensity,
    memoryEmotionTrigger: memoryEmotionTrigger ?? this.memoryEmotionTrigger,
    animationEnabled: animationEnabled ?? this.animationEnabled,
  );
}
