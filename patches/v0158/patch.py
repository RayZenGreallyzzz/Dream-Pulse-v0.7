"""v0.15.8: remove Piper integration, prepare Dream Pulse TTS.

Only the voice subsystem changes. Flutter UI and AI Core remain Android-first.
"""
from pathlib import Path
import shutil

def once(path, old, new):
    p=Path(path)
    s=p.read_text(encoding="utf-8")
    if s.count(old)!=1:
        raise RuntimeError(f"{path}: found {s.count(old)} occurrences: {old[:80]!r}")
    p.write_text(s.replace(old,new,1),encoding="utf-8")

def main():
    pub=Path("pubspec.yaml")
    s=pub.read_text(encoding="utf-8")
    if s.count("version: 0.15.6+40")!=1:
        raise RuntimeError("Requires Dream Pulse 0.15.6 base")
    pub.write_text(s.replace("version: 0.15.6+40","version: 0.15.8+42"),encoding="utf-8")

    for path in ["dream_pulse_voice_backend.dart","dream_voice_catalog.dart"]:
        shutil.copyfile(
            f"patches/v0158/lib/voice/{path}",f"lib/voice/{path}",
        )
    shutil.copyfile("patches/v0158/test/voice_catalog_test.dart","test/voice_catalog_test.dart")

    speech="lib/avatar/speech_controller.dart"
    once(speech,
        """  final List<VoiceOption> voiceOptions = const [
    VoiceOption('irina', 'Ирина · локальная'),
  ];""",
        """  final List<VoiceOption> voiceOptions = const [
    VoiceOption('irina', 'Ирина · перенос в Dream Pulse TTS'),
    VoiceOption('dream_ref_hello', 'Авторский 1 · Привет'),
    VoiceOption('dream_ref_calm', 'Авторский 2 · Спокойный'),
    VoiceOption('dream_ref_weather', 'Авторский 3 · Погода'),
    VoiceOption('dream_ref_long', 'Авторский 4 · Диалог'),
  ];""")
    once(speech,
        """  VoiceOption selectedVoice =
      const VoiceOption('irina', 'Ирина · локальная');""",
        """  VoiceOption selectedVoice =
      const VoiceOption('irina', 'Ирина · перенос в Dream Pulse TTS');""")
    once(speech,
        """    // Silero female model packs will be local assets, never external RuVoice.
    // Previously stored Zoey-style remains an internal alias of Piper Irina.
    if (_local.profile.voice != 'irina') {
      await _local.selectVoice('irina');
    }
""",
        """    // Keep each creator-defined speaker identity separate.
""")
    once(speech,
        """    if (entry == null || !entry.canSynthesize) {
      throw StateError('Голос ещё не обучен для TTS');
    }""",
        """    if (entry == null) {
      throw StateError('Голос не зарегистрирован в Dream Pulse TTS');
    }""")
    once(speech,
        """  Future<void> installLocalVoice({void Function(double)? onProgress}) async {
    await _local.install(onProgress: onProgress);
  }""",
        """  Future<void> installLocalVoice({void Function(double)? onProgress}) async {
    await _local.install(onProgress: onProgress);
  }

  Future<String> importDreamPulseTtsPack(String zipPath) =>
      _local.importPack(zipPath);""")
    once(speech,
        """  Future<void> previewCurrent() async {
    await speak(""",
        """  Future<void> previewCurrent() async {
    if (!_local.ready && !neuralConfigured) {
      throw StateError('Модель голоса ещё не обучена для TTS');
    }
    await speak(""")

    page="lib/ui/assistant_page.dart"
    once(page,
        """          Future<void> chooseVoice(VoiceOption voice) async {""",
        """          Future<void> importTtsPack() async {
            try {
              final picked = await FilePicker.platform.pickFiles(
                type: FileType.custom,
                allowedExtensions: ['zip'],
                withData: false,
              );
              if (picked == null) return;
              final filePath = picked.files.single.path;
              if (filePath == null || filePath.isEmpty) {
                throw StateError('Архив ZIP недоступен Android');
              }
              final message =
                  await widget.speech.importDreamPulseTtsPack(filePath);
              if (mounted) setState(() => status = message);
              if (sheetContext.mounted) setSheetState(() {});
            } catch (error) {
              if (mounted) setState(() => status = 'Dream Pulse TTS: $error');
              if (sheetContext.mounted) setSheetState(() {});
            }
          }

          Future<void> chooseVoice(VoiceOption voice) async {""")
    once(page,
        """                    TextButton.icon(
                      onPressed: diagnoseVoice,""",
        """                    TextButton.icon(
                      onPressed: importTtsPack,
                      icon: const Icon(Icons.file_upload_outlined),
                      label: const Text('Импортировать веса Dream Pulse TTS'),
                    ),
                    const SizedBox(height: 4),
                    TextButton.icon(
                      onPressed: diagnoseVoice,""")
    once(page,
        """                      'Ирина работает локально. Dream Pulse Silero на '
                      'оригинальных весах находится в разработке: '
                      'отдельный RuVoice не требуется.',""",
        """                      'Piper удалён. Dream Pulse TTS использует '
                      'проверенные веса Silero. Сам синтез ещё в разработке.',""")
    once(page,
        """                      'Мои женские голоса · исходные записи для обучения',""",
        """                      'Четыре самостоятельных авторских голоса',""")
    # Old narrative labels vary between patch versions; strip them if present.
    p=Path(page)
    ui=p.read_text(encoding="utf-8")
    ui=ui.replace("Модель: Piper Irina · sherpa-onnx · PCM 16-bit.", "Dream Pulse TTS · Silero v5_5_ru (подготовка).")
    ui=ui.replace("Dream · Zoey-style — наш профиль звучания.", "Голосовые модели пока не обучены.")
    p.write_text(ui,encoding="utf-8")
    # Do not pretend that pressing test produced audio when TTS is absent.
    once(page,
        """            } catch (_) {
              if (mounted) setState(() => status = widget.speech.voiceStatus);""",
        """            } catch (error) {
              if (mounted) setState(() => status = 'Тест TTS: $error');""")

if __name__=="__main__":
    main()
