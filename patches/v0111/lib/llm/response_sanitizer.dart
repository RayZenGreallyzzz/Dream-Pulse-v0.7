class ResponseSanitizer {
  const ResponseSanitizer._();

  static String finalOnly(String raw) {
    var text = raw.replaceAll('\u0000', '').trim();

    // Qwen-style hidden reasoning blocks.
    text = text.replaceAll(
      RegExp(r'<think>[\s\S]*?</think>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<reasoning>[\s\S]*?</reasoning>', caseSensitive: false),
      '',
    );
    text = text.replaceAll(
      RegExp(r'<analysis>[\s\S]*?</analysis>', caseSensitive: false),
      '',
    );

    // If generation was cut off while still inside a hidden block, do not
    // speak or display that partial chain-of-thought.
    final lower = text.toLowerCase();
    final openThink = lower.lastIndexOf('<think>');
    if (openThink >= 0 && lower.indexOf('</think>', openThink) < 0) {
      text = text.substring(0, openThink);
    }

    text = text
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .replaceAll(RegExp(r'^[ \t]+|[ \t]+$', multiLine: true), '')
        .trim();

    return text;
  }

  /// Keeps ordinary punctuation for TTS pauses/prosody, while stripping
  /// markup and standalone symbols that some Android voices pronounce aloud.
  static String forSpeech(String raw) {
    var text = finalOnly(raw);
    if (text.isEmpty) return '';

    text = text.replaceAll(
      RegExp(r'\x60\x60\x60[\s\S]*?\x60\x60\x60', multiLine: true),
      ' ',
    );

    text = text.replaceAllMapped(
      RegExp(r'\[([^\]]+)\]\((https?://[^\s)]+)\)'),
      (m) => m.group(1) ?? '',
    );

    text = text.replaceAll(
      RegExp(r'https?://\S+', caseSensitive: false),
      '',
    );

    text = text.replaceAllMapped(
      RegExp(r'\x60([^\x60]+)\x60'),
      (m) => m.group(1) ?? '',
    );

    text = text
        .replaceAll(RegExp(r'^\s{0,3}#{1,6}\s*', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*>+\s?', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*[-+*]\s+', multiLine: true), '')
        .replaceAll(RegExp(r'^\s*\d+[.)]\s+', multiLine: true), '');

    text = text
        .replaceAll('**', '')
        .replaceAll('__', '')
        .replaceAll('*', '')
        .replaceAll('_', ' ')
        .replaceAll('#', '')
        .replaceAll('|', ' ')
        .replaceAll('~', '')
        .replaceAll(String.fromCharCode(96), '')
        .replaceAll('\\\\', '');

    final sourceMatch = RegExp(
      r'\n\s*(источники|sources)\s*:?\s*\n',
      caseSensitive: false,
    ).firstMatch(text);
    if (sourceMatch != null) {
      text = text.substring(0, sourceMatch.start);
    }

    text = text
        .replaceAll(RegExp(r'[•▪◦◆◇■□►▶]+'), ' ')
        .replaceAll(RegExp(r'={2,}'), ' ')
        .replaceAll(RegExp(r'-{3,}'), ' ')
        .replaceAll(RegExp(r'[ \t]+'), ' ')
        .replaceAll(RegExp(r'\s*\n\s*'), '. ')
        .replaceAll(RegExp(r'\.{2,}'), '.')
        .replaceAll(RegExp(r'\s+([,.;:!?])'), r'$1')
        .replaceAll(RegExp(r'([!?]){2,}'), r'$1')
        .trim();

    text = text
        .split(' ')
        .where((part) => !RegExp(r'^[.,;:!?]+$').hasMatch(part))
        .join(' ')
        .trim();

    return text;
  }
}
