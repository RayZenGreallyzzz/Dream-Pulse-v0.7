from pathlib import Path

p = Path('lib/ui/assistant_page.dart')
s = p.read_text()

s = s.replace(
    "  Future<void> _showVoiceSheet() async {\n    await widget.speech.refreshVoices();",
    "  Future<void> _showVoiceSheet() async {\n    await widget.speech.refreshEngines();\n    await widget.speech.refreshVoices();",
    1,
)

old = """                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10141C),
                          border: Border.all(
                            color: widget.speech.neuralEnabled
                                ? const Color(0xFFFF641A)
                                : const Color(0xFF343A48),
                          ),
                        ),
"""

local_panel = """                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10141C),
                          border: Border.all(
                            color: widget.speech.ruVoiceActive
                                ? const Color(0xFF39D98A)
                                : const Color(0xFF343A48),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  color: widget.speech.ruVoiceAvailable
                                      ? const Color(0xFF39D98A)
                                      : const Color(0xFF687082),
                                ),
                                const SizedBox(width: 7),
                                const Expanded(
                                  child: Text(
                                    'LOCAL // SILERO BAYA',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .9),
                                  ),
                                ),
                                if (widget.speech.ruVoiceActive)
                                  const Text('ACTIVE', style: TextStyle(fontSize: 9, color: Color(0xFF39D98A), letterSpacing: .8)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              widget.speech.ruVoiceAvailable
                                  ? 'RuVoice найден · офлайн · без API · speaker baya-ru'
                                  : 'RuVoice TTS не установлен. После установки Dream Pulse увидит его автоматически.',
                              style: const TextStyle(fontSize: 9, color: Color(0xFF9CA6B8), letterSpacing: .4),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: !widget.speech.ruVoiceAvailable
                                        ? null
                                        : () async {
                                            try {
                                              await widget.speech.useRuVoiceBaya();
                                              if (sheetContext.mounted) setSheetState(() {});
                                              if (mounted) setState(() {});
                                            } catch (_) {}
                                          },
                                    icon: const Icon(Icons.record_voice_over_outlined, size: 17),
                                    label: const Text('USE BAYA'),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: !widget.speech.ruVoiceAvailable
                                      ? null
                                      : () async {
                                          try {
                                            await widget.speech.previewBaya();
                                            if (sheetContext.mounted) setSheetState(() {});
                                          } catch (_) {}
                                        },
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  label: const Text('TEST'),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton(
                                  onPressed: widget.speech.ruVoiceActive
                                      ? () async {
                                          await widget.speech.useDefaultSystemVoice();
                                          if (sheetContext.mounted) setSheetState(() {});
                                          if (mounted) setState(() {});
                                        }
                                      : null,
                                  child: const Text('SYSTEM'),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10141C),
                          border: Border.all(
                            color: widget.speech.neuralEnabled
                                ? const Color(0xFFFF641A)
                                : const Color(0xFF343A48),
                          ),
                        ),
"""

if old not in s:
    raise SystemExit('assistant_page: neural panel anchor not found')
s = s.replace(old, local_panel, 1)

s = s.replace(
    'Живой neural voice + автоматический системный fallback',
    'Baya local offline + optional neural + system fallback',
)
s = s.replace('v0.9.2 NEURAL', 'v0.9.3 BAYA')
s = s.replace('v0.9.2', 'v0.9.3')
p.write_text(s)

p = Path('lib/ui/assistant_shell.dart')
s = p.read_text().replace('v0.9.2 NEURAL', 'v0.9.3 BAYA').replace('v0.9.2', 'v0.9.3')
p.write_text(s)

p = Path('lib/ui/launch_gate.dart')
s = p.read_text().replace('v0.9.2', 'v0.9.3')
p.write_text(s)
