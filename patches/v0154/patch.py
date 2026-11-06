"""Android v0.15.4: fix analyzer findings and add a truthful RuVoice bridge.

Preserves existing Dream Pulse Core and Piper Irina runtime. This optional
RuVoice mode uses the separate Android system TTS engine for now; it is NOT
an embedded Silero engine or a trained clone of the supplied WAV files.
"""
from pathlib import Path
import re
import shutil


def replace_once(path, old, new):
    p = Path(path)
    text = p.read_text(encoding="utf-8")
    if text.count(old) != 1:
        raise RuntimeError(f"{path}: patch anchor count={text.count(old)}: {old[:90]!r}")
    p.write_text(text.replace(old, new, 1), encoding="utf-8")


def add_after(path, old, more):
    replace_once(path, old, old + more)


def main():
    Path("lib/voice").mkdir(parents=True, exist_ok=True)
    shutil.copyfile(
        "patches/v0154/lib/voice/ruvoice_silero_bridge.dart",
        "lib/voice/ruvoice_silero_bridge.dart",
    )
    shutil.copyfile(
        "patches/v0154/lib/voice/dream_voice_catalog.dart",
        "lib/voice/dream_voice_catalog.dart",
    )
    Path("test").mkdir(exist_ok=True)
    shutil.copyfile(
        "patches/v0154/test/voice_catalog_test.dart",
        "test/voice_catalog_test.dart",
    )

    pubspec = Path("pubspec.yaml")
    src = pubspec.read_text(encoding="utf-8")
    if "flutter_tts:" not in src:
        src = src.replace(
            "dependencies:\n",
            "dependencies:\n  flutter_tts: ^4.2.5\n",
            1,
        )
    src = "\n".join(
        "version: 0.15.4+38" if line.startswith("version:") else line
        for line in src.splitlines()
    ) + "\n"
    pubspec.write_text(src, encoding="utf-8")

    voice = "lib/avatar/speech_controller.dart"
    add_after(voice,
        "import 'dart:math';\n",
        "\nimport 'package:flutter_secure_storage/flutter_secure_storage.dart';\n")
    add_after(voice,
        "import '../voice/dream_pulse_voice_backend.dart';\n",
        "import '../voice/dream_voice_catalog.dart';\n"
        "import '../voice/ruvoice_silero_bridge.dart';\n")
    add_after(voice,
        "  final ElevenLabsVoiceBackend _neural = ElevenLabsVoiceBackend();\n",
        "  final RuVoiceSileroBridge _ruvoice = RuVoiceSileroBridge();\n"
        "  static const _voiceStore = FlutterSecureStorage();\n"
        "  static const _ruVoiceSlot = 'dream_pulse_ruvoice_selected';\n"
        "  bool get ruVoiceAvailable => _ruvoice.available;\n")
    replace_once(voice,
        """  final List<VoiceOption> voiceOptions = const [
    VoiceOption('zoey', 'Dream · Zoey-style'),
    VoiceOption('irina', 'Irina · base'),
  ];""",
        """  final List<VoiceOption> voiceOptions = const [
    VoiceOption('zoey', 'Dream · Zoey-style'),
    VoiceOption('irina', 'Ирина · Piper'),
    VoiceOption('ruvoice_baya', 'Silero · Baya (RuVoice)'),
    VoiceOption('ruvoice_kseniya', 'Silero · Kseniya (RuVoice)'),
    VoiceOption('ruvoice_xenia', 'Silero · Xenia (RuVoice)'),
  ];""")
    replace_once(voice,
        "  String get voiceStatus => _local.status;",
        "  String get voiceStatus => selectedVoice.name.startsWith('ruvoice_')\n"
        "      ? _ruvoice.status : _local.status;")
    replace_once(voice,
        """    try {
      await _neural.init();
    } catch (_) {}
    initialized = true;""",
        """    try {
      await _ruvoice.init();
      final saved = await _voiceStore.read(key: _ruVoiceSlot);
      if (saved != null && _ruvoice.available &&
          RuVoiceSileroBridge.voices.containsKey(saved)) {
        selectedVoice = voiceOptions.firstWhere((v) => v.name == saved);
      }
    } catch (_) {}
    try {
      await _neural.init();
    } catch (_) {}
    initialized = true;""")
    replace_once(voice,
        """  Future<void> selectVoice(VoiceOption option) async {
    await _local.stop();
    await _local.selectVoice(option.name);
    selectedVoice = option;
    lastVoiceError = '';
  }""",
        """  Future<void> selectVoice(VoiceOption option) async {
    final entry = DreamVoiceCatalog.find(option.name);
    if (entry == null || !entry.canSynthesize) {
      throw StateError('Голос ещё не обучен для TTS');
    }
    await stop();
    if (entry.engine == DreamVoiceEngine.ruVoiceSystemBridge) {
      await _ruvoice.init();
      if (!_ruvoice.available) {
        throw StateError(
          'Для голоса Silero требуется установленный RuVoice. '
          'Встроенную модель подготовим отдельно.',
        );
      }
      selectedVoice = option;
      await _voiceStore.write(key: _ruVoiceSlot, value: option.name);
    } else {
      await _local.selectVoice(option.name);
      selectedVoice = option;
      await _voiceStore.delete(key: _ruVoiceSlot);
    }
    lastVoiceError = '';
  }""")
    replace_once(voice,
        """    _beginExternalSpeech();
    try {
      await _local.speak(spoken);
      lastVoiceError = '';
    } catch (e) {""",
        """    _beginExternalSpeech();
    try {
      if (selectedVoice.name.startsWith('ruvoice_')) {
        await _ruvoice.speak(
          spoken, selectedVoice.name,
          rate: _local.profile.rate,
          volume: _local.profile.volume,
        );
      } else {
        await _local.speak(spoken);
      }
      lastVoiceError = '';
    } catch (e) {""")
    replace_once(voice,
        """    await Future.wait([
      _local.stop(),
      _neural.stop(),
    ]);""",
        """    await Future.wait([
      _local.stop(),
      _neural.stop(),
      _ruvoice.stop(),
    ]);""")
    replace_once(voice,
        "    unawaited(_neural.dispose());\n",
        "    unawaited(_neural.dispose());\n"
        "    unawaited(_ruvoice.dispose());\n")

    ui = "lib/ui/assistant_page.dart"
    add_after(ui,
        "import '../voice/voice_input_controller.dart';\n",
        "import '../voice/dream_voice_catalog.dart';\n")
    replace_once(ui,
        """                    const SizedBox(height: 10),
                    slider(
                      label: 'Скорость',""",
        """                    const SizedBox(height: 8),
                    Text(
                      widget.speech.ruVoiceAvailable
                          ? 'Silero Baya / Kseniya / Xenia используют '
                              'отдельно установленный RuVoice. '
                              'Встраивание модели — следующий этап.'
                          : 'Silero пока требует установки RuVoice. '
                              'Ирина остаётся доступна в Dream Pulse.',
                      style: const TextStyle(
                        fontSize: 11, color: Color(0xFF9498A3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Мои WAV-голоса · образцы для обучения (ещё не TTS)',
                      style: TextStyle(
                        fontSize: 11, color: Color(0xFFB9BBC2),
                      ),
                    ),
                    ...DreamVoiceCatalog.references.map(
                      (voice) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${voice.label} · модель не обучена',
                          style: const TextStyle(
                            fontSize: 10, color: Color(0xFF797D88),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    slider(
                      label: 'Скорость',""")
    replace_once(ui,
        """              if (mounted) {
                setState(() => status = 'Не удалось выбрать локальный голос');
              }""",
        """              if (mounted) {
                setState(() => status = widget.speech.voiceStatus);
              }""")

    # API 7.5+ of speech_to_text keeps the semantics but uses an options
    # object to avoid deprecated named parameters.
    mic = "lib/voice/voice_input_controller.dart"
    replace_once(mic,
        """      localeId: 'ru_RU',
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 3),
      partialResults: true,""",
        """      listenOptions: stt.SpeechListenOptions(
        localeId: 'ru_RU',
        listenFor: Duration(seconds: 30),
        pauseFor: Duration(seconds: 3),
        partialResults: true,
      ),""")

    # Remove warnings without changing app behavior.
    for path in [
        "lib/avatar/avatar_session.dart",
        "lib/avatar/avatar_stage.dart",
        "lib/tools/tool_registry.dart",
    ]:
        p = Path(path)
        s = p.read_text(encoding="utf-8")
        s = s.replace("import 'dart:typed_data';\n", "", 1)
        p.write_text(s, encoding="utf-8")

    for path in ["lib/ui/world_painter.dart", "lib/ui/ring_painter.dart"]:
        p = Path(path)
        s = p.read_text(encoding="utf-8")
        s = s.replace(".withOpacity(", ".withValues(alpha: ")
        p.write_text(s, encoding="utf-8")

    world = Path("lib/ui/world_painter.dart")
    world_lines = world.read_text(encoding="utf-8").splitlines()
    # Analyzer confirms byId is unused. The initializer may span
    # multiple lines; remove through the terminating semicolon.
    cleaned = []
    dropping = False
    for line in world_lines:
        if not dropping and "final byId =" in line:
            dropping = not line.strip().endswith(";")
            continue
        if dropping:
            if line.strip().endswith(";"):
                dropping = False
            continue
        cleaned.append(line)
    world.write_text("\n".join(cleaned) + "\n", encoding="utf-8")

    # Stage files were copied into app/test, so only the usual generated test
    # imports need to be lint-suppressed in older base archive layouts.
    t = Path("test/core_hardening_test.dart")
    if t.is_file():
        src = t.read_text(encoding="utf-8")
        if not src.startswith("// ignore_for_file: avoid_relative_lib_imports"):
            src = "// ignore_for_file: avoid_relative_lib_imports\n\n" + src
            t.write_text(src, encoding="utf-8")



if __name__ == "__main__":
    main()
