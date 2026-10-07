import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'brain_backend.dart';

class GroqApiBackend extends ChangeNotifier implements BrainBackend {
  static const _storage = FlutterSecureStorage();
  static const _keySlot = 'dream_pulse_groq_api_key';
  static const model = 'openai/gpt-oss-120b';

  String _apiKey = '';
  String status = 'Groq Free не настроен';
  bool generating = false;
  bool _stopRequested = false;
  HttpClient? _client;

  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  bool get stopRequested => _stopRequested;

  @override
  String get name => 'GROQ FREE · GPT-OSS 120B';

  @override
  bool get ready => hasApiKey;

  Future<void> init() async {
    _apiKey = (await _storage.read(key: _keySlot) ?? '').trim();
    status = hasApiKey ? 'Groq Free готов' : 'Groq Free не настроен';
    notifyListeners();
  }

  Future<void> saveApiKey(String value) async {
    final key = value.trim();
    if (key.isEmpty) throw StateError('Groq API key пустой');
    await _storage.write(key: _keySlot, value: key);
    _apiKey = key;
    status = 'Groq Free готов';
    notifyListeners();
  }

  Future<void> clearApiKey() async {
    await _storage.delete(key: _keySlot);
    _apiKey = '';
    status = 'Groq Free не настроен';
    notifyListeners();
  }

  @override
  Future<String> ask(String prompt, {bool thinking = false}) async {
    final out = StringBuffer();
    await for (final chunk in streamAsk(prompt, thinking: thinking)) {
      out.write(chunk);
    }
    return out.toString().trim();
  }

  Stream<String> streamAsk(
    String prompt, {
    bool thinking = false,
  }) async* {
    if (!ready) throw StateError('Добавь бесплатный Groq API key');
    if (generating) throw StateError('Groq уже отвечает');

    generating = true;
    _stopRequested = false;
    status = thinking ? 'Groq 120B думает…' : 'Groq 120B отвечает…';
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    _client = client;
    final answer = StringBuffer();

    try {
      final request = await client.postUrl(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey')
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'text/event-stream');

      request.write(jsonEncode({
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content':
                'Ты языковой вычислитель внутри Dream Pulse Core. '
                'Отвечай по-русски естественно и точно. '
                'Не раскрывай внутренние рассуждения и не изображай работу памяти/поиска.',
          },
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
        'reasoning_effort': thinking ? 'high' : 'low',
        'reasoning_format': 'hidden',
        'max_completion_tokens': thinking ? 4096 : 1536,
      }));

      final response = await request.close().timeout(
        const Duration(seconds: 25),
      );

      if (response.statusCode != HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        if (response.statusCode == 429) {
          throw StateError('GROQ_LIMIT · бесплатный лимит временно исчерпан');
        }
        throw HttpException(
          'Groq HTTP ${response.statusCode}: ${_short(body)}',
        );
      }

      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())) {
        if (_stopRequested) break;
        if (!line.startsWith('data:')) continue;

        final data = line.substring(5).trim();
        if (data.isEmpty) continue;
        if (data == '[DONE]') break;

        Map<String, dynamic> json;
        try {
          json = jsonDecode(data) as Map<String, dynamic>;
        } catch (_) {
          continue;
        }

        final choices = json['choices'];
        if (choices is! List || choices.isEmpty) continue;
        final first = choices.first;
        if (first is! Map) continue;
        final delta = first['delta'];
        if (delta is! Map) continue;

        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          answer.write(content);
          yield content;
        }
      }

      if (_stopRequested) {
        status = 'Groq остановлен';
        return;
      }

      if (answer.toString().trim().isEmpty) {
        throw StateError('Groq не вернул финальный ответ');
      }

      status = 'Groq Free готов';
    } finally {
      client.close(force: true);
      _client = null;
      generating = false;
      notifyListeners();
    }
  }

  String _short(String value) {
    final compact = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 180 ? compact : '${compact.substring(0, 180)}…';
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    _client?.close(force: true);
    _client = null;
    generating = false;
    status = 'Groq остановлен';
    notifyListeners();
  }
}
