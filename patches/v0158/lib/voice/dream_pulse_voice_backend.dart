import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'dream_voice_catalog.dart';

class DreamPulseVoiceProfile {
  const DreamPulseVoiceProfile({
    required this.voice,
    required this.rate,
    required this.pitch,
    required this.timbre,
    required this.volume,
    required this.sentencePauseMs,
  });

  final String voice;
  final double rate;
  final double pitch;
  final double timbre;
  final double volume;
  final int sentencePauseMs;

  DreamPulseVoiceProfile copyWith({
    String? voice,
    double? rate,
    double? pitch,
    double? timbre,
    double? volume,
    int? sentencePauseMs,
  }) =>
      DreamPulseVoiceProfile(
        voice: voice ?? this.voice,
        rate: rate ?? this.rate,
        pitch: pitch ?? this.pitch,
        timbre: timbre ?? this.timbre,
        volume: volume ?? this.volume,
        sentencePauseMs: sentencePauseMs ?? this.sentencePauseMs,
      );
}

/// Dream Pulse TTS public API. No Piper, no external Android TTS, no RuVoice.
///
/// The native model-pack store can verify and stage original Silero model
/// weights, but it cannot speak until the separate native inference adapter
/// is implemented and proven. Never claim that staged weights are playable.
class DreamPulseVoiceBackend {
  static const _channel = MethodChannel('dream_pulse/tts');
  static const _storage = FlutterSecureStorage();
  static const _voiceKey = 'dream_pulse_tts_selected_voice';

  DreamPulseVoiceProfile profile = const DreamPulseVoiceProfile(
    voice: 'irina',
    rate: 1.0,
    pitch: 1.0,
    timbre: 0.0,
    volume: 1.0,
    sentencePauseMs: 220,
  );

  String status = 'Dream Pulse TTS · подготовка собственного движка';
  bool ready = false;
  bool modelStaged = false;
  bool speaking = false;
  bool installing = false;
  double installProgress = 0;
  String lastInstallError = '';

  Future<void> init() async {
    // Old Piper preferences and downloaded files are intentionally ignored.
    final stored = await _storage.read(key: _voiceKey);
    if (stored != null && DreamVoiceCatalog.find(stored) != null) {
      profile = profile.copyWith(voice: stored);
    }
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>('status') ??
          const <String, dynamic>{};
      modelStaged = info['modelStaged'] == true;
      // The native backend explicitly reports false until inference exists.
      ready = info['canSynthesize'] == true;
      status = info['message']?.toString() ??
          'Dream Pulse TTS · нативный движок ещё не подключён';
    } on PlatformException catch (error) {
      ready = false;
      modelStaged = false;
      status = 'Dream Pulse TTS · ошибка подключения: ${error.message}';
    } on MissingPluginException {
      ready = false;
      status = 'Dream Pulse TTS · Android-модуль не установлен';
    }
  }

  Future<void> install({void Function(double)? onProgress}) async {
    // Compatibility method with the existing UI, not a Piper downloader.
    throw StateError(
      'Piper удалён. Для Dream Pulse TTS нужен архив Silero, '
      'подготовленный через RuVoice export; используй импорт ZIP.',
    );
  }

  Future<String> importPack(String path) async {
    if (installing) throw StateError('Импорт уже выполняется');
    if (path.trim().isEmpty) throw ArgumentError('Путь к ZIP пуст');
    installing = true;
    lastInstallError = '';
    installProgress = 0;
    status = 'Dream Pulse TTS · проверка локального пакета…';
    try {
      final info = await _channel.invokeMapMethod<String, dynamic>(
            'install',
            <String, String>{'path': path},
          ) ??
          const <String, dynamic>{};
      modelStaged = info['modelStaged'] == true;
      ready = info['canSynthesize'] == true;
      installProgress = modelStaged ? 1.0 : 0.0;
      status = info['message']?.toString() ??
          'Веса сохранены. Синтез пока не подключён.';
      return status;
    } catch (error) {
      lastInstallError = error.toString();
      status = 'Dream Pulse TTS · ошибка пакета: $lastInstallError';
      rethrow;
    } finally {
      installing = false;
    }
  }

  Future<String> diagnose() async {
    await init();
    return '$status · выбран: ${label(profile.voice)}';
  }

  Future<void> speak(String text) async {
    if (text.trim().isEmpty) return;
    // Silent (no-crash) fallback while the native model adapter is unfinished.
    // Never substitute a system voice or accidentally launch old Piper.
    if (!ready) {
      status = 'Dream Pulse TTS: синтез ещё не подключён · '
          '${label(profile.voice)}';
      return;
    }
    // Future runtime will implement the same channel, requiring explicit
    // native "canSynthesize" status before allowing invocation.
    speaking = true;
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': text,
        'voice': profile.voice,
        'rate': profile.rate,
        'pitch': profile.pitch,
        'timbre': profile.timbre,
        'volume': profile.volume,
        'sentencePauseMs': profile.sentencePauseMs,
      });
    } finally {
      speaking = false;
    }
  }

  Future<void> stop() async {
    if (!speaking) return;
    speaking = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } on MissingPluginException {
      // No runtime has been linked yet.
    }
  }

  Future<void> selectVoice(String id) async {
    if (DreamVoiceCatalog.find(id) == null) {
      throw ArgumentError.value(id, 'voice', 'Неизвестный голос');
    }
    await stop();
    profile = profile.copyWith(voice: id);
    await _storage.write(key: _voiceKey, value: id);
    status = 'Dream Pulse TTS · ${label(id)} · модель готовится';
  }

  void setRate(double value) {
    profile = profile.copyWith(rate: value.clamp(0.70, 1.40));
  }

  void setPitch(double value) {
    profile = profile.copyWith(pitch: value.clamp(0.80, 1.20));
  }

  void setTimbre(double value) {
    profile = profile.copyWith(timbre: value.clamp(-1.0, 1.0));
  }

  void setVolume(double value) {
    profile = profile.copyWith(volume: value.clamp(0.40, 1.60));
  }

  void setSentencePause(int value) {
    profile = profile.copyWith(sentencePauseMs: value.clamp(0, 700));
  }

  String label(String id) =>
      DreamVoiceCatalog.find(id)?.label ?? 'Голос ещё не подготовлен';
}
