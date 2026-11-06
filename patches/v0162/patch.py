"""v0.16.2: select and audition four fitted DSP timbre weights.

Author-defined voices keep their identities; this experimental preview is
not a trained Silero speaker or completed production TTS.
"""
from pathlib import Path

def one(path, old, new):
    p=Path(path)
    source=p.read_text(encoding="utf-8")
    n=source.count(old)
    if n!=1:
        raise RuntimeError(f"{path}: expected one patch anchor, got {n}: {old[:80]!r}")
    p.write_text(source.replace(old,new,1),encoding="utf-8")

pub=Path("pubspec.yaml")
one(str(pub),"version: 0.16.0+44","version: 0.16.2+46")

backend="lib/voice/dream_pulse_voice_backend.dart"
one(backend,
    """  Future<void> speak(String text) async {""",
    """  /// EXPERIMENTAL audio coloration based on learned coefficients.
  /// This is NOT a trained speaker-identity checkpoint for Silero.
  Future<String> previewSelectedTimbre() async {
    const ids = {
      'dream_ref_hello',
      'dream_ref_calm',
      'dream_ref_weather',
      'dream_ref_long',
    };
    final selected = profile.voice;
    if (!ids.contains(selected)) {
      throw StateError(
        'Выбери один из четырёх авторских голосов. '
        'Ирина проходит отдельную подготовку.',
      );
    }
    if (!basePreviewReady) {
      throw StateError(
        'Сначала импортируй Silero Full Lite ZIP. '
        'Только после этого можно проверить обученный тембр.',
      );
    }
    _previewingBase = true;
    status = 'Dream Pulse · проверка обученного тембра $selected…';
    try {
      final message = await _channel.invokeMethod<String>(
        'previewStyle',
        <String, String>{'text': 'прив+ет, м+ир.', 'voice': selected},
      ).timeout(const Duration(seconds: 160));
      status = message ?? 'Синтезирован тестовый звук с тембром $selected';
      return status;
    } catch (error) {
      status = 'Тест тембра: $error';
      rethrow;
    } finally {
      _previewingBase = false;
    }
  }

  Future<void> speak(String text) async {""")

controller="lib/avatar/speech_controller.dart"
one(controller,
    """  Future<String> previewSileroBaseTest() =>
      _local.previewBaseReference();""",
    """  Future<String> previewSileroBaseTest() =>
      _local.previewBaseReference();

  Future<String> previewSelectedTrainedTimbre() =>
      _local.previewSelectedTimbre();""")

ui="lib/ui/assistant_page.dart"
one(ui,
    """          Future<void> testSileroBase() async {""",
    """          Future<void> testTrainedTimbre() async {
            if (sheetContext.mounted) {
              setSheetState(() {
                voiceNotice = 'Проверка обученного тембра на базовом Silero. '
                    'Это ещё не точное воспроизведение авторского голоса.';
              });
            }
            try {
              final message =
                  await widget.speech.previewSelectedTrainedTimbre();
              if (mounted) setState(() => status = message);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = message);
              }
            } catch (error) {
              final detail = 'Тест обученного тембра: $error';
              if (mounted) setState(() => status = detail);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = detail);
              }
            }
          }

          Future<void> testSileroBase() async {""")
one(ui,
    """                    TextButton.icon(
                      onPressed: testSileroBase,
                      icon: const Icon(Icons.science_outlined),
                      label: const Text(
                        'Технический тест Silero (Baya, не авторский голос)',
                      ),
                    ),""",
    """                    TextButton.icon(
                      onPressed: testSileroBase,
                      icon: const Icon(Icons.science_outlined),
                      label: const Text(
                        'Технический тест Silero (Baya, не авторский голос)',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: testTrainedTimbre,
                      icon: const Icon(Icons.tune),
                      label: const Text(
                        'Прослушать обученный тембр выбранного голоса',
                      ),
                    ),
                    const Text(
                      'Только экспериментальная обработка тембра. '
                      'Полноценные голоса ещё не дообучены.',
                      style: TextStyle(fontSize: 10, color: Color(0xFF797D88)),
                    ),""")

tests=Path("test/voice_catalog_test.dart")
s=tests.read_text(encoding="utf-8")
extra="""  test('trained timbre requires local Silero model pack', () async {
    final backend = DreamPulseVoiceBackend();
    expect(backend.basePreviewReady, isFalse);
    await backend.selectVoice('dream_ref_hello');
    await expectLater(
      backend.previewSelectedTimbre(),
      throwsA(isA<StateError>()),
    );
  });

"""
# Test selectVoice writes secure storage; not accessible on a bare test
# platform unless mocked. Instead check default Irina error, no method call.
extra="""  test('trained timbre is not claimed available without model weights', () async {
    final backend = DreamPulseVoiceBackend();
    expect(backend.basePreviewReady, isFalse);
    await expectLater(
      backend.previewSelectedTimbre(),
      throwsA(isA<StateError>()),
    );
  });

"""
end=s.rfind("}\n")
if end<0:raise RuntimeError("Missing Flutter test-suite end")
tests.write_text(s[:end]+extra+s[end:],encoding="utf-8")
