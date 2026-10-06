from pathlib import Path

p = Path('lib/ui/assistant_page.dart')
s = p.read_text()

# If a new turn starts while the previous voice is still speaking, stop only
# the voice first. The model itself is already free at this point.
needle = "    if (text.isEmpty || busy) return;\n\n"
if needle not in s:
    raise SystemExit('assistant_page: send guard not found')
s = s.replace(
    needle,
    "    if (text.isEmpty || busy) return;\n\n    await widget.speech.stop();\n\n",
    1,
)

# Do not keep the assistant/model busy until TTS completes. Speech is launched
# after the final text is ready and runs independently. Dialog mode re-arms
# the microphone only when that speech future finishes and no new turn began.
old = """        if (autoSpeak) {
          await widget.speech.speak(
            answer,
            expression: widget.core.personality.voiceExpression,
          );
        }
      }
      if (dialogMode && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        await widget.voiceInput.start(onFinal: (spoken) {
          input.text = spoken;
          _send(textOverride: spoken);
        });
      }
"""

new = """        if (autoSpeak) {
          final speechFuture = widget.speech.speak(
            answer,
            expression: widget.core.personality.voiceExpression,
          );
          if (dialogMode) {
            speechFuture.then((_) async {
              if (!mounted || busy || !dialogMode) return;
              await Future<void>.delayed(const Duration(milliseconds: 250));
              if (!mounted || busy || !dialogMode) return;
              await widget.voiceInput.start(onFinal: (spoken) {
                input.text = spoken;
                _send(textOverride: spoken);
              });
            }).catchError((_) {});
          } else {
            speechFuture.catchError((_) {});
          }
        } else if (dialogMode && mounted && !busy) {
          await widget.voiceInput.start(onFinal: (spoken) {
            input.text = spoken;
            _send(textOverride: spoken);
          });
        }
      }
"""

if old not in s:
    raise SystemExit('assistant_page: speech/dialog block not found')
s = s.replace(old, new, 1)

# Human-facing voice labels: no internal LOCAL/LOAD-style wording.
s = s.replace('LOCAL // SILERO BAYA', 'ГОЛОС // BAYA')
s = s.replace('USE BAYA', 'BAYA')
s = s.replace(
    'RuVoice найден · офлайн · без API · speaker baya-ru',
    'Baya · офлайн · RuVoice',
)
s = s.replace(
    'RuVoice TTS не установлен. После установки Dream Pulse увидит его автоматически.',
    'RuVoice не найден. Установи движок один раз — Dream Pulse выберет Baya автоматически.',
)
s = s.replace(
    'Baya local offline + optional neural + system fallback',
    'Локальный женский голос RuVoice',
)

s = s.replace('v0.9.4 STREAM', 'v0.9.5 FIX')
s = s.replace('v0.9.4', 'v0.9.5')
p.write_text(s)

for path in ['lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    s = p.read_text().replace('v0.9.4 STREAM', 'v0.9.5 FIX').replace('v0.9.4', 'v0.9.5')
    p.write_text(s)
