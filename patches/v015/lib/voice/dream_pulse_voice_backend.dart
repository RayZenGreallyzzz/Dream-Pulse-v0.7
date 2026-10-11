import 'dart:async';
import 'dart:io';

import 'package:archive/archive_io.dart';
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

  static const _packUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
      'vits-piper-ru_RU-irina-medium.tar.bz2';
  static const _packSha256 =
      '1fc0f54e5e084fe287c07909f2f6e0ba6d857864cf800e3ab80286a4e8233008';
  static const _packBytes = 67153308;

  static const _voiceKey = 'dream_pulse_voice_name';
  static const _rateKey = 'dream_pulse_voice_rate';
  static const _pitchKey = 'dream_pulse_voice_pitch';
  static const _timbreKey = 'dream_pulse_voice_timbre';
  static const _volumeKey = 'dream_pulse_voice_volume';
  static const _pauseKey = 'dream_pulse_voice_pause';

  DreamPulseVoiceProfile profile = const DreamPulseVoiceProfile(
    voice: 'zoey',
    rate: 1.02,
    pitch: 1.05,
    timbre: 0.18,
    volume: 1.00,
    sentencePauseMs: 260,
  );

  String status = 'Dream Pulse Voice Core · запуск…';
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
          ? 'LOCAL · sherpa-onnx · ${label(profile.voice)}'
          : 'Dream Voice не установлен';
    } catch (_) {
      ready = false;
      status = 'Dream Pulse Voice Core недоступен';
    }
  }

  Future<void> install({void Function(double)? onProgress}) async {
    if (installing) return;
    final dirPath = _voiceDir;
    if (dirPath == null || dirPath.isEmpty) {
      throw StateError('Voice storage path is unavailable');
    }

    final dir = Directory(dirPath);
    await dir.create(recursive: true);

    installing = true;
    installProgress = 0;
    lastInstallError = '';
    status = 'Dream Voice · подключение…';
    onProgress?.call(0.001);

    final tmp = File('$dirPath/.dream-voice-irina.tar.bz2.part');
    final pack = File('$dirPath/.dream-voice-irina.tar.bz2');

    try {
      if (await tmp.exists()) await tmp.delete();
      if (await pack.exists()) await pack.delete();

      await _downloadFile(
        _packUrl,
        tmp,
        _packBytes,
        (received) {
          installProgress =
              ((received / _packBytes) * 0.94).clamp(0.001, 0.94);
          status =
              'Dream Voice · загрузка ${(installProgress * 100).round()}%';
          onProgress?.call(installProgress);
        },
      );

      status = 'Dream Voice · проверка SHA-256…';
      installProgress = 0.95;
      onProgress?.call(installProgress);

      final got = (await sha256.bind(tmp.openRead()).first).toString();
      if (got.toLowerCase() != _packSha256) {
        await tmp.delete();
        throw StateError('SHA-256 mismatch: Dream Voice pack');
      }

      await tmp.rename(pack.path);

      status = 'Dream Voice · распаковка…';
      installProgress = 0.97;
      onProgress?.call(installProgress);

      await extractFileToDisk(pack.path, dirPath);

      if (await pack.exists()) {
        await pack.delete();
      }

      final result =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      ready = result['modelPresent'] == true;
      if (!ready) {
        throw StateError('Voice pack extracted but model check failed');
      }

      installProgress = 1.0;
      onProgress?.call(1.0);
      status = 'LOCAL · sherpa-onnx · ${label(profile.voice)}';
    } catch (e) {
      lastInstallError = e
          .toString()
          .replaceFirst('Bad state: ', '')
          .replaceFirst('HttpException: ', '');
      status = 'Dream Voice · ошибка: $lastInstallError';
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
      ..connectionTimeout = const Duration(seconds: 25)
      ..idleTimeout = const Duration(seconds: 45);

    try {
      final request = await client.getUrl(Uri.parse(url));
      request.followRedirects = true;
      request.maxRedirects = 10;
      request.headers.set(
        HttpHeaders.userAgentHeader,
        'DreamPulse/0.15 Android',
      );
      request.headers.set(HttpHeaders.acceptHeader, 'application/octet-stream');

      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );

      if (response.statusCode != HttpStatus.ok &&
          response.statusCode != HttpStatus.partialContent) {
        throw HttpException('HTTP ${response.statusCode}: $url');
      }

      var got = 0;
      final sink = target.openWrite();
      try {
        await for (final chunk in response.timeout(
          const Duration(seconds: 45),
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
          'Неполная загрузка Dream Voice ($got из $expectedSize байт)',
        );
      }
    } finally {
      client.close(force: true);
    }
  }

  Future<void> speak(String text) async {
    final clean = text.trim();
    if (clean.isEmpty) return;
    if (!ready) throw StateError('Сначала установи Dream Voice');

    speaking = true;
    status = 'LOCAL · ${label(profile.voice)} · говорит';

    try {
      await _channel.invokeMethod<void>('speak', {
        'text': clean,
        ...profile.toNative(),
      }).timeout(
        const Duration(seconds: 60),
        onTimeout: () async {
          final state =
              await _channel.invokeMapMethod<String, dynamic>('status') ??
                  const {};
          final stage = state['lastStage']?.toString() ?? 'unknown';
          throw TimeoutException(
            'Dream Voice не ответил. Последний этап: $stage',
          );
        },
      );

      status = 'LOCAL · sherpa-onnx · ${label(profile.voice)}';
    } on PlatformException catch (e) {
      final state =
          await _channel.invokeMapMethod<String, dynamic>('status') ?? const {};
      final stage = state['lastStage']?.toString() ?? 'unknown';
      status = 'Dream Voice · ошибка на $stage';
      throw StateError('${e.message ?? e.code} · этап: $stage');
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
    if (value != 'zoey' && value != 'irina') {
      throw ArgumentError('Unknown Dream Pulse voice profile: $value');
    }

    if (value == 'zoey') {
      profile = profile.copyWith(
        voice: 'zoey',
        rate: 1.02,
        pitch: 1.05,
        timbre: 0.18,
        volume: 1.00,
        sentencePauseMs: 260,
      );
    } else {
      profile = profile.copyWith(
        voice: 'irina',
        rate: 1.00,
        pitch: 1.00,
        timbre: 0.00,
        volume: 1.00,
        sentencePauseMs: 180,
      );
    }

    status = ready
        ? 'LOCAL · sherpa-onnx · ${label(value)}'
        : 'Dream Voice не установлен';

    await _storage.write(key: _voiceKey, value: value);
    await _persistTuning();
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
        'irina' => 'Irina · base',
        _ => 'Dream · Zoey-style',
      };

  Future<void> _persistTuning() async {
    await Future.wait([
      _storage.write(key: _rateKey, value: profile.rate.toString()),
      _storage.write(key: _pitchKey, value: profile.pitch.toString()),
      _storage.write(key: _timbreKey, value: profile.timbre.toString()),
      _storage.write(key: _volumeKey, value: profile.volume.toString()),
      _storage.write(
        key: _pauseKey,
        value: profile.sentencePauseMs.toString(),
      ),
    ]);
  }

  Future<void> _restore() async {
    final voice = await _storage.read(key: _voiceKey);

    // Old Baya/Kseniya tuning is intentionally not reused. v0.15 starts from
    // the new Zoey-style reference profile unless the user already saved v0.15.
    if (voice != 'zoey' && voice != 'irina') return;

    final rate = double.tryParse(await _storage.read(key: _rateKey) ?? '');
    final pitch = double.tryParse(await _storage.read(key: _pitchKey) ?? '');
    final timbre = double.tryParse(await _storage.read(key: _timbreKey) ?? '');
    final volume = double.tryParse(await _storage.read(key: _volumeKey) ?? '');
    final pause = int.tryParse(await _storage.read(key: _pauseKey) ?? '');

    profile = profile.copyWith(
      voice: voice,
      rate: rate?.clamp(0.70, 1.40),
      pitch: pitch?.clamp(0.80, 1.20),
      timbre: timbre?.clamp(-1.0, 1.0),
      volume: volume?.clamp(0.40, 1.60),
      sentencePauseMs: pause?.clamp(0, 700),
    );
  }
}
