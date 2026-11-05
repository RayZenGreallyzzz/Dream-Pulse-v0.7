"""v0.15.5: correct the TTS product contract to embedded female voices only.

Undo v0.15.4's experimental external RuVoice bridge in the generated Android
app. Irina remains on current Piper (already verified). Other female recordings
remain private references until actual mobile-compatible weights are trained.
No Dream Pulse Core changes.
"""
from pathlib import Path
import shutil


def once(path, old, new):
    p = Path(path)
    data = p.read_text(encoding="utf-8")
    n = data.count(old)
    if n != 1:
        raise RuntimeError(f"{path}: expected one occurrence, got {n}: {old[:65]!r}")
    p.write_text(data.replace(old, new, 1), encoding="utf-8")


def main():
    shutil.copyfile(
        "patches/v0155/lib/voice/dream_voice_catalog.dart",
        "lib/voice/dream_voice_catalog.dart",
    )
    shutil.copyfile(
        "patches/v0155/test/voice_catalog_test.dart",
        "test/voice_catalog_test.dart",
    )
    old_bridge = Path("lib/voice/ruvoice_silero_bridge.dart")
    if old_bridge.is_file():
        old_bridge.unlink()

    # Preserve original v0.15.2 diagnostics while removing all external TTS.
    speech = Path("lib/avatar/speech_controller.dart")
    shutil.copyfile(
        "patches/v015/lib/avatar/speech_controller.dart", speech,
    )
    once(speech,
        "import '../voice/dream_pulse_voice_backend.dart';\n",
        "import '../voice/dream_pulse_voice_backend.dart';\n"
        "import '../voice/dream_voice_catalog.dart';\n")
    once(speech,
        """  final List<VoiceOption> voiceOptions = const [
    VoiceOption('zoey', 'Dream · Zoey-style'),
    VoiceOption('irina', 'Irina · base'),
  ];""",
        """  final List<VoiceOption> voiceOptions = const [
    VoiceOption('irina', 'Ирина · локальная'),
  ];""")
    once(speech,
        """  VoiceOption selectedVoice =
      const VoiceOption('zoey', 'Dream · Zoey-style');""",
        """  VoiceOption selectedVoice =
      const VoiceOption('irina', 'Ирина · локальная');""")
    once(speech,
        """    await _local.init();
    selectedVoice = voiceOptions.firstWhere(""",
        """    await _local.init();
    // Silero female model packs will be local assets, never external RuVoice.
    // Previously stored Zoey-style remains an internal alias of Piper Irina.
    if (_local.profile.voice != 'irina') {
      await _local.selectVoice('irina');
    }
    selectedVoice = voiceOptions.firstWhere(""")
    once(speech,
        """  Future<void> selectVoice(VoiceOption option) async {
    await _local.stop();
    await _local.selectVoice(option.name);""",
        """  Future<void> selectVoice(VoiceOption option) async {
    final entry = DreamVoiceCatalog.find(option.name);
    if (entry == null || !entry.canSynthesize) {
      throw StateError('Голос ещё не обучен для TTS');
    }
    await _local.stop();
    await _local.selectVoice(option.name);""")
    once(speech,
        "  Future<void> selectVoice(VoiceOption option) async {",
        """  Future<String> diagnoseLocalVoice() async {
    final result = await _local.diagnose();
    lastVoiceError = '';
    return result;
  }

  Future<void> selectVoice(VoiceOption option) async {""")

    # The user's four recordings must be represented as pending reference
    # datasets, never masquerading as independent neural voice models.
    ui = Path("lib/ui/assistant_page.dart")
    source = ui.read_text(encoding="utf-8")
    start_marker = """                    const SizedBox(height: 8),
                    Text(
                      widget.speech.ruVoiceAvailable"""
    end_marker = """                    const SizedBox(height: 10),
                    slider(
                      label: 'Скорость',"""
    start = source.find(start_marker)
    end = source.find(end_marker, start + 1)
    if start < 0 or end < 0:
        raise RuntimeError("v0.15.4 voice UI section not found")
    new_section = """                    const SizedBox(height: 8),
                    const Text(
                      'Ирина работает локально. Dream Pulse Silero на '
                      'оригинальных весах находится в разработке: '
                      'отдельный RuVoice не требуется.',
                      style: TextStyle(
                        fontSize: 11, color: Color(0xFF9498A3),
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Мои женские голоса · исходные записи для обучения',
                      style: TextStyle(
                        fontSize: 11, color: Color(0xFFB9BBC2),
                      ),
                    ),
                    ...DreamVoiceCatalog.references.map(
                      (voice) => Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(
                          '${voice.label} · TTS-модель ещё не обучена',
                          style: const TextStyle(
                            fontSize: 10, color: Color(0xFF797D88),
                          ),
                        ),
                      ),
                    ),
"""
    ui.write_text(source[:start] + new_section + source[end:], encoding="utf-8")

    # This opt-in bridge was only used in v0.15.4; native Flutter TTS and
    # externally installed Android engines are no longer dependencies.
    pub = Path("pubspec.yaml")
    lines = pub.read_text(encoding="utf-8").splitlines()
    lines = [
        ("version: 0.15.5+39" if line.startswith("version:") else line)
        for line in lines if not line.strip().startswith("flutter_tts:")
    ]
    pub.write_text("\n".join(lines) + "\n", encoding="utf-8")


if __name__ == "__main__":
    main()
