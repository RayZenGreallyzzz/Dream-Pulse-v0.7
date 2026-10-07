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

  String get label {
    final n = name.toLowerCase();
    if (n.startsWith('baya')) return 'Baya';
    if (n.startsWith('kseniya')) return 'Kseniya';
    if (n.startsWith('xenia')) return 'Xenia';
    return name;
  }
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

  static const ruVoiceEngine = 'ru.kost.ruvoice';

  final AvatarSession session;
  final FlutterTts _tts = FlutterTts();
  final ElevenLabsVoiceBackend _neural = ElevenLabsVoiceBackend();
  final Random _random = Random();
  Timer? _mouthTimer;

  String _systemVoiceLabel = 'Системный русский голос';
  String? _defaultEngine;
  bool ruVoiceAvailable = false;
  bool ruVoiceActive = false;
  bool preferRuVoice = true;
  bool initialized = false;
  String lastVoiceError = '';
  String ruVoiceStatus = 'RuVoice: проверка...';
  VoiceOption? selectedVoice;
  List<VoiceOption> voiceOptions = const [];
  List<NeuralVoiceOption> neuralVoiceOptions = const [];
  String lastNeuralError = '';

  String get voiceLabel {
    if (ruVoiceActive) return selectedVoice?.label ?? 'Baya';
    if (neuralEnabled && neuralConfigured) return 'NEURAL · ${_neural.voiceName}';
    return _systemVoiceLabel;
  }

  bool get neuralEnabled => _neural.enabled;
  bool get neuralConfigured => _neural.configured;
  bool get neuralHasApiKey => _neural.hasApiKey;
  String get neuralVoiceId => _neural.voiceId;
  String get neuralVoiceName => _neural.voiceName;
  String get neuralStatus => _neural.status;

  Future<void> init() async {
    lastVoiceError = '';
    try {
      await _tts.awaitSpeakCompletion(true);
      _defaultEngine = (await _tts.getDefaultEngine)?.toString();
      await _tts.setLanguage('ru-RU');
      await _tts.setSpeechRate(0.47);
      await _tts.setPitch(0.97);
      await _tts.setVolume(1.0);

      try {
        await _neural.init();
      } catch (_) {
        // Cloud voice is optional; local/system TTS must still work.
      }

      await Future<void>.delayed(const Duration(milliseconds: 180));
      await refreshEngines(preferRuVoice: true);

      if (!ruVoiceActive) {
        await refreshVoices();
        if (voiceOptions.isNotEmpty) {
          await selectVoice(voiceOptions.first);
          ruVoiceStatus = ruVoiceAvailable
              ? 'Baya недоступна · системный русский голос активен'
              : 'RuVoice не найден · системный русский голос активен';
        } else {
          ruVoiceStatus = 'Русский TTS-голос не найден в Android';
        }
      }

      initialized = true;
    } catch (e) {
      initialized = true;
      lastVoiceError = e.toString();
      ruVoiceStatus = 'TTS init error: $e';
    }
  }

  Future<void> refreshEngines({bool preferRuVoice = false}) async {
    try {
      final dynamic raw = await _tts.getEngines;
      final engines = raw is List
          ? raw.map((e) => e.toString()).where((e) => e.isNotEmpty).toList()
          : <String>[];
      ruVoiceAvailable = engines.contains(ruVoiceEngine);
      ruVoiceStatus = ruVoiceAvailable ? 'RuVoice найден' : 'RuVoice не установлен';
      if (preferRuVoice && ruVoiceAvailable) {
        await useRuVoiceBaya();
      }
    } catch (e) {
      ruVoiceAvailable = false;
      ruVoiceActive = false;
      ruVoiceStatus = 'RuVoice недоступен: $e';
    }
  }

  Future<void> useRuVoiceBaya() async {
    await refreshEngines();
    preferRuVoice = true;
    if (!ruVoiceAvailable) {
      ruVoiceActive = false;
      ruVoiceStatus = 'RuVoice/Baya не установлена';
      throw StateError('RuVoice TTS не установлен');
    }

    await _neural.setEnabled(false);
    await _tts.stop();
    await _tts.setEngine(ruVoiceEngine);
    await Future<void>.delayed(const Duration(milliseconds: 180));
    await _tts.awaitSpeakCompletion(true);
    await _tts.setLanguage('ru-RU');
    ruVoiceActive = true;
    await refreshVoices();

    VoiceOption? baya;
    for (final voice in voiceOptions) {
      final name = voice.name.toLowerCase();
      if (name == 'baya-ru' || name.startsWith('baya')) {
        baya = voice;
        break;
      }
    }

    if (baya == null) {
      ruVoiceActive = false;
      ruVoiceStatus = 'RuVoice найден, но Baya не найдена';
      throw StateError('Голос Baya отсутствует в RuVoice');
    }

    await selectVoice(baya);
    _systemVoiceLabel = 'Baya';
    ruVoiceStatus = 'Baya активна';
  }

  Future<void> useDefaultSystemVoice() async {
    preferRuVoice = false;
    final engine = _defaultEngine;
    if (engine != null && engine.isNotEmpty && engine != ruVoiceEngine) {
      await _tts.stop();
      await _tts.setEngine(engine);
      await _tts.awaitSpeakCompletion(true);
    }
    ruVoiceActive = false;
    await _tts.setLanguage('ru-RU');
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
    if (name == 'baya-ru' || name.startsWith('baya')) score += 120;
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

  Future<void> previewBaya() async {
    await useRuVoiceBaya();
    await _speakSystem(
      'Привет. Я Dream Pulse. Ну что, похоже, теперь у меня наконец появился нормальный голос.',
      const VoiceExpression(rate: 0.46, pitch: 0.96),
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
    requireRuVoice = false;
    ruVoiceActive = false;
    await _neural.selectVoice(option);
    lastNeuralError = '';
  }

  Future<void> selectNeuralVoiceId(String voiceId) async {
    try {
      requireRuVoice = false;
      ruVoiceActive = false;
      await _neural.selectVoiceId(voiceId);
      lastNeuralError = '';
    } catch (e) {
      lastNeuralError = e.toString();
      rethrow;
    }
  }

  Future<void> setNeuralEnabled(bool enabled) async {
    if (enabled) {
      requireRuVoice = false;
      ruVoiceActive = false;
    }
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
    final shouldUseNeural = !ruVoiceActive && neuralConfigured && (neuralEnabled || forceNeural);

    // Prefer Baya, but never choose silence when the engine/voice is missing.
    if (!shouldUseNeural && preferRuVoice && !ruVoiceActive && ruVoiceAvailable) {
      try {
        await useRuVoiceBaya();
      } catch (e) {
        lastVoiceError = e.toString();
        ruVoiceStatus = 'Baya недоступна · использую системный русский голос';
      }
    }

    if (shouldUseNeural) {
      await _tts.stop();
      _beginExternalSpeech();
      try {
        await _neural.speak(trimmed, style);
        lastNeuralError = '';
        return;
      } catch (e) {
        lastNeuralError = e.toString();
        lastVoiceError = e.toString();
      } finally {
        _stopMouthMotion();
      }
    }

    await _speakSystem(trimmed, style);
  }

  Future<void> previewCurrent() async {
    await speak(
      'Привет. Я Dream Pulse. Если ты меня слышишь, голос работает.',
      expression: const VoiceExpression(rate: 0.46, pitch: 0.97),
    );
  }

  Future<void> _speakSystem(String text, VoiceExpression style) async {
    await _neural.stop();
    await _tts.stop();

    if (ruVoiceActive) {
      await _tts.setEngine(ruVoiceEngine);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await _tts.setLanguage('ru-RU');
      final voice = selectedVoice;
      if (voice != null) {
        await _tts.setVoice({'name': voice.name, 'locale': voice.locale});
      }
    }

    await _tts.awaitSpeakCompletion(true);
    await _tts.setSpeechRate(style.rate.clamp(0.35, 0.62));
    await _tts.setPitch(style.pitch.clamp(0.85, 1.12));
    await _tts.setVolume(style.volume.clamp(0.0, 1.0));
    final result = await _tts.speak(text, focus: true);
    if (result == 0) {
      lastVoiceError = 'Android TTS вернул код 0';
      throw StateError('Android TTS не запустил воспроизведение');
    }
    lastVoiceError = '';
    if (ruVoiceActive) {
      ruVoiceStatus = 'Baya активна';
    } else {
      ruVoiceStatus = 'Системный русский голос активен';
    }
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
