import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
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
  static const _channel = MethodChannel('dream_pulse/voice');
  static const _storage = FlutterSecureStorage();
  static const _base =
      'https://github.com/RayZenGreallyzzz/Dream-Pulse-v0.7/releases/download/voice-pack-v1';

  static const _voiceKey = 'dream_pulse_voice_name';
  static const _rateKey = 'dream_pulse_voice_rate';
  static const _pitchKey = 'dream_pulse_voice_pitch';
  static const _timbreKey = 'dream_pulse_voice_timbre';
  static const _volumeKey = 'dream_pulse_voice_volume';
  static const _pauseKey = 'dream_pulse_voice_pause';

  static const _files = <String>[
    'accentor.ptl',
    'backbone.pte',
    'head.ptl',
    'tts_mel.ptl',
  ];

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
  bool installing = false;
  double installProgress = 0;
  String? _voiceDir;

  Future<void> init() async {
    await _restore();
    try {
      final result =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      ready = result['modelPresent'] == true;
      _voiceDir = result['voiceDir']?.toString();
      status = ready
          ? 'LOCAL · Silero v5_5_ru · ${label(profile.voice)}'
          : 'Голосовой пакет не установлен';
    } catch (_) {
      ready = false;
      status = 'Dream Pulse Voice недоступен';
    }
  }

  Future<void> install({void Function(double)? onProgress}) async {
    if (installing) return;
    final dirPath = _voiceDir;
    if (dirPath == null || dirPath.isEmpty) {
      throw StateError('Voice storage path is unavailable');
    }

    installing = true;
    installProgress = 0;
    status = 'Голос · подготовка загрузки';
    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    try {
      final manifestText = await _downloadText('$_base/dream-pulse-voice-pack-v1.sha256');
      final expected = <String, String>{};
      for (final line in manifestText.split('\n')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 2) {
          expected[parts.last] = parts.first.toLowerCase();
        }
      }

      for (var i = 0; i < _files.length; i++) {
        final name = _files[i];
        final target = File('$dirPath/$name');
        final tmp = File('$dirPath/.$name.part');
        if (tmp.existsSync()) await tmp.delete();

        status = 'Голос · загрузка $name';
        await _downloadFile(
          '$_base/$name',
          tmp,
          (part) {
            installProgress = (i + part) / _files.length;
            onProgress?.call(installProgress);
          },
        );

        final wanted = expected[name];
        if (wanted == null) {
          throw StateError('Voice pack manifest does not contain $name');
        }
        final got = (await sha256.bind(tmp.openRead()).first).toString();
        if (got.toLowerCase() != wanted) {
          await tmp.delete();
          throw StateError('SHA-256 mismatch: $name');
        }

        if (target.existsSync()) await target.delete();
        await tmp.rename(target.path);
        installProgress = (i + 1) / _files.length;
        onProgress?.call(installProgress);
      }

      final result =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      ready = result['modelPresent'] == true;
      if (!ready) throw StateError('Voice pack installed but model check failed');
      status = 'LOCAL · Silero v5_5_ru · ${label(profile.voice)}';
    } finally {
      installing = false;
    }
  }

  Future<String> _downloadText(String url) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      return response.transform(utf8.decoder).join();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> _downloadFile(
    String url,
    File target,
    void Function(double) onProgress,
  ) async {
    final client = HttpClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('HTTP ${response.statusCode}');
      }
      final total = response.contentLength;
      var got = 0;
      final sink = target.openWrite();
      await for (final chunk in response) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) onProgress((got / total).clamp(0.0, 1.0));
      }
      await sink.flush();
      await sink.close();
    } finally {
      client.close(force: true);
    }
  }

  Future<void> speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (!ready) throw StateError('Сначала установи Baya + Kseniya');
    speaking = true;
    status = 'LOCAL · ${label(profile.voice)} · говорит';
    try {
      await _channel.invokeMethod<void>('speak', {
        'text': clean,
        ...profile.toNative(),
      });
      status = 'LOCAL · Silero v5_5_ru · ${label(profile.voice)}';
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

  Future<void> selectVoice(String value) async {
    if (value != 'baya' && value != 'kseniya') {
      throw ArgumentError('Unknown Dream Pulse voice: $value');
    }
    profile = profile.copyWith(voice: value);
    status = ready
        ? 'LOCAL · Silero v5_5_ru · ${label(value)}'
        : 'Голосовой пакет не установлен';
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
    unawaited(_storage.write(key: _timbreKey, value: profile.timbre.toString()));
  }

  void setVolume(double value) {
    profile = profile.copyWith(volume: value.clamp(0.40, 1.60));
    unawaited(_storage.write(key: _volumeKey, value: profile.volume.toString()));
  }

  void setSentencePause(int value) {
    profile = profile.copyWith(sentencePauseMs: value.clamp(0, 700));
    unawaited(_storage.write(
      key: _pauseKey,
      value: profile.sentencePauseMs.toString(),
    ));
  }

  String label(String voice) => voice == 'kseniya' ? 'Kseniya' : 'Baya';

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
