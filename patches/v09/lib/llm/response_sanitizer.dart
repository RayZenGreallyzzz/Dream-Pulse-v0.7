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
}
