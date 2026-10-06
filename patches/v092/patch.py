from pathlib import Path

# Personality -> neural delivery profile. Identity remains in the selected
# ElevenLabs voice; mood only changes delivery within conservative bounds.
p = Path('lib/personality/personality_engine.dart')
s = p.read_text()
old = '''  VoiceExpression get voiceExpression {
    return switch (_state.mood) {
      Mood.playful => const VoiceExpression(rate: 0.50, pitch: 0.98),
      Mood.cheeky => const VoiceExpression(rate: 0.51, pitch: 0.96),
      Mood.warm => const VoiceExpression(rate: 0.46, pitch: 0.98),
      Mood.thoughtful => const VoiceExpression(rate: 0.44, pitch: 0.96),
      Mood.blue => const VoiceExpression(rate: 0.43, pitch: 0.94),
      Mood.energetic => const VoiceExpression(rate: 0.52, pitch: 1.00),
      Mood.calm => const VoiceExpression(rate: 0.47, pitch: 0.97),
    };
  }
'''
new = '''  VoiceExpression get voiceExpression {
    return switch (_state.mood) {
      Mood.playful => const VoiceExpression(
          rate: 0.50,
          pitch: 0.98,
          neuralStability: 0.38,
          neuralSimilarity: 0.84,
          neuralStyle: 0.16,
          neuralSpeed: 1.04,
          neuralCue: '[happily]',
        ),
      Mood.cheeky => const VoiceExpression(
          rate: 0.51,
          pitch: 0.96,
          neuralStability: 0.40,
          neuralSimilarity: 0.86,
          neuralStyle: 0.14,
          neuralSpeed: 1.02,
        ),
      Mood.warm => const VoiceExpression(
          rate: 0.46,
          pitch: 0.98,
          neuralStability: 0.52,
          neuralSimilarity: 0.88,
          neuralStyle: 0.07,
          neuralSpeed: 0.96,
        ),
      Mood.thoughtful => const VoiceExpression(
          rate: 0.44,
          pitch: 0.96,
          neuralStability: 0.58,
          neuralSimilarity: 0.86,
          neuralStyle: 0.04,
          neuralSpeed: 0.94,
        ),
      Mood.blue => const VoiceExpression(
          rate: 0.43,
          pitch: 0.94,
          neuralStability: 0.56,
          neuralSimilarity: 0.86,
          neuralStyle: 0.06,
          neuralSpeed: 0.92,
          neuralCue: '[sad]',
        ),
      Mood.energetic => const VoiceExpression(
          rate: 0.52,
          pitch: 1.00,
          neuralStability: 0.36,
          neuralSimilarity: 0.82,
          neuralStyle: 0.16,
          neuralSpeed: 1.07,
          neuralCue: '[happily]',
        ),
      Mood.calm => const VoiceExpression(
          rate: 0.47,
          pitch: 0.97,
          neuralStability: 0.50,
          neuralSimilarity: 0.86,
          neuralStyle: 0.05,
          neuralSpeed: 0.98,
        ),
    };
  }
'''
if old not in s:
    raise SystemExit('personality_engine: voiceExpression block not found')
s = s.replace(old, new, 1)
p.write_text(s)

# Replace the simple Android TTS chooser with a two-tier voice console:
# ElevenLabs neural voice first, Android TTS as an automatic fallback.
p = Path('lib/ui/assistant_page.dart')
s = p.read_text()
start = s.find('  Future<void> _showVoiceSheet() async {')
end = s.find('  Future<void> _toggleMic() async {', start)
if start < 0 or end < 0:
    raise SystemExit('assistant_page: voice sheet method not found')

