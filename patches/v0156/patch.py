"""v0.15.6: preserve Irina, surface native crash diagnostics.

Do not touch Dream Pulse Core, the Irina weights, the custom voice dataset,
or the experimental Silero work.
"""
from pathlib import Path

p = Path("pubspec.yaml")
raw = p.read_text(encoding="utf-8")
marker = "version: 0.15.5+39"
if raw.count(marker) != 1:
    raise RuntimeError("Expected a v0.15.5 Android baseline")
p.write_text(raw.replace(marker, "version: 0.15.6+40", 1), encoding="utf-8")

p = Path("lib/voice/dream_pulse_voice_backend.dart")
raw = p.read_text(encoding="utf-8")
def once(old, new):
    global raw
    count = raw.count(old)
    if count != 1:
        raise RuntimeError(f"Voice backend patch anchor count={count}: {old[:80]!r}")
    raw = raw.replace(old, new, 1)

once(
    """          throw TimeoutException(
            'Dream Voice не ответил. Последний этап: $stage',
          );""",
    """          final exit = state['voiceExit']?.toString() ?? 'unknown';
          throw TimeoutException(
            'Dream Voice не ответил. Последний этап: $stage; '
            'процесс: $exit',
          );""",
)
once(
    """      throw StateError('${e.message ?? e.code} · этап: $stage');""",
    """      final exit = state['voiceExit']?.toString() ?? 'unknown';
      throw StateError(
        '${e.message ?? e.code} · этап: $stage · процесс: $exit',
      );""",
)
once(
    """  Future<void> stop() async {
    speaking = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }""",
    """  Future<void> stop() async {
    // SpeechController calls stop() before EVERY utterance. Starting a
    // service only to stop an idle engine unnecessarily churned the
    // isolated :voice process and could race with the next SPEAK intent.
    final wasSpeaking = speaking;
    speaking = false;
    if (!wasSpeaking) return;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }""",
)
p.write_text(raw, encoding="utf-8")
