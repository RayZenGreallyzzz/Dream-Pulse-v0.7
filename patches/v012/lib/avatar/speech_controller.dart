import 'dart:async';
import 'dart:math';

import '../llm/response_sanitizer.dart';
import '../voice/dream_pulse_voice_backend.dart';
import '../voice/elevenlabs_voice_backend.dart';
import '../voice/voice_expression.dart';
import 'avatar_session.dart';

class VoiceOption {
  const VoiceOption(this.name, this.label);

  final String name;
  final String label;
}

class SpeechController {
  SpeechController(this.session);

  final AvatarSession session;
  final DreamPulseVoiceBackend _local = DreamPulseVoiceBackend();
  final ElevenLabsVoiceBackend _neural = ElevenLabsVoiceBackend();
  final Random _random = Random();

  Timer? _mouthTimer;
  bool initialized = false;
  String lastVoiceError = '';
  String lastNeuralError = '';

  final List<VoiceOption> voiceOptions = const [
    VoiceOption('baya', 'Baya'),
    VoiceOption('kseniya', 'Kseniya'),
  ];

  VoiceOption selectedVoice = const VoiceOption('baya', 'Baya');

  String get voiceLabel =>
      neuralEnabled && neuralConfigured ? 'NEURAL · ${_neural.voiceName}' : selectedVoice.label;

  String get voiceStatus => _local.status;
  bool get localVoiceReady => _local.ready;

  double get voiceRate => _local.profile.rate;
  double get voicePitch => _local.profile.pitch;
  double get voiceTimbre => _local.profile.timbre;
  double get voiceVolume => _local.profile.volume;
  int get sentencePauseMs => _local.profile.sentencePauseMs;

  bool get neuralEnabled => _neural.enabled;
  bool get neuralConfigured => _neural.configured;
  bool get neuralHasApiKey => _neural.hasApiKey;
  String get neuralVoiceId => _neural.voiceId;
  String get neuralVoiceName => _neural.voiceName;
  String get neuralStatus => _neural.status;
  List<NeuralVoiceOption> neuralVoiceOptions = const [];

  Future<void> init() async {
    lastVoiceError = '';
    await _local.init();
    selectedVoice = voiceOptions.firstWhere(
      (v) => v.name == _local.profile.voice,
      orElse: () => voiceOptions.first,
    );
    try {
      await _neural.init();
    } catch (_) {
      // Cloud voice is optional. Local Dream Pulse Voice remains primary.
    }
    initialized = true;
  }

  Future<void> selectVoice(VoiceOption option) async {
    await _local.stop();
    await _local.selectVoice(option.name);
    selectedVoice = option;
    lastVoiceError = '';
  }

  void setRate(double value) => _local.setRate(value);
  void setPitch(double value) => _local.setPitch(value);
  void setTimbre(double value) => _local.setTimbre(value);
  void setVolume(double value) => _local.setVolume(value);
  void setSentencePause(int value) => _local.setSentencePause(value);

  Future<void> previewVoice(VoiceOption option) async {
    await selectVoice(option);
    await previewCurrent();
  }

  Future<void> previewCurrent() async {
    await speak(
      'Привет! Я Dream Pulse. Это мой локальный голос ${selectedVoice.label}.',
      expression: const VoiceExpression(rate: 0.47, pitch: 0.97),
    );
  }

  Future<void> saveNeuralApiKey(String apiKey) async {
    await _neural.saveApiKey(apiKey);
    lastNeuralError = '';
  }

  Future<List<NeuralVoiceOption>> loadNeuralVoices() async {
    try {
      neuralVoiceOptions = await _neural.fetchVoices();
      lastNeuralError = '';
      return neuralVoiceOptions;
    } catch (e) {
      lastNeuralError = e.toString();
      rethrow;
    }
  }

  Future<void> selectNeuralVoice(NeuralVoiceOption option) async {
    await _neural.selectVoice(option);
    lastNeuralError = '';
  }

  Future<void> selectNeuralVoiceId(String voiceId) async {
    try {
      await _neural.selectVoiceId(voiceId);
      lastNeuralError = '';
    } catch (e) {
      lastNeuralError = e.toString();
      rethrow;
    }
  }

  Future<void> setNeuralEnabled(bool enabled) async {
    await _neural.setEnabled(enabled);
  }

  Future<void> clearNeuralCredentials() async {
    await _neural.clearCredentials();
    neuralVoiceOptions = const [];
    lastNeuralError = '';
  }

  Future<void> previewNeuralVoice(NeuralVoiceOption option) async {
    await _local.stop();
    _beginExternalSpeech();
    try {
      await _neural.previewVoice(option);
      lastNeuralError = '';
    } catch (e) {
      lastNeuralError = e.toString();
      rethrow;
    } finally {
      _stopMouthMotion();
    }
  }

  Future<void> testNeuralVoice() async {
    if (!neuralConfigured) throw StateError('Сначала выбери Neural Voice');
    await speak(
      'Привет. Я Dream Pulse. Сегодня мне нравится, как я звучу.',
      expression: const VoiceExpression(
        rate: 0.47,
        pitch: 0.97,
        neuralStability: 0.44,
        neuralSimilarity: 0.86,
        neuralStyle: 0.10,
        neuralSpeed: 0.97,
      ),
      forceNeural: true,
    );
  }

  Future<void> speak(
    String text, {
    VoiceExpression? expression,
    bool forceNeural = false,
  }) async {
    if (!initialized) await init();

    final spoken = ResponseSanitizer.forSpeech(text);
    if (spoken.isEmpty) return;

    final style = expression ?? const VoiceExpression(rate: 0.47, pitch: 0.97);
    final useNeural = neuralConfigured && (neuralEnabled || forceNeural);

    await stop();

    if (useNeural) {
      _beginExternalSpeech();
      try {
        await _neural.speak(spoken, style);
        lastNeuralError = '';
        return;
      } catch (e) {
        lastNeuralError = e.toString();
        lastVoiceError = e.toString();
      } finally {
        _stopMouthMotion();
      }
    }

    _beginExternalSpeech();
    try {
      await _local.speak(spoken);
      lastVoiceError = '';
    } catch (e) {
      lastVoiceError = e.toString();
      rethrow;
    } finally {
      _stopMouthMotion();
    }
  }

  Future<void> stop() async {
    await Future.wait([
      _local.stop(),
      _neural.stop(),
    ]);
    _stopMouthMotion();
  }

  void _beginExternalSpeech() {
    session.speaking.value = true;
    _startMouthMotion();
  }

  void _startMouthMotion() {
    _mouthTimer?.cancel();
    _mouthTimer = Timer.periodic(const Duration(milliseconds: 90), (_) {
      if (!session.speaking.value) return;
      session.mouthOpen.value = 0.18 + (_random.nextDouble() * 0.72);
    });
  }

  void _stopMouthMotion() {
    _mouthTimer?.cancel();
    _mouthTimer = null;
    session.mouthOpen.value = 0.0;
    session.speaking.value = false;
  }

  void dispose() {
    _mouthTimer?.cancel();
    unawaited(_local.stop());
    unawaited(_neural.dispose());
  }
}
