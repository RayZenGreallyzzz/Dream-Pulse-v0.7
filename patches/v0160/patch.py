"""v0.16.0: replace obsolete Zoey/Piper install control with honest Silero UX.

Keep Dream Pulse Core and native Silero inference unchanged. The original
Silero weights are NOT embedded. Never present staged base weights as the
user's authored voice.
"""
from pathlib import Path


def exactly_once(file: Path, old: str, new: str):
    src = file.read_text(encoding="utf-8")
    n = src.count(old)
    if n != 1:
        raise RuntimeError(f"{file}: expected 1 anchor, found {n}: {old[:95]!r}")
    file.write_text(src.replace(old, new, 1), encoding="utf-8")


def replace_between(file: Path, start: str, end: str, replacement: str):
    s = file.read_text(encoding="utf-8")
    if s.count(start) != 1:
        raise RuntimeError(f"{file}: unexpected modal layout for {start[:60]!r}")
    a = s.index(start)
    b = s.find(end, a + len(start))
    if b <= a:
        raise RuntimeError(f"{file}: modal block out of order")
    file.write_text(s[:a] + replacement + s[b:], encoding="utf-8")


def main():
    pub = Path("pubspec.yaml")
    exactly_once(pub, "version: 0.15.9+43", "version: 0.16.0+44")

    ui = Path("lib/ui/assistant_page.dart")
    # Injected by patch v0.13, originally used for a downloadable Piper
    # archive. That backend no longer exists in Dream Pulse v0.15.9.
    start = "                    if (!widget.speech.localVoiceReady) ...[\n"
    end = "                    const SizedBox(height: 18),\n"
    obsolete_download_removed = """                    const SizedBox(height: 12),
                    const Text(
                      'Для проверки нужен локально подготовленный '
                      'Silero Full Lite ZIP. Автозагрузка Zoey-style '
                      'удалена вместе с Piper.',
                      style: TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: Color(0xFFB9BBC2),
                      ),
                    ),
"""
    replace_between(ui, start, end, obsolete_download_removed)

    # This message lives outside StatefulBuilder and survives its rebuilds.
    exactly_once(ui,
        """  Future<void> _showVoiceSheet() async {
    if (!mounted) return;

    await showModalBottomSheet<void>(""",
        """  Future<void> _showVoiceSheet() async {
    if (!mounted) return;
    String voiceNotice = 'Silero: ожидается импорт весов. '
        'Это пока не обученные авторские голоса.';

    await showModalBottomSheet<void>(""")

    # Show errors INSIDE the voice sheet: otherwise they are hidden by the
    # bottom sheet, making a button appear as if it does nothing.
    exactly_once(ui,
        """                    Text(
                      widget.speech.voiceStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777B85),
                      ),
                    ),""",
        """                    Text(
                      widget.speech.voiceStatus,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF777B85),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      voiceNotice,
                      key: const ValueKey('dream-pulse-voice-notice'),
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.4,
                        color: Color(0xFFFFB27C),
                      ),
                    ),""")

    # Replace the confusing no-feedback picker and save progress to the
    # sheet itself. FilePicker is the existing API from the project.
    replace_between(ui,
        "          Future<void> importTtsPack() async {\n",
        "          Future<void> chooseVoice(VoiceOption voice) async {\n",
        """          Future<void> importTtsPack() async {
            if (sheetContext.mounted) {
              setSheetState(() => voiceNotice = 'Открываю выбор ZIP…');
            }
            try {
              final picked = await FilePicker.pickFiles(type: FileType.any);
              if (picked.isEmpty) {
                if (sheetContext.mounted) {
                  setSheetState(() {
                    voiceNotice = 'Выбор файла отменён. '
                        'Сначала подготовь пакет модели на компьютере.';
                  });
                }
                return;
              }
              final selected = picked.first;
              final filePath = selected.path;
              if (filePath == null || filePath.isEmpty) {
                throw StateError(
                  'Android не передал доступный путь к файлу ZIP',
                );
              }
              if (!selected.name.toLowerCase().endsWith('.zip')) {
                throw StateError('Нужен Silero Full Lite ZIP, а не WAV/PT');
              }
              if (sheetContext.mounted) {
                setSheetState(() {
                  voiceNotice = 'Проверяю ZIP и SHA-256 модели…';
                });
              }
              final result =
                  await widget.speech.importDreamPulseTtsPack(filePath);
              if (mounted) setState(() => status = result);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = result);
              }
            } catch (error) {
              final detail = 'Импорт Silero: ' + error.toString();
              if (mounted) setState(() => status = detail);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = detail);
              }
            }
          }

""")

    # Show a visible response even if the model isn't installed, and
    # preserve a clear separation between diagnostic Baya and user voices.
    replace_between(ui,
        "          Future<void> testSileroBase() async {\n",
        "          Future<void> importTtsPack() async {\n",
        """          Future<void> testSileroBase() async {
            if (sheetContext.mounted) {
              setSheetState(() {
                voiceNotice = 'Проверяю Silero Lite. '
                    'Это тест Baya, не голос Ирина.';
              });
            }
            try {
              final message = await widget.speech.previewSileroBaseTest();
              if (mounted) setState(() => status = message);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = message);
              }
            } catch (error) {
              final detail = 'Silero: ' + error.toString();
              if (mounted) setState(() => status = detail);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = detail);
              }
            }
          }

""")

    # Legacy "Test" always showed success even when the engine had no
    # compatible voice weights. Make this explicit instead.
    replace_between(ui,
        "          Future<void> testCurrent() async {\n",
        "          Future<void> diagnoseVoice() async {\n",
        """          Future<void> testCurrent() async {
            try {
              await widget.speech.previewCurrent();
              final message = 'Тест выбранного голоса завершён.';
              if (mounted) setState(() => status = message);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = message);
              }
            } catch (error) {
              final detail = 'Авторский голос ещё не готов: '
                  + error.toString();
              if (mounted) setState(() => status = detail);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = detail);
              }
            }
          }

""")

    replace_between(ui,
        "          Future<void> diagnoseVoice() async {\n",
        "          Future<void> testSileroBase() async {\n",
        """          Future<void> diagnoseVoice() async {
            if (sheetContext.mounted) {
              setSheetState(() {
                voiceNotice = 'Проверяю состояние Dream Pulse TTS…';
              });
            }
            try {
              final result = await widget.speech.diagnoseLocalVoice();
              if (mounted) setState(() => status = result);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = result);
              }
            } catch (error) {
              final detail = 'Диагностика TTS: ' + error.toString();
              if (mounted) setState(() => status = detail);
              if (sheetContext.mounted) {
                setSheetState(() => voiceNotice = detail);
              }
            }
          }

""")

    # Runtime no longer contains a downloadable Zoey or Piper voice.
    s = ui.read_text(encoding="utf-8")
    if "Установить Dream Voice · Zoey-style" in s:
        raise RuntimeError("Legacy Zoey download button survived v0.16.0")
    if "onPressed: widget.speech.localVoiceInstalling" in s:
        raise RuntimeError("Legacy Piper downloader handler survived v0.16.0")


if __name__ == "__main__":
    main()
