import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

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
  }) {
    return DreamPulseVoiceProfile(
      voice: voice ?? this.voice,
      rate: rate ?? this.rate,
      pitch: pitch ?? this.pitch,
      timbre: timbre ?? this.timbre,
      volume: volume ?? this.volume,
      sentencePauseMs: sentencePauseMs ?? this.sentencePauseMs,
    );
  }

  Map<String, Object> toNative() => {
        'voice': voice,
        'rate': rate,
        'pitch': pitch,
        'timbre': timbre,
        'volume': volume,
        'sentencePauseMs': sentencePauseMs,
      };
}

class DreamPulseVoiceBackend {
  DreamPulseVoiceBackend();

  static const _channel = MethodChannel('dream_pulse/voice');
  static const _storage = FlutterSecureStorage();

  static const _voiceKey = 'dream_pulse_voice_name';
  static const _rateKey = 'dream_pulse_voice_rate';
  static const _pitchKey = 'dream_pulse_voice_pitch';
  static const _timbreKey = 'dream_pulse_voice_timbre';
  static const _volumeKey = 'dream_pulse_voice_volume';
  static const _pauseKey = 'dream_pulse_voice_pause';

  DreamPulseVoiceProfile profile = const DreamPulseVoiceProfile(
    voice: 'baya',
    rate: 1.00,
    pitch: 1.00,
    timbre: -0.10,
    volume: 1.00,
    sentencePauseMs: 160,
  );

  String status = 'Dream Pulse Voice · запуск…';
  bool ready = false;
  bool speaking = false;

  Future<void> init() async {
    await _restore();
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      ready = result['modelPresent'] == true;
      status = ready
          ? 'LOCAL · Silero v5_5_ru · ${label(profile.voice)}'
          : 'Локальная голосовая модель не найдена';
      unawaited(_warmup());
    } catch (_) {
      ready = false;
      status = 'Dream Pulse Voice недоступен';
    }
  }

  Future<void> _warmup() async {
    try {
      await _channel.invokeMethod<void>('warmup');
      ready = true;
      status = 'LOCAL · Silero v5_5_ru · ${label(profile.voice)}';
    } catch (_) {
      // First real speak will surface a useful error if warmup failed.
    }
  }

  Future<void> speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    speaking = true;
    status = 'LOCAL · ${label(profile.voice)} · говорит';
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': clean,
        ...profile.toNative(),
      });
      ready = true;
      status = 'LOCAL · Silero v5_5_ru · ${label(profile.voice)}';
    } on PlatformException catch (e) {
      status = 'Голос: ${e.message ?? e.code}';
      rethrow;
    } finally {
      speaking = false;
    }
  }

  Future<void> stop() async {
    speaking = false;
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (_) {}
  }

  Future<void> preview() => speak(
        'Привет! Я Dream Pulse. Теперь мой голос работает локально и принадлежит только этому приложению.',
      );

  Future<void> selectVoice(String value) async {
    if (value != 'baya' && value != 'kseniya') {
      throw ArgumentError('Unknown Dream Pulse voice: $value');
    }
    profile = profile.copyWith(voice: value);
    status = 'LOCAL · Silero v5_5_ru · ${label(value)}';
    await _storage.write(key: _voiceKey, value: value);
  }

  void setRate(double value) {
    profile = profile.copyWith(rate: value.clamp(0.70, 1.40));
    unawaited(_storage.write(key: _rateKey, value: profile.rate.toString()));
  }

  void setPitch(double value) {
    profile = profile.copyWith(pitch: value.clamp(0.80, 1.20));
    unawaited(_storage.write(key: _pitchKey, value: profile.pitch.toString()));
  }

  void setTimbre(double value) {
    profile = profile.copyWith(timbre: value.clamp(-1.0, 1.0));
    unawaited(
      _storage.write(key: _timbreKey, value: profile.timbre.toString()),
    );
  }

  void setVolume(double value) {
    profile = profile.copyWith(volume: value.clamp(0.40, 1.60));
    unawaited(
      _storage.write(key: _volumeKey, value: profile.volume.toString()),
    );
  }

  void setSentencePause(int value) {
    profile = profile.copyWith(sentencePauseMs: value.clamp(0, 700));
    unawaited(
      _storage.write(
        key: _pauseKey,
        value: profile.sentencePauseMs.toString(),
      ),
    );
  }

  String label(String voice) => switch (voice) {
        'kseniya' => 'Kseniya',
        _ => 'Baya',
      };

  Future<void> _restore() async {
    final voice = await _storage.read(key: _voiceKey);
    final rate = double.tryParse(await _storage.read(key: _rateKey) ?? '');
    final pitch = double.tryParse(await _storage.read(key: _pitchKey) ?? '');
    final timbre = double.tryParse(await _storage.read(key: _timbreKey) ?? '');
    final volume = double.tryParse(await _storage.read(key: _volumeKey) ?? '');
    final pause = int.tryParse(await _storage.read(key: _pauseKey) ?? '');

    profile = profile.copyWith(
      voice: voice == 'kseniya' ? 'kseniya' : 'baya',
      rate: rate?.clamp(0.70, 1.40),
      pitch: pitch?.clamp(0.80, 1.20),
      timbre: timbre?.clamp(-1.0, 1.0),
      volume: volume?.clamp(0.40, 1.60),
      sentencePauseMs: pause?.clamp(0, 700),
    );
  }
}
