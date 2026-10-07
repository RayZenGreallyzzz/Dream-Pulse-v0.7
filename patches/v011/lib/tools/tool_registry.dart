import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';

import 'attachments.dart';

class ToolRegistry {
  ToolRegistry()
      : _vision = GroqVisionTool(),
        _file = FileTextTool() {
    _video = VideoVisionTool(_vision);
  }

  final GroqVisionTool _vision;
  final FileTextTool _file;
  late final VideoVisionTool _video;

  final List<String> lastTrace = <String>[];

  Future<List<ToolRunResult>> runFor(
    String prompt,
    List<ChatAttachment> attachments,
  ) async {
    lastTrace.clear();
    if (attachments.isEmpty) return const [];

    final out = <ToolRunResult>[];
    final images = attachments.where((a) => a.isImage).take(3).toList();

    if (images.isNotEmpty) {
      lastTrace.add('VisionTool');
      try {
        final text = await _vision.analyzeFiles(
          images.map((e) => e.path).toList(),
          prompt,
        );
        out.add(ToolRunResult(tool: 'VisionTool', output: text));
      } catch (e) {
        out.add(ToolRunResult(
          tool: 'VisionTool',
          output: _publicError(e),
          ok: false,
        ));
      }
    }

    for (final video in attachments.where((a) => a.isVideo).take(2)) {
      lastTrace.add('VideoTool');
      try {
        final text = await _video.analyze(video.path, prompt);
        out.add(ToolRunResult(tool: 'VideoTool', output: text));
      } catch (e) {
        out.add(ToolRunResult(
          tool: 'VideoTool',
          output: _publicError(e),
          ok: false,
        ));
      }
    }

    for (final file in attachments.where((a) => a.isFile).take(3)) {
      lastTrace.add('FileTool');
      try {
        final text = await _file.read(file.path);
        out.add(ToolRunResult(tool: 'FileTool', output: text));
      } catch (e) {
        out.add(ToolRunResult(
          tool: 'FileTool',
          output: _publicError(e),
          ok: false,
        ));
      }
    }

    return out;
  }

  String evidenceText(List<ToolRunResult> runs, {int maxChars = 12000}) {
    if (runs.isEmpty) return '';
    final out = StringBuffer();
    for (final run in runs) {
      out.writeln('[${run.tool}] ${run.ok ? 'OK' : 'ERROR'}');
      out.writeln(run.output);
      out.writeln();
      if (out.length >= maxChars) break;
    }
    final text = out.toString();
    return text.length <= maxChars ? text : text.substring(0, maxChars);
  }

  String _publicError(Object e) {
    final raw = e.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
    if (raw.contains('401')) return 'Vision API key отклонён';
    if (raw.contains('429')) return 'Vision API временно достиг лимита';
    if (raw.contains('SocketException') || raw.contains('timed out')) {
      return 'Нет соединения с онлайн-инструментом';
    }
    return raw.length <= 180 ? raw : '${raw.substring(0, 180)}…';
  }
}

class GroqVisionTool {
  static const _storage = FlutterSecureStorage();
  static const _keySlot = 'dream_pulse_groq_api_key';
  static const _model = 'qwen/qwen3.8-27b';

  Future<String> analyzeFiles(List<String> paths, String prompt) async {
    final images = <_VisionImage>[];
    for (final path in paths.take(3)) {
      final file = File(path);
      if (!await file.exists()) continue;
      final bytes = await file.readAsBytes();
      if (bytes.lengthInBytes > 19 * 1024 * 1024) {
        throw StateError('Изображение больше 19 МБ');
      }
      images.add(_VisionImage(bytes, _mimeFor(path)));
    }
    if (images.isEmpty) throw StateError('Нет доступных изображений');
    return _analyze(images, prompt);
  }

  Future<String> analyzeBytes(
    List<Uint8List> bytes,
    String prompt, {
    String mime = 'image/jpeg',
  }) {
    final images = bytes.take(3).map((e) => _VisionImage(e, mime)).toList();
    if (images.isEmpty) throw StateError('Не удалось извлечь кадры видео');
    return _analyze(images, prompt);
  }

