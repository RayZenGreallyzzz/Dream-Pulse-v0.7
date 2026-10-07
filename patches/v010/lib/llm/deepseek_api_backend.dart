import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'brain_backend.dart';

class DeepSeekApiBackend extends ChangeNotifier implements BrainBackend {
  static const _storage = FlutterSecureStorage();
  static const _keySlot = 'dream_pulse_deepseek_api_key';

  String _apiKey = '';
  String status = 'DeepSeek API не настроен';
  bool generating = false;
  bool _stopRequested = false;
  HttpClient? _client;

  bool get hasApiKey => _apiKey.trim().isNotEmpty;
  bool get stopRequested => _stopRequested;

  @override
  String get name => 'API · DeepSeek V4 Flash';

  @override
  bool get ready => hasApiKey;

  Future<void> init() async {
    _apiKey = (await _storage.read(key: _keySlot) ?? '').trim();
    status = hasApiKey ? 'DeepSeek API готов' : 'DeepSeek API не настроен';
    notifyListeners();
  }

  Future<void> saveApiKey(String value) async {
    final key = value.trim();
    if (key.isEmpty) {
      throw StateError('API key пустой');
    }
    await _storage.write(key: _keySlot, value: key);
    _apiKey = key;
    status = 'DeepSeek API готов';
    notifyListeners();
  }

  Future<void> clearApiKey() async {
    await _storage.delete(key: _keySlot);
    _apiKey = '';
    status = 'DeepSeek API не настроен';
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
    if (!hasApiKey) {
      throw StateError('Добавь DeepSeek API key в настройках');
    }
    if (generating) {
      throw StateError('DeepSeek API уже отвечает');
    }

    generating = true;
    _stopRequested = false;
    status = thinking ? 'DeepSeek API думает…' : 'DeepSeek API отвечает…';
    notifyListeners();

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    _client = client;
    final answer = StringBuffer();

    try {
      final request = await client.postUrl(
        Uri.parse('https://api.deepseek.com/chat/completions'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $_apiKey')
        ..set(HttpHeaders.contentTypeHeader, 'application/json')
        ..set(HttpHeaders.acceptHeader, 'text/event-stream');

      request.write(jsonEncode({
        'model': 'deepseek-v4-flash',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'stream': true,
        'thinking': {
          'type': thinking ? 'enabled' : 'disabled',
        },
        'max_tokens': thinking ? 2048 : 1024,
      }));

      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );

      if (response.statusCode != HttpStatus.ok) {
        final body = await response.transform(utf8.decoder).join();
        throw HttpException(
          'DeepSeek API HTTP ${response.statusCode}: ${_short(body)}',
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

        // reasoning_content intentionally stays hidden from the visible chat.
        final content = delta['content'];
        if (content is String && content.isNotEmpty) {
          answer.write(content);
          yield content;
        }
      }

      if (_stopRequested) {
        status = 'DeepSeek API остановлен';
        return;
      }

      if (answer.toString().trim().isEmpty) {
        throw StateError('DeepSeek API не вернул финальный ответ');
      }

      status = 'DeepSeek API готов';
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
    status = 'DeepSeek API остановлен';
    notifyListeners();
  }
}
