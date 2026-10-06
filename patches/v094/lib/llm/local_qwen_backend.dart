import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';

import 'brain_backend.dart';
import 'response_sanitizer.dart';

class LocalQwenBackend extends ChangeNotifier implements BrainBackend {
  LocalQwenBackend();

  final LlamaController _controller = LlamaController();
  final List<ChatMessage> _history = <ChatMessage>[];

  String? modelPath;
  String status = 'Qwen 0.6B не загружен';
  double loadProgress = 0;
  int contextSize = 1536;
  int gpuLayers = 0;
  int freeRamMb = 0;
  int threads = 2;
  bool loading = false;
  bool generating = false;
  bool _stopRequested = false;

  bool get stopRequested => _stopRequested;

  @override
  String get name => 'Qwen3 0.6B Local';

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
      freeRamMb = gpu.freeRamBytes > 0 ? gpu.freeRamBytes ~/ (1024 * 1024) : 0;

      contextSize = (smartProfile && freeRamMb >= 1800) ? 2048 : 1536;
      threads = 2;
      gpuLayers = 0;

      progressSub = _controller.loadProgress.listen((value) {
        loadProgress = value.clamp(0.0, 1.0);
        status = 'Загрузка Qwen 0.6B ${(loadProgress * 100).round()}%';
        notifyListeners();
      });

      status = 'Загружаю Qwen3 0.6B · CPU...';
      notifyListeners();
      await _controller.loadModel(
        modelPath: path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );

      final loaded = await _controller.isModelLoaded();
      if (!loaded) throw StateError('llama.cpp не подтвердил загрузку Qwen 0.6B');
      modelPath = path;
      status = 'Qwen 0.6B готов · ${contextSize} ctx · CPU · $threads потока';
      _history.clear();
    } catch (e) {
      modelPath = null;
      loadProgress = 0;
      status = 'Qwen 0.6B: $e';
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

  /// Streams final-answer text for conversational mode.
  ///
  /// Deep thinking is buffered until completion so hidden reasoning never
  /// reaches UI/TTS. Normal /no_think generation is emitted as llama.cpp
  /// produces it.
  Stream<String> streamAsk(String prompt, {bool thinking = false}) async* {
    if (!ready) throw StateError('Сначала загрузи локальный Qwen 0.6B');
    if (generating) throw StateError('Qwen уже отвечает');

    generating = true;
    _stopRequested = false;
    status = thinking ? 'Qwen думает...' : 'Qwen отвечает потоком...';
    notifyListeners();

    final switchToken = thinking ? '/think' : '/no_think';
    final systemText = '''
Ты — локальный языковой модуль Dream Pulse. Отвечай по-русски, естественно и компактно.
Ты работаешь внутри Dream Pulse Core: не объявляй непроверенные сведения достоверными.
Если в запросе есть блок WEB EVIDENCE, используй его для свежих фактов и не выдумывай источники.
Если данных недостаточно — прямо скажи об этом.
Никогда не выводи пользователю внутренние рассуждения, chain-of-thought или служебные этапы Core.
$switchToken
'''.trim();

    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: systemText),
      ..._trimmedHistory(),
      ChatMessage(role: 'user', content: prompt),
    ];

    final rawBuffer = StringBuffer();
    try {
      final stream = _controller.generateChat(
        messages: messages,
        template: 'chatml',
        maxTokens: thinking ? 288 : 224,
        temperature: thinking ? 0.55 : 0.65,
        topP: thinking ? 0.9 : 0.82,
        topK: 20,
        minP: 0.0,
        repeatPenalty: 1.08,
      );

      if (thinking) {
        await for (final chunk in stream) {
          rawBuffer.write(chunk);
        }
        final finalAnswer = ResponseSanitizer.finalOnly(rawBuffer.toString());
        if (finalAnswer.isNotEmpty) yield finalAnswer;
      } else {
        await for (final chunk in stream) {
          if (chunk.isEmpty) continue;
          rawBuffer.write(chunk);
          yield chunk;
        }
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
        while (_history.length > 6) {
          _history.removeAt(0);
        }
      }
      status = 'Qwen 0.6B готов';
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  List<ChatMessage> _trimmedHistory() {
    if (_history.length <= 4) return List<ChatMessage>.from(_history);
    return List<ChatMessage>.from(_history.sublist(_history.length - 4));
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
    status = 'Qwen выгружен';
    notifyListeners();
  }
}
