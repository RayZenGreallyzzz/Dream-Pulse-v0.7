"""v0.15.9 Dart controls for real isolated Silero base preview.

Stock Baya is only a diagnostic reference and NOT an author-owned voice.
"""
from pathlib import Path


def once(path, old, new):
    p=Path(path)
    s=p.read_text(encoding="utf-8")
    n=s.count(old)
    if n!=1:
        raise RuntimeError(f"{path}: patch count {n}: {old[:80]!r}")
    p.write_text(s.replace(old,new,1), encoding="utf-8")


def main():
    pub=Path("pubspec.yaml")
    s=pub.read_text(encoding="utf-8")
    if s.count("version: 0.15.8+42")!=1:
        raise RuntimeError("v0.15.8 baseline required")
    pub.write_text(s.replace("version: 0.15.8+42","version: 0.15.9+43"),encoding="utf-8")

    backend="lib/voice/dream_pulse_voice_backend.dart"
    once(backend,"import 'package:flutter/services.dart';",
         "import 'dart:async';\nimport 'package:flutter/services.dart';")
    once(backend,"  bool modelStaged = false;\n",
         "  bool modelStaged = false;\n  bool basePreviewReady = false;\n  bool _previewingBase = false;\n")
    p=Path(backend)
    s=p.read_text(encoding="utf-8")
    anchor="      modelStaged = info['modelStaged'] == true;\n"
    if s.count(anchor)!=2:
        raise RuntimeError("Model status anchors changed")
    p.write_text(s.replace(anchor,anchor+
        "      basePreviewReady = info['basePreviewReady'] == true;\n"), encoding="utf-8")

    once(backend,
        """  Future<void> speak(String text) async {""",
        """  /// Stock female Silero Baya: engineering test only, never Irina.
  Future<String> previewBaseReference() async {
    if (!basePreviewReady) {
      throw StateError(
        'Нужен Silero Full Lite ZIP. Служебный тест не является авторским голосом.',
      );
    }
    _previewingBase = true;
    status = 'Silero Lite · техническая генерация PCM…';
    try {
      final message = await _channel.invokeMethod<String>(
        'previewBase',
        <String, String>{'text': 'прив+ет, м+ир.'},
      ).timeout(const Duration(seconds: 160));
      status = 'Silero Lite · ${message ?? 'звук готов'}';
      return status;
    } on TimeoutException {
      status = 'Silero Lite · голосовой процесс не ответил';
      rethrow;
    } catch (error) {
      status = 'Silero Lite · ошибка: $error';
      rethrow;
    } finally {
      _previewingBase = false;
    }
  }

  Future<void> speak(String text) async {""")
    once(backend,
        """  Future<void> stop() async {
    if (!speaking) return;
    speaking = false;""",
        """  Future<void> stop() async {
    if (!speaking && !_previewingBase) return;
    speaking = false;
    _previewingBase = false;""")

    controller="lib/avatar/speech_controller.dart"
    once(controller,
        """  Future<String> importDreamPulseTtsPack(String zipPath) =>
      _local.importPack(zipPath);""",
        """  Future<String> importDreamPulseTtsPack(String zipPath) =>
      _local.importPack(zipPath);

  Future<String> previewSileroBaseTest() =>
      _local.previewBaseReference();""")

    ui="lib/ui/assistant_page.dart"
    once(ui,
        """          Future<void> importTtsPack() async {""",
        """          Future<void> testSileroBase() async {
            try {
              final message = await widget.speech.previewSileroBaseTest();
              if (mounted) setState(() => status = message);
              if (sheetContext.mounted) setSheetState(() {});
            } catch (error) {
              if (mounted) {
                setState(() => status = 'Технический тест Silero: $error');
              }
              if (sheetContext.mounted) setSheetState(() {});
            }
          }

          Future<void> importTtsPack() async {""")
    once(ui,
        """                    TextButton.icon(
                      onPressed: importTtsPack,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Импортировать веса Dream Pulse TTS'),
                    ),""",
        """                    TextButton.icon(
                      onPressed: importTtsPack,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Импортировать веса Dream Pulse TTS'),
                    ),
                    TextButton.icon(
                      onPressed: testSileroBase,
                      icon: const Icon(Icons.science_outlined),
                      label: const Text(
                        'Технический тест Silero (Baya, не авторский голос)',
                      ),
                    ),""")

    tests=Path("test/voice_catalog_test.dart")
    existing=tests.read_text(encoding="utf-8")
    extra="""  test('Silero baseline cannot impersonate an untrained voice', () async {
    final backend = DreamPulseVoiceBackend();
    expect(backend.basePreviewReady, isFalse);
    await expectLater(
      backend.previewBaseReference(),
      throwsA(isA<StateError>()),
    );
  });

"""
    end=existing.rfind("}\n")
    if end<0:
        raise RuntimeError("Flutter voice test suite has changed")
    tests.write_text(existing[:end]+extra+existing[end:],encoding="utf-8")

if __name__=="__main__":
    main()
