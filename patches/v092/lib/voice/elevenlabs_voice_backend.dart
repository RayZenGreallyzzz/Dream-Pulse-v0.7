import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'voice_expression.dart';

class NeuralVoiceOption {
  const NeuralVoiceOption({
    required this.voiceId,
    required this.name,
    required this.previewUrl,
    this.description = '',
    this.gender = '',
    this.language = '',
  });

  final String voiceId;
  final String name;
  final String previewUrl;
  final String description;
  final String gender;
  final String language;

  String get subtitle {
    final parts = <String>[
      if (gender.isNotEmpty) gender,
      if (language.isNotEmpty) language,
      if (description.isNotEmpty) description,
    ];
    return parts.join(' · ');
  }
}

class ElevenLabsVoiceBackend {
  ElevenLabsVoiceBackend();

  static const _apiKeyStorage = 'dream_pulse_elevenlabs_api_key';
  static const _voiceIdStorage = 'dream_pulse_elevenlabs_voice_id';
  static const _voiceNameStorage = 'dream_pulse_elevenlabs_voice_name';
  static const _enabledStorage = 'dream_pulse_elevenlabs_enabled';

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  final AudioPlayer _player = AudioPlayer();

  String _apiKey = '';
  String _voiceId = '';
  String _voiceName = '';
  bool enabled = false;
  String status = 'NEURAL VOICE OFF';

  bool get hasApiKey => _apiKey.isNotEmpty;
  bool get configured => hasApiKey && _voiceId.isNotEmpty;
  String get voiceId => _voiceId;
  String get voiceName => _voiceName.isEmpty ? 'Neural voice' : _voiceName;

  Future<void> init() async {
    _apiKey = (await _secure.read(key: _apiKeyStorage) ?? '').trim();
    _voiceId = (await _secure.read(key: _voiceIdStorage) ?? '').trim();
    _voiceName = (await _secure.read(key: _voiceNameStorage) ?? '').trim();
    enabled = (await _secure.read(key: _enabledStorage)) == 'true';
    if (!configured) enabled = false;
    status = configured
        ? (enabled ? 'NEURAL READY · $voiceName' : 'NEURAL SAVED · OFF')
        : (hasApiKey ? 'API KEY SAVED · CHOOSE VOICE' : 'NEURAL VOICE OFF');
  }

  Future<void> saveApiKey(String value) async {
    final key = value.trim();
    if (key.isEmpty) return;
    _apiKey = key;
    await _secure.write(key: _apiKeyStorage, value: key);
    status = _voiceId.isEmpty ? 'API KEY SAVED · CHOOSE VOICE' : 'NEURAL READY · $voiceName';
  }

  Future<void> setEnabled(bool value) async {
    enabled = value && configured;
    await _secure.write(key: _enabledStorage, value: enabled ? 'true' : 'false');
    status = enabled
        ? 'NEURAL READY · $voiceName'
        : (configured ? 'NEURAL SAVED · OFF' : 'NEURAL VOICE OFF');
  }

  Future<void> clearCredentials() async {
    await stop();
    _apiKey = '';
    _voiceId = '';
    _voiceName = '';
    enabled = false;
    status = 'NEURAL VOICE OFF';
    await _secure.delete(key: _apiKeyStorage);
    await _secure.delete(key: _voiceIdStorage);
    await _secure.delete(key: _voiceNameStorage);
    await _secure.delete(key: _enabledStorage);
  }

  Future<List<NeuralVoiceOption>> fetchVoices() async {
    _requireKey();
    status = 'LOADING ELEVENLABS VOICES...';

    List<NeuralVoiceOption> result = const [];
    try {
      final filtered = await _getJson(Uri.https('api.elevenlabs.io', '/v2/voices', {
        'page_size': '50',
        'gender': 'female',
        'language': 'ru',
      }));
      result = _parseVoices(filtered);
    } catch (_) {
      // Some account/library combinations do not expose filter metadata.
      // Retry without filters instead of making the UI look broken.
    }

    if (result.isEmpty) {
      final all = await _getJson(Uri.https('api.elevenlabs.io', '/v2/voices', {
        'page_size': '50',
      }));
      result = _parseVoices(all);
    }

    result.sort((a, b) {
      final aScore = _voiceScore(a);
      final bScore = _voiceScore(b);
      if (aScore != bScore) return bScore.compareTo(aScore);
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });

    status = result.isEmpty
        ? 'NO ELEVENLABS VOICES FOUND'
        : 'ELEVENLABS · ${result.length} VOICES';
    return result;
  }

