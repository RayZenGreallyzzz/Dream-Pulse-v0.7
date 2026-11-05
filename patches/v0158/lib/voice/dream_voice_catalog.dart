/// Voice identities remain distinct; the temporary absence of a TTS runtime
/// MUST NOT be represented as an installed or playable voice.
enum DreamVoiceEngine { irinaMigrationPending, sileroCustomPending }

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

  /// Irina is an owner-created identity, NOT an original Silero voice.
  /// The previous Piper package has been removed from the Android app.
  static const irina = DreamVoiceDescriptor(
    id: 'irina',
    label: 'Ирина · перенос в Dream Pulse TTS',
    engine: DreamVoiceEngine.irinaMigrationPending,
    canSynthesize: false,
  );

  /// Four deliberately separate, AI-designed female identities.
  /// Similar source audio duration is not evidence of speaker equivalence.
  static const references = <DreamVoiceDescriptor>[
    DreamVoiceDescriptor(
      id: 'dream_ref_hello',
      label: 'Авторский голос 1 · Привет',
      engine: DreamVoiceEngine.sileroCustomPending,
      canSynthesize: false,
      referenceFile: 'hello.wav',
    ),
    DreamVoiceDescriptor(
      id: 'dream_ref_calm',
      label: 'Авторский голос 2 · Ты справляешься',
      engine: DreamVoiceEngine.sileroCustomPending,
      canSynthesize: false,
      referenceFile: 'calm.wav',
    ),
    DreamVoiceDescriptor(
      id: 'dream_ref_weather',
      label: 'Авторский голос 3 · Как погода за окном',
      engine: DreamVoiceEngine.sileroCustomPending,
      canSynthesize: false,
      referenceFile: 'weather.wav',
    ),
    DreamVoiceDescriptor(
      id: 'dream_ref_long',
      label: 'Авторский голос 4 · Не спрашивай сколько',
      engine: DreamVoiceEngine.sileroCustomPending,
      canSynthesize: false,
      referenceFile: 'long.wav',
    ),
  ];

  /// No voice is playable until a verified model and native synthesizer exist.
  static const playable = <DreamVoiceDescriptor>[];

  static const all = <DreamVoiceDescriptor>[irina, ...references];

  static DreamVoiceDescriptor? find(String id) {
    for (final voice in all) {
      if (voice.id == id) return voice;
    }
    return null;
  }
}

class DreamSileroEmbeddedSpec {
  const DreamSileroEmbeddedSpec._();

  static const baseModel = 'v5_5_ru';
  static const license = 'CC BY-NC-SA 4.0';
  static const nativeRuntimeReady = false;
  static const source = 'https://github.com/snakers4/silero-models';
  static const expectedFiles = <String>[
    'tts_mel.ptl',
    'head.ptl',
    'backbone.pte',
    'accentor.ptl',
    'homo.ptl',
    'stress.bin',
  ];
}
