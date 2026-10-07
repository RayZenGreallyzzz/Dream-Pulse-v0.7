import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'brain_backend.dart';
import 'response_sanitizer.dart';

class LocalDeepSeekBackend extends ChangeNotifier implements BrainBackend {
  final LlamaController _controller = LlamaController();
  final List<ChatMessage> _history = <ChatMessage>[];

  String? modelPath;
  String status = 'DeepSeek 1.5B не загружен';
  double loadProgress = 0;
  int contextSize = 1024;
  int gpuLayers = 0;
  int freeRamMb = 0;
  int threads = 4;
  bool loading = false;
  bool generating = false;
  bool _stopRequested = false;

  bool get stopRequested => _stopRequested;
  String get modelLabel => 'DeepSeek R1 1.5B';

  @override
  String get name => 'LOCAL · DeepSeek 1.5B';

  @override
  bool get ready => modelPath != null && !loading;

  Future<void> load(String path) async {
    if (loading || generating) return;
    loading = true;
    modelPath = null;
    status = 'Проверяю память…';
    loadProgress = 0;
    notifyListeners();

    StreamSubscription<double>? progressSub;
    try {
      final gpu = await _controller.detectGpu();
      freeRamMb =
          gpu.freeRamBytes > 0 ? gpu.freeRamBytes ~/ (1024 * 1024) : 0;

      contextSize = 1024;
      final cpu = Platform.numberOfProcessors;
      threads = cpu >= 4 ? 4 : (cpu >= 2 ? 2 : 1);
      gpuLayers = 0;

      progressSub = _controller.loadProgress.listen((value) {
        loadProgress = value.clamp(0.0, 1.0);
        status = 'Загрузка DeepSeek ${(loadProgress * 100).round()}%';
        notifyListeners();
      });

      status = 'Загружаю DeepSeek 1.5B · CPU · $threads потока…';
      notifyListeners();

      await _controller.loadModel(
        modelPath: path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );

      if (!await _controller.isModelLoaded()) {
        throw StateError('llama.cpp не подтвердил загрузку DeepSeek');
      }

      modelPath = path;
      _history.clear();
      status = 'DeepSeek 1.5B готов · CPU · $threads потока';
    } catch (e) {
      modelPath = null;
      loadProgress = 0;
      status = 'LOCAL ERROR · $e';
      rethrow;
    } finally {
      await progressSub?.cancel();
      loading = false;
      notifyListeners();
    }
  }

  @override
  Future<String> ask(String prompt, {bool thinking = false}) async {
    final out = StringBuffer();
    await for (final chunk in streamAsk(prompt)) {
      out.write(chunk);
    }
    return ResponseSanitizer.finalOnly(out.toString());
  }

  Stream<String> streamAsk(String prompt, {bool thinking = false}) async* {
    if (!ready) throw StateError('Сначала установи локальный DeepSeek 1.5B');
    if (generating) throw StateError('Локальный DeepSeek уже отвечает');

    generating = true;
    _stopRequested = false;
    status = 'DeepSeek 1.5B отвечает…';
    notifyListeners();

    final raw = StringBuffer();
    final visible = StringBuffer();
    final perf = Stopwatch()..start();
    Timer? watchdog;

    try {
      final source = _controller.generate(
        prompt: _prompt(prompt),
        maxTokens: 320,
        temperature: 0.58,
        topP: 0.90,
        topK: 20,
        minP: 0.0,
        repeatPenalty: 1.06,
      );

      watchdog = Timer(const Duration(seconds: 90), () async {
        if (!generating) return;
        _stopRequested = true;
        status = 'LOCAL TIMEOUT · переключись на API';
        notifyListeners();
        try {
          await _controller.stop();
        } catch (_) {}
      });

      var lastPaint = 0;
      await for (final chunk in source) {
        if (_stopRequested) break;
        if (chunk.isEmpty) continue;
        raw.write(chunk);

        final clean = _cleanChunk(chunk);
        if (clean.isNotEmpty) {
          visible.write(clean);
          yield clean;
        }

        final ms = perf.elapsedMilliseconds;
        if (ms - lastPaint > 700) {
          final cps = ms <= 0 ? 0.0 : raw.length * 1000.0 / ms;
          status = 'DeepSeek LOCAL · ${cps.toStringAsFixed(1)} симв/с';
          lastPaint = ms;
          notifyListeners();
        }
      }

      if (_stopRequested) {
        if (visible.isEmpty) {
          throw StateError('Локальный DeepSeek не успел ответить. Переключись на API.');
        }
        return;
      }

      final answer = ResponseSanitizer.finalOnly(visible.toString()).trim();
      if (answer.isEmpty) {
        throw StateError('DeepSeek 1.5B не сформировал ответ. Переключись на API.');
      }

      _history
        ..add(ChatMessage(role: 'user', content: prompt))
        ..add(ChatMessage(role: 'assistant', content: answer));
      while (_history.length > 4) {
        _history.removeAt(0);
      }

      final seconds = perf.elapsedMilliseconds / 1000.0;
      final cps = seconds <= 0 ? 0.0 : raw.length / seconds;
      status = 'DeepSeek 1.5B готов · ${cps.toStringAsFixed(1)} симв/с';
    } finally {
      watchdog?.cancel();
      perf.stop();
      generating = false;
      notifyListeners();
    }
  }

  String _prompt(String prompt) {
    final out = StringBuffer('<｜begin▁of▁sentence｜>');
    for (final message in _trimmedHistory()) {
      if (message.role == 'user') {
        out.write('<｜User｜>${message.content}');
      } else if (message.role == 'assistant') {
        out.write(
          '<｜Assistant｜>${ResponseSanitizer.finalOnly(message.content)}'
          '<｜end▁of▁sentence｜>',
        );
      }
    }

    out
      ..write('<｜User｜>')
      ..write('''
Ты языковой модуль внутри Dream Pulse Core.
Отвечай по-русски, естественно, без служебных этапов и без внутренних рассуждений.
Если есть WEB EVIDENCE, используй его для свежих фактов и не выдумывай источники.
Если данных недостаточно, скажи об этом прямо.

$prompt
'''.trim())
      ..write('<｜Assistant｜><think>\n\n</think>\n');

    return out.toString();
  }

  List<ChatMessage> _trimmedHistory() {
    if (_history.length <= 2) return List<ChatMessage>.from(_history);
    return List<ChatMessage>.from(_history.sublist(_history.length - 2));
  }

  String _cleanChunk(String value) => value
      .replaceAll('<｜end▁of▁sentence｜>', '')
      .replaceAll('<｜begin▁of▁sentence｜>', '')
      .replaceAll('<think>', '')
      .replaceAll('</think>', '');

  Future<void> clearConversation() async {
    _history.clear();
    await _controller.clearContext();
    status = 'Контекст очищен';
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    try {
      await _controller.stop();
    } catch (_) {}
    generating = false;
    status = 'Остановлено';
    notifyListeners();
  }

  Future<void> unload() async {
    if (generating) await stop();
    await _controller.dispose();
    modelPath = null;
    status = 'DeepSeek 1.5B выгружен';
    notifyListeners();
  }
}