  Future<void> selectVoice(NeuralVoiceOption option) async {
    _voiceId = option.voiceId.trim();
    _voiceName = option.name.trim().isEmpty ? 'Neural voice' : option.name.trim();
    await _secure.write(key: _voiceIdStorage, value: _voiceId);
    await _secure.write(key: _voiceNameStorage, value: _voiceName);
    await setEnabled(true);
  }

  Future<void> selectVoiceId(String value) async {
    _requireKey();
    final id = value.trim();
    if (id.isEmpty) throw StateError('Voice ID пустой');

    final metadata = await _getJson(Uri.https('api.elevenlabs.io', '/v1/voices/$id'));
    final name = (metadata['name'] ?? 'Neural voice').toString().trim();
    await selectVoice(NeuralVoiceOption(
      voiceId: id,
      name: name.isEmpty ? 'Neural voice' : name,
      previewUrl: (metadata['preview_url'] ?? '').toString(),
      description: (metadata['description'] ?? '').toString(),
    ));
  }

  Future<void> previewVoice(NeuralVoiceOption option) async {
    await stop();
    status = 'PREVIEW · ${option.name}';
    try {
      if (option.previewUrl.trim().isNotEmpty) {
        await _play(UrlSource(option.previewUrl.trim()));
      } else {
        final bytes = await _synthesize(
          'Привет. Я Dream Pulse. Думаю, этот голос мне подходит.',
          voiceId: option.voiceId,
          expression: const VoiceExpression(
            rate: 0.47,
            pitch: 0.97,
            neuralStability: 0.46,
            neuralSimilarity: 0.86,
            neuralStyle: 0.08,
            neuralSpeed: 0.97,
          ),
        );
        await _play(BytesSource(bytes, mimeType: 'audio/mpeg'));
      }
      status = configured ? 'NEURAL READY · $voiceName' : 'PREVIEW COMPLETE';
    } catch (e) {
      status = _friendlyError(e);
      rethrow;
    }
  }

  Future<void> speak(String text, VoiceExpression expression) async {
    if (!enabled || !configured) {
      throw StateError('Neural voice is not configured');
    }

    await stop();
    status = 'NEURAL SPEAKING · $voiceName';
    try {
      final bytes = await _synthesize(
        text,
        voiceId: _voiceId,
        expression: expression,
      );
      await _play(BytesSource(bytes, mimeType: 'audio/mpeg'));
      status = 'NEURAL READY · $voiceName';
    } catch (e) {
      status = _friendlyError(e);
      rethrow;
    }
  }

