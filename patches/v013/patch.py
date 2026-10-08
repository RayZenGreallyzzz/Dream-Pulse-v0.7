from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
if '  crypto:' not in s:
    s = s.replace('dependencies:\n', 'dependencies:\n  crypto: ^3.0.6\n', 1)
s = '\n'.join('version: 0.13.1+30' if line.startswith('version:') else line for line in s.splitlines()) + '\n'
p.write_text(s)

ui = Path('lib/ui/assistant_page.dart')
s = ui.read_text()
s = s.replace('  bool autoSpeak = true;', '  bool autoSpeak = false;', 1)
ui.write_text(s)


speech = Path('lib/avatar/speech_controller.dart')
text = speech.read_text()
needle = '''  String get voiceStatus => _local.status;
  bool get localVoiceReady => _local.ready;
'''
replacement = '''  String get voiceStatus => _local.status;
  bool get localVoiceReady => _local.ready;
  bool get localVoiceInstalling => _local.installing;
  double get localVoiceInstallProgress => _local.installProgress;

  Future<void> installLocalVoice({void Function(double)? onProgress}) async {
    await _local.install(onProgress: onProgress);
  }
'''
if needle not in text:
    raise SystemExit('speech local voice marker not found')
speech.write_text(text.replace(needle, replacement, 1))

ui = Path('lib/ui/assistant_page.dart')
text = ui.read_text()
needle = '''                    Text(
                      widget.speech.voiceStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777B85),
                      ),
                    ),
                    const SizedBox(height: 18),
'''
replacement = '''                    Text(
                      widget.speech.voiceStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777B85),
                      ),
                    ),
                    if (!widget.speech.localVoiceReady) ...[
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: widget.speech.localVoiceInstalling
                            ? widget.speech.localVoiceInstallProgress
                            : 0.0,
                        minHeight: 3,
                      ),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: widget.speech.localVoiceInstalling
                            ? null
                            : () async {
                                try {
                                  await widget.speech.installLocalVoice(
                                    onProgress: (_) {
                                      if (sheetContext.mounted) {
                                        setSheetState(() {});
                                      }
                                    },
                                  );
                                  if (sheetContext.mounted) {
                                    setSheetState(() {});
                                  }
                                  if (mounted) setState(() {});
                                } catch (e) {
                                  if (mounted) {
                                    setState(() => status =
                                        'Голосовой пакет: $e');
                                  }
                                  if (sheetContext.mounted) {
                                    setSheetState(() {});
                                  }
                                }
                              },
                        icon: const Icon(Icons.download_rounded),
                        label: Text(widget.speech.localVoiceInstalling
                            ? 'Загрузка · ${(widget.speech.localVoiceInstallProgress * 100).round()}%'
                            : 'Установить Baya + Kseniya'),
                        style: TextButton.styleFrom(
                          alignment: Alignment.centerLeft,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ],
                    const SizedBox(height: 18),
'''
if needle not in text:
    raise SystemExit('voice sheet status marker not found')
ui.write_text(text.replace(needle, replacement, 1))
