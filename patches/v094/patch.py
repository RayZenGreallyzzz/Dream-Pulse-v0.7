from pathlib import Path

# Stream the local model into the visible assistant message without bypassing
# Dream Pulse Core. UI updates are throttled so 4 GB Android devices do not
# rebuild on every tiny token.
p = Path('lib/ui/assistant_page.dart')
s = p.read_text()

old = """      final answer = await widget.core.ask(
        text,
        thinking: thinking,
        allowWeb: allowWeb,
      );
      if (!mounted) return;
      setState(() {
        messages.add(_Message(false, answer));
        status = '${widget.brain.lastBackend} · ${widget.core.status}';
      });
      if (autoSpeak) await widget.speech.speak(answer, expression: widget.core.personality.voiceExpression);
"""

new = """      final answerBuffer = StringBuffer();
      var assistantIndex = -1;
      var lastPaint = DateTime.fromMillisecondsSinceEpoch(0);

      await for (final chunk in widget.core.askStream(
        text,
        thinking: thinking,
        allowWeb: allowWeb,
      )) {
        answerBuffer.write(chunk);
        if (!mounted) return;

        final now = DateTime.now();
        final shouldPaint =
            now.difference(lastPaint).inMilliseconds >= 50 ||
            chunk.endsWith('.') ||
            chunk.endsWith('!') ||
            chunk.endsWith('?') ||
            chunk.contains('\\n');
        if (!shouldPaint) continue;

        final partial = answerBuffer.toString();
        setState(() {
          if (assistantIndex < 0) {
            assistantIndex = messages.length;
            messages.add(_Message(false, partial));
          } else {
            messages[assistantIndex] = _Message(false, partial);
          }
          status = '${widget.brain.lastBackend} · ${widget.core.status}';
        });
        lastPaint = now;
      }

      final answer = answerBuffer.toString().trim();
      if (!mounted) return;
      if (answer.isNotEmpty) {
        setState(() {
          if (assistantIndex < 0) {
            messages.add(_Message(false, answer));
          } else {
            messages[assistantIndex] = _Message(false, answer);
          }
          status = '${widget.brain.lastBackend} · ${widget.core.status}';
        });
        if (autoSpeak) {
          await widget.speech.speak(
            answer,
            expression: widget.core.personality.voiceExpression,
          );
        }
      }
"""

if old not in s:
    raise SystemExit('assistant_page: current core ask block not found')
s = s.replace(old, new, 1)

old_catch = """    } catch (e) {
      if (!mounted) return;
      setState(() {
        messages.add(_Message(false, 'Ошибка: $e'));
        status = 'ошибка';
      });
    } finally {
"""

new_catch = """    } catch (e) {
      if (!mounted) return;
      if (e.toString().contains('GENERATION_CANCELLED')) {
        setState(() => status = 'Остановлено');
      } else {
        setState(() {
          messages.add(_Message(false, 'Ошибка: $e'));
          status = 'ошибка';
        });
      }
    } finally {
"""

if old_catch not in s:
    raise SystemExit('assistant_page: catch block not found')
s = s.replace(old_catch, new_catch, 1)

s = s.replace('v0.9.3 BAYA', 'v0.9.4 STREAM')
s = s.replace('v0.9.3', 'v0.9.4')
p.write_text(s)

# Keep the complete RuVoice model intact, but hide the two stock male speakers
# from Dream Pulse. Unknown extra-pack voices stay visible rather than being
# guessed by name.
p = Path('lib/avatar/speech_controller.dart')
s = p.read_text()

s = s.replace(
    "    if (ruVoiceActive) return 'BAYA LOCAL · RuVoice';",
    "    if (ruVoiceActive) return '${selectedVoice?.label ?? 'Baya'} · RuVoice';",
    1,
)

anchor = """      options.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));
      voiceOptions = options;
"""
replacement = """      if (ruVoiceActive) {
        const hiddenStockMale = {'aidar-ru', 'eugene-ru'};
        options.removeWhere(
          (voice) => hiddenStockMale.contains(voice.name.toLowerCase()),
        );
      }

      options.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));
      voiceOptions = options;
"""
if anchor not in s:
    raise SystemExit('speech_controller: voice sort anchor not found')
s = s.replace(anchor, replacement, 1)
p.write_text(s)

for path in ['lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    s = p.read_text().replace('v0.9.3 BAYA', 'v0.9.4 STREAM').replace('v0.9.3', 'v0.9.4')
    p.write_text(s)
