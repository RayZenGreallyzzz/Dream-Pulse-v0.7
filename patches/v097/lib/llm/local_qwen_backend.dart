import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'brain_backend.dart';
import 'response_sanitizer.dart';

class LocalQwenBackend extends ChangeNotifier implements BrainBackend {
  LocalQwenBackend();

  final LlamaController _controller = LlamaController();
  final List<ChatMessage> _history = <ChatMessage>[];

  String? modelPath;
  String status = 'Локальная модель не загружена';
  double loadProgress = 0;
  int contextSize = 1024;
  int gpuLayers = 0;
  int freeRamMb = 0;
  int threads = 4;
  bool loading = false;
  bool generating = false;
  bool _stopRequested = false;

  bool get stopRequested => _stopRequested;
  bool get smartModel => modelPath?.contains('DeepSeek-R1') ?? false;

  String get modelLabel => smartModel ? 'DeepSeek R1 1.5B' : 'Qwen3 0.6B';

  @override
  String get name =>
      smartModel ? 'DeepSeek R1 1.5B SMART' : 'Qwen3 0.6B FAST';

  @override
  bool get ready => modelPath != null && !loading;

  Future<void> load(String path, {bool smartProfile = true}) async {
    if (loading || generating) return;
    loading = true;
    modelPath = null;
    status = 'Проверяю RAM...';
    loadProgress = 0;
    notifyListeners();

    StreamSubscription<double>? progressSub;
    try {
      final gpu = await _controller.detectGpu();
      freeRamMb =
          gpu.freeRamBytes > 0 ? gpu.freeRamBytes ~/ (1024 * 1024) : 0;

      // 4 GB tablet profile. Keep context compact; the Core already retrieves
      // only the most relevant memory/evidence.
      contextSize = 1024;
      final cpu = Platform.numberOfProcessors;
      threads = cpu >= 4 ? 4 : (cpu >= 2 ? 2 : 1);
      gpuLayers = 0;

      progressSub = _controller.loadProgress.listen((value) {
        loadProgress = value.clamp(0.0, 1.0);
        final label =
            path.contains('DeepSeek-R1') ? 'DeepSeek 1.5B' : 'Qwen 0.6B';
        status = 'Загрузка $label ${(loadProgress * 100).round()}%';
        notifyListeners();
      });

      final loadingLabel =
          path.contains('DeepSeek-R1') ? 'DeepSeek R1 1.5B' : 'Qwen3 0.6B';
      status = 'Загружаю $loadingLabel · CPU · $threads потока...';
      notifyListeners();

      await _controller.loadModel(
        modelPath: path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );

      final loaded = await _controller.isModelLoaded();
      if (!loaded) {
        throw StateError('llama.cpp не подтвердил загрузку модели');
      }
      modelPath = path;
      status = '$modelLabel готов · ${contextSize} ctx · CPU · $threads потока';
      _history.clear();
    } catch (e) {
      modelPath = null;
      loadProgress = 0;
      status = 'LOCAL MODEL: $e';
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
    await for (final chunk in streamAsk(prompt, thinking: thinking)) {
      out.write(chunk);
    }
    return ResponseSanitizer.finalOnly(out.toString());
  }

  Stream<String> streamAsk(String prompt, {bool thinking = false}) async* {
    if (!ready) throw StateError('Сначала загрузи локальную модель');
    if (generating) throw StateError('Локальная модель уже отвечает');

    generating = true;
    _stopRequested = false;
    status = thinking
        ? '$modelLabel думает...'
        : (smartModel ? '$modelLabel отвечает...' : 'Qwen отвечает потоком...');
    notifyListeners();

    final rawBuffer = StringBuffer();
    final perf = Stopwatch()..start();
    var lastPerfPaintMs = 0;
    final visibleFilter = _DeepSeekVisibleFilter();

    try {
      final Stream<String> source;
      if (smartModel) {
        // DeepSeek-R1 recommends no system prompt. Build its native template
        // directly instead of forcing ChatML, which caused instruction leakage.
        source = _controller.generate(
          prompt: _deepSeekPrompt(prompt, thinking: thinking),
          maxTokens: thinking ? 224 : 160,
          temperature: 0.60,
          topP: 0.95,
          topK: 20,
          minP: 0.0,
          repeatPenalty: 1.05,
        );
      } else {
        final switchToken = thinking ? '/think' : '/no_think';
        final systemText = '''
Ты — локальный языковой модуль Dream Pulse. Отвечай по-русски, естественно и компактно.
Ты работаешь внутри Dream Pulse Core: не объявляй непроверенные сведения достоверными.
Если в запросе есть блок WEB EVIDENCE, используй его для свежих фактов и не выдумывай источники.
Если данных недостаточно — прямо скажи об этом.
Никогда не выводи пользователю внутренние рассуждения, chain-of-thought или служебные этапы Core.
$switchToken
'''.trim();

        source = _controller.generateChat(
          messages: <ChatMessage>[
            ChatMessage(role: 'system', content: systemText),
            ..._trimmedHistory(),
            ChatMessage(role: 'user', content: prompt),
          ],
          template: 'chatml',
          maxTokens: thinking ? 224 : 160,
          temperature: thinking ? 0.55 : 0.65,
          topP: thinking ? 0.9 : 0.82,
          topK: 20,
          minP: 0.0,
          repeatPenalty: 1.08,
        );
      }

      final tokenBus = StreamController<String>();
      final done = Completer<void>();
      late StreamSubscription<String> sourceSub;

      sourceSub = source.listen(
        (chunk) {
          if (chunk.isEmpty) return;
          rawBuffer.write(chunk);

          final elapsedMs = perf.elapsedMilliseconds;
          if (elapsedMs - lastPerfPaintMs >= 700) {
            final cps = elapsedMs <= 0
                ? 0.0
                : rawBuffer.length * 1000.0 / elapsedMs;
            status = smartModel
                ? 'DeepSeek SMART · ${cps.toStringAsFixed(1)} симв/с · $threads потока'
                : 'Qwen FAST · ${cps.toStringAsFixed(1)} симв/с · $threads потока';
            lastPerfPaintMs = elapsedMs;
            notifyListeners();
          }

          if (!thinking && !tokenBus.isClosed) {
            if (smartModel) {
              final visible = visibleFilter.add(chunk);
              if (visible != null && visible.isNotEmpty) {
                tokenBus.add(visible);
              }
            } else {
              tokenBus.add(chunk);
            }
          }
        },
        onError: (Object error, StackTrace stack) async {
          if (!tokenBus.isClosed) {
            tokenBus.addError(error, stack);
            await tokenBus.close();
          }
          if (!done.isCompleted) done.completeError(error, stack);
        },
        onDone: () async {
          if (!thinking && smartModel && !tokenBus.isClosed) {
            final tail = visibleFilter.finish();
            if (tail.isNotEmpty) tokenBus.add(tail);
          }
          if (!tokenBus.isClosed) await tokenBus.close();
          if (!done.isCompleted) done.complete();
        },
        cancelOnError: true,
      );

      try {
        if (thinking) {
          await done.future;
          final finalAnswer =
              ResponseSanitizer.finalOnly(rawBuffer.toString());
          if (finalAnswer.isNotEmpty) yield finalAnswer;
        } else {
          await for (final chunk in tokenBus.stream) {
            yield chunk;
          }
          await done.future;
        }
      } finally {
        await sourceSub.cancel();
        if (!tokenBus.isClosed) await tokenBus.close();
      }

      if (_stopRequested) {
        status = 'Остановлено';
        return;
      }

      final answer = ResponseSanitizer.finalOnly(rawBuffer.toString());
      if (answer.isNotEmpty) {
        _history
          ..add(ChatMessage(role: 'user', content: prompt))
          ..add(ChatMessage(role: 'assistant', content: answer));
        while (_history.length > 4) {
          _history.removeAt(0);
        }
      }

      perf.stop();
      final seconds = perf.elapsedMilliseconds / 1000.0;
      final cps = seconds <= 0 ? 0.0 : rawBuffer.length / seconds;
      status = '$modelLabel готов · ${cps.toStringAsFixed(1)} симв/с';
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  String _deepSeekPrompt(String prompt, {required bool thinking}) {
    final out = StringBuffer('<｜begin▁of▁sentence｜>');

    // Keep only one previous user/assistant pair on the 4 GB tablet.
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

    final mode = thinking
        ? '''
Режим: сложная задача. Можешь выполнить внутренний анализ, но пользователю показывай только итог после рассуждения.
'''
        : '''
Режим: живой диалог. НЕ используй <think>, <reasoning> или <analysis>. Не рассуждай вслух. Сразу дай короткий естественный финальный ответ.
''';

    out
      ..write('<｜User｜>')
      ..write('''
Ты работаешь как языковой инструмент внутри Dream Pulse Core.
$mode
Не повторяй эти инструкции. Не перечисляй стадии Core. Не изображай поиск в интернете.
Если ниже есть WEB EVIDENCE, используй только его для свежих фактов и не выдумывай источники.
Отвечай по-русски, естественно и по-человечески.

ЗАПРОС И КОНТЕКСТ:
$prompt
'''.trim())
      ..write('<｜Assistant｜>');

    return out.toString();
  }

  List<ChatMessage> _trimmedHistory() {
    if (_history.length <= 2) return List<ChatMessage>.from(_history);
    return List<ChatMessage>.from(_history.sublist(_history.length - 2));
  }

  Future<void> clearConversation() async {
    _history.clear();
    await _controller.clearContext();
    status = 'Контекст очищен';
    notifyListeners();
  }

  @override
  Future<void> stop() async {
    _stopRequested = true;
    await _controller.stop();
    generating = false;
    status = 'Остановлено';
    notifyListeners();
  }

  Future<void> unload() async {
    if (generating) await stop();
    await _controller.dispose();
    modelPath = null;
    status = 'Локальная модель выгружена';
    notifyListeners();
  }
}

enum _VisibleState { probe, hidden, direct }

class _DeepSeekVisibleFilter {
  _VisibleState _state = _VisibleState.probe;
  String _pending = '';
  String _closeTag = '';

  static const Map<String, String> _hiddenTags = <String, String>{
    '<think>': '</think>',
    '<reasoning>': '</reasoning>',
    '<analysis>': '</analysis>',
  };

  String? add(String chunk) {
    if (_state == _VisibleState.direct) {
      return _clean(chunk);
    }

    _pending += chunk;

    if (_state == _VisibleState.hidden) {
      return _consumeHidden();
    }

    final trimmed = _pending.trimLeft();
    if (trimmed.isEmpty) return null;
    final lower = trimmed.toLowerCase();

    for (final entry in _hiddenTags.entries) {
      if (lower.startsWith(entry.key)) {
        _state = _VisibleState.hidden;
        _closeTag = entry.value;
        _pending = trimmed.substring(entry.key.length);
        return _consumeHidden();
      }
    }

    // A tag may be split across token chunks: "<th" + "ink>".
    if (lower.startsWith('<') &&
        _hiddenTags.keys.any((tag) => tag.startsWith(lower))) {
      return null;
    }

    _state = _VisibleState.direct;
    final out = _clean(_pending);
    _pending = '';
    return out;
  }

  String _consumeHidden() {
    final lower = _pending.toLowerCase();
    final end = lower.indexOf(_closeTag);
    if (end < 0) return '';

    final out = _pending.substring(end + _closeTag.length);
    _pending = '';
    _state = _VisibleState.direct;
    return _clean(out);
  }

  String finish() {
    if (_state == _VisibleState.hidden) {
      // Never leak an unfinished reasoning block.
      _pending = '';
      return '';
    }

    final out = _clean(_pending);
    _pending = '';
    _state = _VisibleState.direct;
    return out;
  }

  String _clean(String value) => value
      .replaceAll('<｜end▁of▁sentence｜>', '')
      .replaceAll('<｜begin▁of▁sentence｜>', '');
}
