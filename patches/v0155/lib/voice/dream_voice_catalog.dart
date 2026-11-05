/// Female-only Dream Pulse voice registry.
///
/// Only Irina has working synthesis today. The four private WAV references
/// require an adapted/trainable model; they are not Silero speaker IDs.
enum DreamVoiceEngine { piper, embeddedSileroPending, customModelPending }

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

  /// Hidden legacy 'zoey' uses the same Piper Irina model and is preserved
  /// for already-stored settings. It is not a separate trained voice.
  static const legacyVoiceId = 'zoey';

  static const playable = <DreamVoiceDescriptor>[
    DreamVoiceDescriptor(
      id: 'irina',
      label: 'Ирина · локальная',
      engine: DreamVoiceEngine.piper,
      canSynthesize: true,
    ),
  ];

  /// These are private user-supplied recordings, not four TTS checkpoints.
  /// Training and transcript alignment must precede model-pack creation.
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
    if (id == legacyVoiceId) return playable.first;
    for (final voice in [...playable, ...references]) {
      if (voice.id == id) return voice;
    }
    return null;
  }
}

/// Explicit contract for a future *in-app* model based on Silero weights.
/// These paths are not shipped until the model has been converted, verified,
/// licensed and benchmarked. They must never be mistaken for voice profiles.
class DreamSileroEmbeddedSpec {
  const DreamSileroEmbeddedSpec._();

  static const baseModel = 'v5_5_ru';
  static const license = 'CC BY-NC-SA 4.0';
  static const sourceUrl = 'https://github.com/snakers4/silero-models';
  static const baseModelComponents = <String>[
    'tts_mel.ptl',
    'head.ptl',
    'backbone.pte',
    'accentor.ptl',
    'homo.ptl',
    'stress.bin',
  ];

  // Currently no verified trained custom checkpoint is embedded.
  static const customVoicesReady = false;
}
