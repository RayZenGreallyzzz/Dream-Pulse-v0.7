from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
s = '\n'.join(
    'version: 0.15.2+36'
    if line.startswith('version:')
    else line
    for line in s.splitlines()
) + '\n'
p.write_text(s)

backend = Path('lib/voice/dream_pulse_voice_backend.dart')
text = backend.read_text()

needle = '''  Future<void> selectVoice(String value) async {'''
diag = '''  Future<String> diagnose() async {
    status = 'Диагностика · сигнал → модель → TTS…';

    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('diagnose')
              .timeout(
        const Duration(seconds: 40),
        onTimeout: () async {
          final state =
              await _channel.invokeMapMethod<String, dynamic>('status') ??
                  const {};
          final stage = state['lastStage']?.toString() ?? 'unknown';
          throw TimeoutException(
            'Диагностика зависла на этапе: $stage',
          );
        },
      );

      final message = result?['message']?.toString() ?? 'DIAG OK';
      final stage = result?['stage']?.toString() ?? 'done';
      status = '$message · $stage';
      return status;
    } on PlatformException catch (e) {
      final state =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      final stage = state['lastStage']?.toString() ?? 'unknown';
      status =
          'Диагностика: ${e.message ?? e.code} · этап: $stage';
      rethrow;
    }
  }

'''

if needle not in text:
    raise SystemExit('backend selectVoice marker not found')
text = text.replace(needle, diag + needle, 1)
backend.write_text(text)

speech = Path('lib/avatar/speech_controller.dart')
text = speech.read_text()
needle = '''  Future<void> selectVoice(VoiceOption option) async {'''
insert = '''  Future<String> diagnoseLocalVoice() async {
    final result = await _local.diagnose();
    lastVoiceError = '';
    return result;
  }

'''
if needle not in text:
    raise SystemExit('speech selectVoice marker not found')
text = text.replace(needle, insert + needle, 1)
speech.write_text(text)

ui = Path('lib/ui/assistant_page.dart')
text = ui.read_text()

needle = '''          Future<void> chooseVoice(VoiceOption voice) async {'''
insert = '''          Future<void> diagnoseVoice() async {
            try {
              final message = await widget.speech.diagnoseLocalVoice();
              if (sheetContext.mounted) setSheetState(() {});
              if (mounted) {
                setState(() => status = message);
              }
            } catch (_) {
              if (mounted) {
                setState(() => status = widget.speech.voiceStatus);
              }
              if (sheetContext.mounted) setSheetState(() {});
            }
          }

'''
if needle not in text:
    raise SystemExit('voice sheet chooseVoice marker not found')
text = text.replace(needle, insert + needle, 1)

needle = '''                    TextButton.icon(
                      onPressed: testCurrent,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('Тест · ${widget.speech.voiceLabel}'),
'''
replacement = '''                    TextButton.icon(
                      onPressed: diagnoseVoice,
                      icon: const Icon(Icons.health_and_safety_outlined),
                      label: const Text(
                        'Диагностика · сигнал + модель + TTS',
                      ),
                      style: TextButton.styleFrom(
                        alignment: Alignment.centerLeft,
                        padding: EdgeInsets.zero,
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: testCurrent,
                      icon: const Icon(Icons.play_arrow_rounded),
                      label: Text('Тест · ${widget.speech.voiceLabel}'),
'''
if needle not in text:
    raise SystemExit('voice test button marker not found')
text = text.replace(needle, replacement, 1)

text = text.replace(
    'Модель: Silero TTS v5_5_ru · локальное выполнение. '
    'Доступны только Baya и Kseniya.',
    'Модель: Piper Irina · sherpa-onnx · PCM 16-bit. '
    'Dream · Zoey-style — наш профиль звучания.'
)

ui.write_text(text)
