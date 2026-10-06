class VoiceExpression {
  const VoiceExpression({
    required this.rate,
    required this.pitch,
    this.volume = 1.0,
  });

  /// flutter_tts speech rate. Deliberately conservative to keep speech natural.
  final double rate;
  final double pitch;
  final double volume;
}
