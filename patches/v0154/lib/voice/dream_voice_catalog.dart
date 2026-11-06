/// Registered voice slots; only engines with actual speech models are playable.
/// WAV recordings are *training references*, NOT drop-in TTS voice models.
enum DreamVoiceEngine { piper, ruVoiceSystemBridge, customModelPending }

class DreamVoiceDescriptor {
  const DreamVoiceDescriptor({
    required this.id,
    required this.label,
    required this.engine,
    required this.canSynthesize,
    this.referenceFile,
  });

  final String id;
  final String label;
  final DreamVoiceEngine engine;
  final bool canSynthesize;
  final String? referenceFile;
}

class DreamVoiceCatalog {
  const DreamVoiceCatalog._();

  static const playable = <DreamVoiceDescriptor>[
    DreamVoiceDescriptor(
      id: 'zoey',
      label: 'Dream · Zoey-style (Piper Irina)',
      engine: DreamVoiceEngine.piper,
      canSynthesize: true,
    ),
    DreamVoiceDescriptor(
      id: 'irina',
      label: 'Ирина · Piper',
      engine: DreamVoiceEngine.piper,
      canSynthesize: true,
    ),
    DreamVoiceDescriptor(
      id: 'ruvoice_baya',
      label: 'Silero · Baya (RuVoice)',
      engine: DreamVoiceEngine.ruVoiceSystemBridge,
      canSynthesize: true,
    ),
    DreamVoiceDescriptor(
      id: 'ruvoice_kseniya',
      label: 'Silero · Kseniya (RuVoice)',
      engine: DreamVoiceEngine.ruVoiceSystemBridge,
      canSynthesize: true,
    ),
    DreamVoiceDescriptor(
      id: 'ruvoice_xenia',
      label: 'Silero · Xenia (RuVoice)',
      engine: DreamVoiceEngine.ruVoiceSystemBridge,
      canSynthesize: true,
    ),
  ];

  /// Private recordings are distributed in a separate local ZIP, not in the
  /// public GitHub repository or the APK until a model is actually trained.
  static const references = <DreamVoiceDescriptor>[
    DreamVoiceDescriptor(
      id: 'dream_ref_hello',
      label: 'Мой голос · Привет',
      engine: DreamVoiceEngine.customModelPending,
      canSynthesize: false,
      referenceFile: 'hello.wav',
    ),
    DreamVoiceDescriptor(
      id: 'dream_ref_calm',
      label: 'Мой голос · Ты справляешься',
      engine: DreamVoiceEngine.customModelPending,
      canSynthesize: false,
      referenceFile: 'calm.wav',
    ),
    DreamVoiceDescriptor(
      id: 'dream_ref_weather',
      label: 'Мой голос · Как погода за окном',
      engine: DreamVoiceEngine.customModelPending,
      canSynthesize: false,
      referenceFile: 'weather.wav',
    ),
    DreamVoiceDescriptor(
      id: 'dream_ref_long',
      label: 'Мой голос · Не спрашивай сколько',
      engine: DreamVoiceEngine.customModelPending,
      canSynthesize: false,
      referenceFile: 'long.wav',
    ),
  ];

  static DreamVoiceDescriptor? find(String id) {
    for (final item in [...playable, ...references]) {
      if (item.id == id) return item;
    }
    return null;
  }
}