method = r'''  Future<void> _showVoiceSheet() async {
    await widget.speech.refreshVoices();
    if (!mounted) return;

    final apiKey = TextEditingController();
    final voiceId = TextEditingController(text: widget.speech.neuralVoiceId);
    var neuralVoices = widget.speech.neuralVoiceOptions;
    var busyVoice = false;
    var message = widget.speech.neuralStatus;

    try {
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        backgroundColor: const Color(0xFF0D1016),
        builder: (sheetContext) => StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> connectNeural() async {
              if (busyVoice) return;
              setSheetState(() {
                busyVoice = true;
                message = 'CONNECTING ELEVENLABS...';
              });
              try {
                if (apiKey.text.trim().isNotEmpty) {
                  await widget.speech.saveNeuralApiKey(apiKey.text);
                  apiKey.clear();
                }
                if (voiceId.text.trim().isNotEmpty &&
                    voiceId.text.trim() != widget.speech.neuralVoiceId) {
                  await widget.speech.selectNeuralVoiceId(voiceId.text);
                }
                neuralVoices = await widget.speech.loadNeuralVoices();
                message = widget.speech.neuralStatus;
              } catch (e) {
                message = 'ERROR · ${e.toString().replaceFirst('Exception: ', '')}';
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => busyVoice = false);
                }
              }
            }

            Future<void> testNeural() async {
              if (busyVoice) return;
              setSheetState(() {
                busyVoice = true;
                message = 'NEURAL TEST...';
              });
              try {
                await widget.speech.testNeuralVoice();
                message = widget.speech.neuralStatus;
              } catch (e) {
                message = 'ERROR · ${e.toString().replaceFirst('Exception: ', '')}';
              } finally {
                if (sheetContext.mounted) {
                  setSheetState(() => busyVoice = false);
                }
              }
            }

            final systemVoices = widget.speech.voiceOptions;
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  14,
                  14,
                  14,
                  MediaQuery.viewInsetsOf(context).bottom + 14,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'DREAM PULSE // VOICE',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, letterSpacing: 1.2),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        'Живой neural voice + автоматический системный fallback',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const SizedBox(height: 14),
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
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  color: widget.speech.neuralConfigured
                                      ? const Color(0xFF39D98A)
                                      : const Color(0xFF687082),
                                ),
                                const SizedBox(width: 7),
                                const Expanded(
                                  child: Text(
                                    'NEURAL // ELEVENLABS',
                                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: .9),
                                  ),
                                ),
                                Switch(
                                  value: widget.speech.neuralEnabled,
                                  onChanged: widget.speech.neuralConfigured
                                      ? (value) async {
                                          await widget.speech.setNeuralEnabled(value);
                                          if (sheetContext.mounted) {
                                            setSheetState(() => message = widget.speech.neuralStatus);
                                          }
                                        }
                                      : null,
                                ),
                              ],
                            ),
                            Text(
                              message,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 9, color: Color(0xFF9CA6B8), letterSpacing: .5),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: apiKey,
                              obscureText: true,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: InputDecoration(
                                labelText: widget.speech.neuralHasApiKey
                                    ? 'ElevenLabs API key · сохранён'
                                    : 'ElevenLabs API key',
                                hintText: widget.speech.neuralHasApiKey ? 'Введи новый только для замены' : 'xi_...',
                              ),
                            ),
                            const SizedBox(height: 8),
                            TextField(
                              controller: voiceId,
                              enableSuggestions: false,
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Voice ID · необязательно',
                                hintText: 'Можно выбрать голос ниже',
                              ),
                            ),
                            const SizedBox(height: 9),
                            Row(
                              children: [
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: busyVoice ? null : connectNeural,
                                    icon: busyVoice
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(strokeWidth: 2),
                                          )
                                        : const Icon(Icons.cloud_sync_outlined, size: 17),
                                    label: const Text('CONNECT / LOAD VOICES'),
                                  ),
                                ),
                                const SizedBox(width: 6),
                                OutlinedButton.icon(
                                  onPressed: busyVoice || !widget.speech.neuralConfigured ? null : testNeural,
                                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                                  label: const Text('TEST'),
                                ),
                              ],
                            ),
                            if (neuralVoices.isNotEmpty) ...[
                              const SizedBox(height: 10),
                              const Text(
                                'ДОСТУПНЫЕ ГОЛОСА',
                                style: TextStyle(fontSize: 9, color: Color(0xFF8992A5), letterSpacing: .8),
                              ),
                              const SizedBox(height: 5),
                              ConstrainedBox(
                                constraints: const BoxConstraints(maxHeight: 300),
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: neuralVoices.length,
                                  itemBuilder: (_, i) {
                                    final voice = neuralVoices[i];
                                    final selected = widget.speech.neuralVoiceId == voice.voiceId;
                                    return ListTile(
                                      dense: true,
                                      contentPadding: EdgeInsets.zero,
                                      leading: Icon(
                                        selected ? Icons.radio_button_checked : Icons.radio_button_off,
                                        size: 18,
                                      ),
                                      title: Text(voice.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                                      subtitle: voice.subtitle.isEmpty
                                          ? Text(voice.voiceId, maxLines: 1, overflow: TextOverflow.ellipsis)
                                          : Text(voice.subtitle, maxLines: 2, overflow: TextOverflow.ellipsis),
                                      trailing: IconButton(
                                        tooltip: 'Прослушать',
                                        icon: const Icon(Icons.headphones_outlined),
                                        onPressed: busyVoice
                                            ? null
                                            : () async {
                                                setSheetState(() => busyVoice = true);
                                                try {
                                                  await widget.speech.previewNeuralVoice(voice);
                                                } catch (e) {
                                                  message = 'ERROR · ${e.toString().replaceFirst('Exception: ', '')}';
                                                } finally {
                                                  if (sheetContext.mounted) {
                                                    setSheetState(() => busyVoice = false);
                                                  }
                                                }
                                              },
                                      ),
                                      onTap: () async {
                                        await widget.speech.selectNeuralVoice(voice);
                                        voiceId.text = voice.voiceId;
                                        if (sheetContext.mounted) {
                                          setSheetState(() => message = widget.speech.neuralStatus);
                                        }
                                        if (mounted) setState(() {});
                                      },
                                    );
                                  },
                                ),
                              ),
                            ],
                            if (widget.speech.neuralHasApiKey) ...[
                              const SizedBox(height: 7),
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton.icon(
                                  onPressed: busyVoice
                                      ? null
                                      : () async {
                                          await widget.speech.clearNeuralCredentials();
                                          voiceId.clear();
                                          neuralVoices = const [];
                                          if (sheetContext.mounted) {
                                            setSheetState(() => message = widget.speech.neuralStatus);
                                          }
                                        },
                                  icon: const Icon(Icons.key_off_outlined, size: 16),
                                  label: const Text('УДАЛИТЬ КЛЮЧ'),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Divider(height: 1),
                      const SizedBox(height: 10),
                      const Text(
                        'SYSTEM FALLBACK // OFFLINE',
                        style: TextStyle(fontSize: 10, letterSpacing: .8, color: Color(0xFF8F98AA)),
                      ),
                      const SizedBox(height: 6),
                      if (systemVoices.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Дополнительных русских TTS-голосов Android не найдено.'),
                        )
                      else
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 220),
                          child: ListView.builder(
                            shrinkWrap: true,
                            itemCount: systemVoices.length,
                            itemBuilder: (_, i) {
                              final voice = systemVoices[i];
                              final selected = widget.speech.selectedVoice?.name == voice.name;
                              return ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(voice.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text(voice.locale),
                                leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
                                trailing: IconButton(
                                  tooltip: 'Прослушать fallback',
                                  icon: const Icon(Icons.play_arrow_rounded),
                                  onPressed: () => widget.speech.previewVoice(voice),
                                ),
                                onTap: () async {
                                  await widget.speech.selectVoice(voice);
                                  if (sheetContext.mounted) setSheetState(() {});
                                  if (mounted) setState(() {});
                                },
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } finally {
      apiKey.dispose();
      voiceId.dispose();
    }
  }

'''
s = s[:start] + method + s[end:]

# Visible version labels.
s = s.replace('v0.9.1 LIVE', 'v0.9.2 NEURAL')
s = s.replace('v0.9.1', 'v0.9.2')
p.write_text(s)

p = Path('lib/ui/assistant_shell.dart')
s = p.read_text().replace('v0.9.1 LIVE', 'v0.9.2 NEURAL')
p.write_text(s)

p = Path('lib/ui/launch_gate.dart')
s = p.read_text().replace('v0.9.1', 'v0.9.2')
p.write_text(s)
