import 'dart:async';
import 'dart:math';

import 'package:flutter_tts/flutter_tts.dart';

import '../llm/response_sanitizer.dart';
import '../voice/elevenlabs_voice_backend.dart';
import '../voice/voice_expression.dart';
import 'avatar_session.dart';

class VoiceOption {
  const VoiceOption({required this.name, required this.locale});

  final String name;
  final String locale;

  String get label => name;
}

class SpeechController {
  SpeechController(this.session) {
    _tts.setStartHandler(() {
      session.speaking.value = true;
      _startMouthMotion();
    });
    _tts.setCompletionHandler(_stopMouthMotion);
    _tts.setCancelHandler(_stopMouthMotion);
    _tts.setErrorHandler((_) => _stopMouthMotion());
    _tts.setProgressHandler((text, start, end, word) {
      session.mouthOpen.value = 0.85;
    });
  }

  final AvatarSession session;
  final FlutterTts _tts = FlutterTts();
  final ElevenLabsVoiceBackend _neural = ElevenLabsVoiceBackend();
  final Random _random = Random();
  Timer? _mouthTimer;

  String _systemVoiceLabel = 'Системный русский голос';
  VoiceOption? selectedVoice;
  List<VoiceOption> voiceOptions = const [];
  List<NeuralVoiceOption> neuralVoiceOptions = const [];
  String lastNeuralError = '';

  String get voiceLabel => neuralEnabled && neuralConfigured
      ? 'NEURAL · ${_neural.voiceName}'
      : _systemVoiceLabel;
  bool get neuralEnabled => _neural.enabled;
  bool get neuralConfigured => _neural.configured;
  bool get neuralHasApiKey => _neural.hasApiKey;
  String get neuralVoiceId => _neural.voiceId;
  String get neuralVoiceName => _neural.voiceName;
  String get neuralStatus => _neural.status;

  Future<void> init() async {
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('ru-RU');
    await _tts.setSpeechRate(0.47);
    await _tts.setPitch(0.97);
    await _tts.setVolume(1.0);
    await _neural.init();
    await refreshVoices();
    if (voiceOptions.isNotEmpty) {
      await selectVoice(voiceOptions.first);
    }
  }

  Future<void> refreshVoices() async {
    try {
      final dynamic raw = await _tts.getVoices;
      if (raw is! List) {
        voiceOptions = const [];
        return;
      }

      final options = raw.whereType<Map>().where((voice) {
        final locale = (voice['locale'] ?? '').toString().toLowerCase();
        return locale.startsWith('ru');
      }).map((voice) {
        return VoiceOption(
          name: (voice['name'] ?? 'Русский голос').toString(),
          locale: (voice['locale'] ?? 'ru-RU').toString(),
        );
      }).toList();

      options.sort((a, b) => _voiceScore(b).compareTo(_voiceScore(a)));
      voiceOptions = options;
    } catch (_) {
      voiceOptions = const [];
    }
  }

  int _voiceScore(VoiceOption option) {
    final name = option.name.toLowerCase();
    var score = 0;
    if (name.contains('female') || name.contains('fem') || name.contains('жен')) score += 50;
    if (name.contains('network') || name.contains('neural') || name.contains('enhanced')) score += 25;
    if (name.contains('natural') || name.contains('premium')) score += 20;
    if (name.contains('local')) score += 4;
    return score;
  }

  Future<void> selectVoice(VoiceOption option) async {
    await _tts.setVoice({'name': option.name, 'locale': option.locale});
    selectedVoice = option;
    _systemVoiceLabel = option.name;
  }

  Future<void> previewVoice(VoiceOption option) async {
    await selectVoice(option);
    await _speakSystem(
      'Привет. Я Dream Pulse. Думаю, этот голос мне подходит.',
      const VoiceExpression(rate: 0.47, pitch: 0.97),
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
    await _tts.stop();
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
    final trimmed = ResponseSanitizer.finalOnly(text);
    if (trimmed.isEmpty) return;

    final style = expression ?? const VoiceExpression(rate: 0.47, pitch: 0.97);
    final shouldUseNeural = neuralConfigured && (neuralEnabled || forceNeural);

    if (shouldUseNeural) {
      await _tts.stop();
      _beginExternalSpeech();
      try {
        await _neural.speak(trimmed, style);
        lastNeuralError = '';
        return;
      } catch (e) {
        lastNeuralError = e.toString();
        // Online voice is enhancement, not a single point of failure.
        // Continue through the local Android TTS path below.
      } finally {
        _stopMouthMotion();
      }
    }

    await _speakSystem(trimmed, style);
  }

  Future<void> _speakSystem(String text, VoiceExpression style) async {
    await _neural.stop();
    await _tts.stop();
    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(style.rate.clamp(0.35, 0.62));
    await _tts.setPitch(style.pitch.clamp(0.85, 1.12));
    await _tts.setVolume(style.volume.clamp(0.0, 1.0));
    await _tts.speak(text, focus: true);
  }

  Future<void> stop() async {
    await Future.wait([
      _tts.stop(),
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
    _tts.stop();
    unawaited(_neural.dispose());
  }
}