  Future<String> _analyze(List<_VisionImage> images, String prompt) async {
    final key = (await _storage.read(key: _keySlot) ?? '').trim();
    if (key.isEmpty) {
      throw StateError('Для VisionTool нужен сохранённый Groq key');
    }

    final content = <Map<String, dynamic>>[
      {
        'type': 'text',
        'text':
            'Ты VisionTool внутри Dream Pulse. Проанализируй визуальные данные для пользовательской задачи. '
            'Опиши только наблюдаемое, отделяй факты от предположений, отметь важные детали интерфейса/ошибок/объектов. '
            'Пользовательская задача: ${prompt.trim().isEmpty ? 'Проанализируй вложение.' : prompt.trim()}',
      },
      ...images.map((image) => {
            'type': 'image_url',
            'image_url': {
              'url':
                  'data:${image.mime};base64,${base64Encode(image.bytes)}',
            },
          }),
    ];

    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 20);
    try {
      final request = await client.postUrl(
        Uri.parse('https://api.groq.com/openai/v1/chat/completions'),
      );
      request.headers
        ..set(HttpHeaders.authorizationHeader, 'Bearer $key')
        ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8');

      final payload = {
        'model': _model,
        'messages': [
          {
            'role': 'user',
            'content': content,
          }
        ],
        'reasoning_effort': 'none',
        'max_completion_tokens': 1200,
        'stream': false,
      };
      request.add(utf8.encode(jsonEncode(payload)));

      final response = await request.close().timeout(
        const Duration(seconds: 45),
      );
      final body = await response.transform(utf8.decoder).join();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Vision HTTP ${response.statusCode}');
      }

      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw StateError('VisionTool вернул неизвестный формат');
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw StateError('VisionTool не вернул ответ');
      }
      final first = choices.first;
      if (first is! Map) throw StateError('VisionTool: пустой ответ');
      final message = first['message'];
      if (message is! Map) throw StateError('VisionTool: нет message');
      final text = (message['content'] ?? '').toString().trim();
      if (text.isEmpty) throw StateError('VisionTool: пустой текст');
      return text;
    } finally {
      client.close(force: true);
    }
  }

  String _mimeFor(String path) {
    final p = path.toLowerCase();
    if (p.endsWith('.png')) return 'image/png';
    if (p.endsWith('.webp')) return 'image/webp';
    if (p.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }
}

class VideoVisionTool {
  VideoVisionTool(this.vision);

  static const _media = MethodChannel('dream_pulse/media');

  final GroqVisionTool vision;

  Future<String> analyze(String path, String prompt) async {
    final frames = <Uint8List>[];
    for (final timeMs in const [0, 3000, 8000]) {
      try {
        final data = await _media.invokeMethod<Uint8List>(
          'videoFrame',
          {
            'path': path,
            'timeMs': timeMs,
          },
        );
        if (data != null && data.isNotEmpty) frames.add(data);
      } catch (_) {}
    }

    if (frames.isEmpty) {
      throw StateError('Не удалось извлечь кадры из видео');
    }

    return vision.analyzeBytes(
      frames,
      'Это ключевые кадры одного видео. Сравни кадры по времени и найди изменения/ошибки/действия. $prompt',
    );
  }
}

class FileTextTool {
  static const _textExtensions = {
    '.txt',
    '.md',
    '.json',
    '.yaml',
    '.yml',
    '.dart',
    '.py',
    '.js',
    '.ts',
    '.tsx',
    '.jsx',
    '.html',
    '.css',
    '.log',
    '.csv',
    '.xml',
    '.sh',
  };

  Future<String> read(String path) async {
    final file = File(path);
    if (!await file.exists()) throw StateError('Файл недоступен');
    final size = await file.length();
    final name = path.split(Platform.pathSeparator).last;
    final lower = name.toLowerCase();
    final isText = _textExtensions.any(lower.endsWith);

    if (!isText) {
      return 'Файл: $name · ${_prettyBytes(size)}. '
          'В v0.11 бинарные документы прикрепляются к чату, но содержимое автоматически читается только у текстовых/кодовых файлов.';
    }

    if (size > 1024 * 1024) {
      throw StateError('Текстовый файл больше 1 МБ');
    }

    var text = await file.readAsString();
    if (text.length > 14000) {
      text = '${text.substring(0, 14000)}\n…[обрезано ToolRegistry]';
    }
    return 'Файл: $name\n$text';
  }

  String _prettyBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _VisionImage {
  const _VisionImage(this.bytes, this.mime);

  final Uint8List bytes;
  final String mime;
}
