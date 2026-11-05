"""v0.15.7 Dart wiring for app-private Silero model packs.

No change to Core and no claim that a staged model can synthesize yet.
"""
from pathlib import Path
import shutil


def once(path, old, new):
    file = Path(path)
    data = file.read_text(encoding="utf-8")
    if data.count(old) != 1:
        raise RuntimeError(
            f"{path}: expected one patch anchor, got {data.count(old)}: {old[:90]!r}"
        )
    file.write_text(data.replace(old, new, 1), encoding="utf-8")


def main():
    pubspec = Path("pubspec.yaml")
    code = pubspec.read_text(encoding="utf-8")
    if code.count("version: 0.15.6+40") != 1:
        raise RuntimeError("v0.15.7 needs v0.15.6 Android baseline")
    pubspec.write_text(
        code.replace("version: 0.15.6+40", "version: 0.15.7+41", 1),
        encoding="utf-8",
    )

    shutil.copyfile(
        "patches/v0157/lib/voice/silero_pack_backend.dart",
        "lib/voice/silero_pack_backend.dart",
    )
    Path("test").mkdir(exist_ok=True)
    shutil.copyfile(
        "patches/v0157/test/silero_pack_test.dart",
        "test/silero_pack_test.dart",
    )

    speech = "lib/avatar/speech_controller.dart"
    once(
        speech,
        "import '../voice/dream_pulse_voice_backend.dart';\n",
        "import '../voice/dream_pulse_voice_backend.dart';\n"
        "import '../voice/silero_pack_backend.dart';\n",
    )
    once(
        speech,
        "  final DreamPulseVoiceBackend _local = DreamPulseVoiceBackend();\n",
        "  final DreamPulseVoiceBackend _local = DreamPulseVoiceBackend();\n"
        "  final DreamPulseSileroPackBackend _sileroStore =\n"
        "      const DreamPulseSileroPackBackend();\n",
    )
    once(
        speech,
        "  Future<void> installLocalVoice({void Function(double)? onProgress}) async {\n",
        """  Future<String> sileroPackStatus() async {
    final state = await _sileroStore.status();
    return state.message;
  }

  Future<String> importSileroBasePack(String zipPath) async {
    final state = await _sileroStore.installFromLocalZip(zipPath);
    if (!state.modelStaged) {
      throw StateError('Silero: проверенный пакет не установлен');
    }
    // Staging is NOT speech inference. Irina keeps handling all playback.
    return state.message;
  }

  Future<void> installLocalVoice({void Function(double)? onProgress}) async {
""",
    )

    page = "lib/ui/assistant_page.dart"
    once(
        page,
        """          Future<void> testCurrent() async {
""",
        """          Future<void> importSileroPack() async {
            try {
              final selected = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['zip'],
                withData: false,
              );
              if (selected == null) return;
              final filePath = selected.files.single.path;
              if (filePath == null || filePath.isEmpty) {
                throw StateError('Файл архива Silero недоступен');
              }
              final result = await widget.speech.importSileroBasePack(filePath);
              if (mounted) setState(() => status = result);
              if (sheetContext.mounted) setSheetState(() {});
            } catch (error) {
              if (mounted) {
                setState(() => status = 'Импорт Silero: $error');
              }
              if (sheetContext.mounted) setSheetState(() {});
            }
          }

          Future<void> testCurrent() async {
""",
    )
    once(
        page,
        """                    const SizedBox(height: 10),
                    slider(
                      label: 'Скорость',
""",
        """                    const SizedBox(height: 8),
                    TextButton.icon(
                      onPressed: importSileroPack,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Подготовить веса Silero из ZIP'),
                    ),
                    const Text(
                      'Импорт устанавливает только проверенные файлы модели. '
                      'Пока нейросетевой рантайм не подключён, '
                      'произвольный текст продолжает читать Ирина.',
                      style: TextStyle(
                        fontSize: 10, color: Color(0xFF797D88),
                      ),
                    ),
                    const SizedBox(height: 10),
                    slider(
                      label: 'Скорость',
""",
    )


if __name__ == "__main__":
    main()