  Future<Uint8List> _synthesize(
    String text, {
    required String voiceId,
    required VoiceExpression expression,
  }) async {
    _requireKey();
    final clean = text.trim();
    if (clean.isEmpty) throw StateError('Пустой текст для озвучки');

    final cue = expression.neuralCue.trim();
    final spokenText = cue.isEmpty ? clean : '$cue $clean';
    final uri = Uri.https(
      'api.elevenlabs.io',
      '/v1/text-to-speech/$voiceId',
      {'output_format': 'mp3_44100_128'},
    );

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.postUrl(uri);
      request.headers
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set('xi-api-key', _apiKey)
        ..set(HttpHeaders.acceptHeader, 'audio/mpeg');

      request.add(utf8.encode(jsonEncode({
        'text': spokenText,
        'model_id': 'eleven_v3',
        'voice_settings': {
          'stability': expression.neuralStability.clamp(0.0, 1.0),
          'similarity_boost': expression.neuralSimilarity.clamp(0.0, 1.0),
          'style': expression.neuralStyle.clamp(0.0, 1.0),
          'use_speaker_boost': true,
          'speed': expression.neuralSpeed.clamp(0.7, 1.2),
        },
      })));

      final response = await request.close().timeout(const Duration(seconds: 25));
      final bytes = await _readBytes(response);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final body = utf8.decode(bytes, allowMalformed: true);
        throw HttpException('ElevenLabs HTTP ${response.statusCode}: ${_short(body)}');
      }
      if (bytes.isEmpty) throw StateError('ElevenLabs вернул пустое аудио');
      return bytes;
    } finally {
      client.close(force: true);
    }
  }

  Future<Map<String, dynamic>> _getJson(Uri uri) async {
    _requireKey();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      final request = await client.getUrl(uri);
      request.headers
        ..set('xi-api-key', _apiKey)
        ..set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(const Duration(seconds: 15));
      final bytes = await _readBytes(response);
      final body = utf8.decode(bytes, allowMalformed: true);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException('ElevenLabs HTTP ${response.statusCode}: ${_short(body)}');
      }
      final decoded = jsonDecode(body);
      if (decoded is! Map) throw const FormatException('Unexpected ElevenLabs response');
      return Map<String, dynamic>.from(decoded);
    } finally {
      client.close(force: true);
    }
  }

  List<NeuralVoiceOption> _parseVoices(Map<String, dynamic> json) {
    final raw = json['voices'];
    if (raw is! List) return const [];
    final out = <NeuralVoiceOption>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final id = (map['voice_id'] ?? '').toString().trim();
      final name = (map['name'] ?? '').toString().trim();
      if (id.isEmpty || name.isEmpty) continue;
      final labelsRaw = map['labels'];
      final labels = labelsRaw is Map
          ? Map<String, dynamic>.from(labelsRaw)
          : const <String, dynamic>{};
      out.add(NeuralVoiceOption(
        voiceId: id,
        name: name,
        previewUrl: (map['preview_url'] ?? '').toString(),
        description: (map['description'] ?? labels['description'] ?? '').toString(),
        gender: (labels['gender'] ?? '').toString(),
        language: (labels['language'] ?? map['language'] ?? '').toString(),
      ));
    }
    return out;
  }

  int _voiceScore(NeuralVoiceOption voice) {
    final haystack = '${voice.gender} ${voice.language} ${voice.description} ${voice.name}'.toLowerCase();
    var score = 0;
    if (haystack.contains('female') || haystack.contains('жен')) score += 60;
    if (haystack.contains('ru') || haystack.contains('russian') || haystack.contains('рус')) score += 35;
    if (haystack.contains('convers')) score += 15;
    if (haystack.contains('warm') || haystack.contains('soft')) score += 8;
    return score;
  }

  Future<void> _play(Source source) async {
    final done = Completer<void>();
    late final StreamSubscription<void> sub;
    sub = _player.onPlayerComplete.listen((_) {
      if (!done.isCompleted) done.complete();
    });
    try {
      await _player.setVolume(1.0);
      await _player.play(source);
      await done.future.timeout(const Duration(seconds: 120));
    } on TimeoutException {
      await _player.stop();
      throw TimeoutException('Озвучка не завершилась вовремя');
    } finally {
      await sub.cancel();
    }
  }

  Future<Uint8List> _readBytes(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  String _friendlyError(Object error) {
    final text = error.toString();
    if (text.contains('401')) return 'NEURAL ERROR · API KEY';
    if (text.contains('402')) return 'NEURAL ERROR · CREDITS';
    if (text.contains('429')) return 'NEURAL ERROR · RATE LIMIT';
    if (text.contains('SocketException') || text.contains('TimeoutException')) {
      return 'NEURAL OFFLINE · SYSTEM FALLBACK';
    }
    return 'NEURAL ERROR · SYSTEM FALLBACK';
  }

  String _short(String value) {
    final clean = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return clean.length <= 280 ? clean : clean.substring(0, 280);
  }

  void _requireKey() {
    if (_apiKey.isEmpty) throw StateError('ElevenLabs API key не задан');
  }

  Future<void> stop() => _player.stop();

  Future<void> dispose() async {
    await _player.dispose();
  }
}
