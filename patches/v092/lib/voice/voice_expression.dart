class VoiceExpression {
  const VoiceExpression({
    required this.rate,
    required this.pitch,
    this.volume = 1.0,
    this.neuralStability = 0.50,
    this.neuralSimilarity = 0.84,
    this.neuralStyle = 0.06,
    this.neuralSpeed = 1.0,
    this.neuralCue = '',
  });

  /// flutter_tts fallback rate. Kept deliberately conservative.
  final double rate;
  final double pitch;
  final double volume;

  /// ElevenLabs request-level expression. These alter delivery, not identity.
  final double neuralStability;
  final double neuralSimilarity;
  final double neuralStyle;
  final double neuralSpeed;

  /// Optional Eleven v3 audio tag, for example `[happily] ` or `[sad] `.
  /// Never shown in chat; it is only sent to the neural voice renderer.
  final String neuralCue;
}
