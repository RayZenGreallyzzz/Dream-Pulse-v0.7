import 'package:flutter_tts/flutter_tts.dart';

/// Optional *system* bridge to the user's separate RuVoice application.
///
/// This is a compatibility/proof-of-speech backend, NOT an embedded Silero
/// inference engine. The future embedded adapter can replace this class
/// without changing SpeechController or the Dream Pulse Core.
class RuVoiceSileroBridge {
  static const enginePackage = 'ru.kost.ruvoice';
  static const voices = <String, String>{
    'ruvoice_baya': 'baya-ru',
    'ruvoice_kseniya': 'kseniya-ru',
    'ruvoice_xenia': 'xenia-ru',
  };

  final FlutterTts _tts = FlutterTts();
  bool available = false;
  bool _initialized = false;
  bool _speaking = false;
  String status = 'RuVoice: проверка установленного движка';

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final engines = await _tts.getEngines;
      final installed = engines is Iterable &&
          engines.any((engine) {
            if (engine is String) return engine == enginePackage;
            if (engine is Map) {
              return engine['name'] == enginePackage ||
                  engine['engine'] == enginePackage;
            }
            return false;
          });
      if (!installed) {
        status = 'RuVoice Silero не установлен (отдельное приложение)';
        return;
      }
      await _tts.setEngine(enginePackage);
      await _tts.setLanguage('ru-RU');
      await _tts.awaitSpeakCompletion(true);
      available = true;
      status = 'RuVoice Silero: системный TTS готов';
    } catch (error) {
      available = false;
      status = 'RuVoice Silero недоступен: $error';
    }
  }

  Future<void> speak(
    String text,
    String voiceId, {
    double rate = 1.0,
    double volume = 1.0,
  }) async {
    if (!_initialized) await init();
    if (!available) throw StateError(status);
    final nativeVoice = voices[voiceId];
    if (nativeVoice == null) {
      throw ArgumentError.value(voiceId, 'voiceId', 'Unknown Silero voice');
    }
    if (_speaking) await stop();
    _speaking = true;
    try {
      await _tts.setVoice(<String, String>{
        'name': nativeVoice,
        'locale': 'ru-RU',
      });
      await _tts.setSpeechRate((0.5 * rate).clamp(0.1, 1.0));
      await _tts.setVolume(volume.clamp(0.0, 1.0));
      status = 'RuVoice · $nativeVoice · говорит';
      final result = await _tts.speak(text);
      if (result != 1) {
        throw StateError('RuVoice returned unsuccessful TTS result: $result');
      }
      status = 'RuVoice Silero: готов';
    } finally {
      _speaking = false;
    }
  }

  Future<void> stop() async {
    _speaking = false;
    if (available) await _tts.stop();
  }

  Future<void> dispose() async {
    await stop();
    await _tts.shutdown();
  }
}
