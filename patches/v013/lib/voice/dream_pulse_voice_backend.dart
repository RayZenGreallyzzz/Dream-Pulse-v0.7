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

  static const _sha256 = <String, String>{
    'accentor.ptl': '0b727755cbc9efb79852528561fcedc5543c627a611811d32c66f5a1b71ba9b1',
    'backbone.pte': 'a35bd43df063481995929fa84aada4aafd8e4ac982eb7ef95384f5c5314e6260',
    'head.ptl': 'f7ea3ea93de475639ea991d5befa975a73122711536f88cd79aeed9ee580e9a4',
    'tts_mel.ptl': 'cea5e77af3ae9f8ca45701ba51f5fadedf88ca924b571b6940d2b0a295451902',
  };

  static const _sizes = <String, int>{
    'accentor.ptl': 11002183,
    'backbone.pte': 53380480,
    'head.ptl': 4961893,
    'tts_mel.ptl': 28152216,
  };

  static const _totalBytes = 97596772;

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
  String lastInstallError = '';
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
    lastInstallError = '';
    status = 'Голос · подключение…';
    onProgress?.call(0.001);

    final dir = Directory(dirPath);
    await dir.create(recursive: true);
    var completedBytes = 0;

    try {
      for (final name in _files) {
        final target = File('$dirPath/$name');
        final tmp = File('$dirPath/.$name.part');
        if (await tmp.exists()) await tmp.delete();

        final expectedSize = _sizes[name]!;
        status = 'Голос · загрузка $name';

        await _downloadFile(
          '$_base/$name',
          tmp,
          expectedSize,
          (received) {
            final overall =
                (completedBytes + received) / _totalBytes;
            installProgress = overall.clamp(0.001, 0.999);
            onProgress?.call(installProgress);
          },
        );

        final got = (await sha256.bind(tmp.openRead()).first).toString();
        final wanted = _sha256[name]!;
        if (got.toLowerCase() != wanted) {
          await tmp.delete();
          throw StateError('SHA-256 mismatch: $name');
        }

        if (await target.exists()) await target.delete();
        await tmp.rename(target.path);

        completedBytes += expectedSize;
        installProgress = completedBytes / _totalBytes;
        onProgress?.call(installProgress);
      }

      final result =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      ready = result['modelPresent'] == true;
      if (!ready) {
        throw StateError('Voice pack installed but model check failed');
      }

      installProgress = 1.0;
      onProgress?.call(1.0);
      status = 'LOCAL · Silero v5_5_ru · ${label(profile.voice)}';
    } catch (e) {
      lastInstallError = e.toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('HttpException: ', '');
      status = 'Голос · ошибка: $lastInstallError';
      rethrow;
    } finally {
      installing = false;
    }
  }

  Future<void> _downloadFile(
    String url,
    File target,
    int expectedSize,
    void Function(int receivedBytes) onProgress,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20)
      ..idleTimeout = const Duration(seconds: 30);
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 8;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DreamPulse/0.13.1 Android',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException('HTTP ${response.statusCode}: $url');
      }

      var got = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 30),
        )) {
          sink.add(chunk);
          got += chunk.length;
          onProgress(got);
        }
        await sink.flush();
      } finally {
        await sink.close();
      }

      if (got != expectedSize) {
        throw StateError(
          'Неполная загрузка: ${target.uri.pathSegments.last} '
          '($got из $expectedSize байт)',
        );
      }
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
