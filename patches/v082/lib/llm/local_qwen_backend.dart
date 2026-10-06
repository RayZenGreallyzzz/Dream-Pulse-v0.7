import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:llama_flutter_android/llama_flutter_android.dart';
import 'brain_backend.dart';

class LocalQwenBackend extends ChangeNotifier implements BrainBackend {
  LocalQwenBackend();

  final LlamaController _controller = LlamaController();
  final List<ChatMessage> _history = <ChatMessage>[];

  String? modelPath;
  String status = 'Qwen не загружен';
  double loadProgress = 0;
  int contextSize = 1024;
  int gpuLayers = 0;
  int freeRamMb = 0;
  int threads = 2;
  bool loading = false;
  bool generating = false;

  static const int minFreeRamMbFor17B = 1400;

  @override
  String get name => 'Qwen3 1.7B Local · 4GB SAFE';

  @override
  bool get ready => modelPath != null && !loading;

  Future<void> load(String path, {bool smartProfile = true}) async {
    if (loading || generating) return;
    loading = true;
    modelPath = null;
    status = 'Проверяю свободную RAM...';
    loadProgress = 0;
    notifyListeners();

    StreamSubscription<double>? progressSub;
    try {
      final gpu = await _controller.detectGpu();
      freeRamMb = gpu.freeRamBytes > 0
          ? gpu.freeRamBytes ~/ (1024 * 1024)
          : 0;

      // Strict 4 GB tablet profile. Android uses unified memory, therefore
      // GPU offload competes for the same RAM and can increase peak pressure.
      contextSize = 1024;
      threads = 2;
      gpuLayers = 0;

      if (freeRamMb > 0 && freeRamMb < minFreeRamMbFor17B) {
        throw StateError(
          'Для Qwen 1.7B сейчас свободно только $freeRamMb MB RAM. '
          'Нужно хотя бы ~$minFreeRamMbFor17B MB. Закрой тяжёлые приложения '
          'или используй лёгкий Qwen 0.6B.',
        );
      }

      progressSub = _controller.loadProgress.listen((value) {
        loadProgress = value.clamp(0.0, 1.0);
        status = 'Загрузка Qwen · 4GB SAFE ${(loadProgress * 100).round()}%';
        notifyListeners();
      });

      status = 'Загружаю Qwen3 1.7B · SAFE 1024 · CPU...';
      notifyListeners();
      await _controller.loadModel(
        modelPath: path,
        threads: threads,
        contextSize: contextSize,
        gpuLayers: gpuLayers,
      );

      final loaded = await _controller.isModelLoaded();
      if (!loaded) throw StateError('llama.cpp не подтвердил загрузку модели');
      modelPath = path;
      status = 'Qwen готов · SAFE ${contextSize} ctx · CPU · ${threads} потока · до загрузки RAM $freeRamMb MB';
      _history.clear();
    } catch (e) {
      modelPath = null;
      loadProgress = 0;
      status = 'Qwen SAFE: $e';
      rethrow;
    } finally {
      await progressSub?.cancel();
      loading = false;
      notifyListeners();
    }
  }

  @override
  Future<String> ask(String prompt, {bool thinking = false}) async {
    if (!ready) throw StateError('Сначала загрузи локальный Qwen');
    if (generating) throw StateError('Qwen уже отвечает');

    generating = true;
    status = thinking ? 'Qwen думает...' : 'Qwen отвечает...';
    notifyListeners();

    final switchToken = thinking ? '/think' : '/no_think';
    final systemText = '''
Ты — локальный голосовой ассистент Dream Pulse. Отвечай по-русски, естественно и компактно.
Если информации недостаточно — прямо скажи об этом. Не выдумывай результаты инструментов.
Устройство имеет ограниченную RAM, поэтому избегай чрезмерно длинных ответов.
$switchToken
'''.trim();

    final messages = <ChatMessage>[
      ChatMessage(role: 'system', content: systemText),
      ..._trimmedHistory(),
      ChatMessage(role: 'user', content: prompt),
    ];

    final buffer = StringBuffer();
    final completer = Completer<String>();
    late StreamSubscription<String> sub;

    try {
      sub = _controller.generateChat(
        messages: messages,
        template: 'chatml',
        maxTokens: thinking ? 256 : 192,
        temperature: thinking ? 0.6 : 0.7,
        topP: thinking ? 0.9 : 0.8,
        topK: 20,
        minP: 0.0,
        repeatPenalty: 1.08,
      ).listen(
        buffer.write,
        onError: (Object error, StackTrace stack) {
          if (!completer.isCompleted) completer.completeError(error, stack);
        },
        onDone: () {
          if (!completer.isCompleted) completer.complete(buffer.toString().trim());
        },
        cancelOnError: true,
      );

      final answer = await completer.future;
      await sub.cancel();
      if (answer.isNotEmpty) {
        _history
          ..add(ChatMessage(role: 'user', content: prompt))
          ..add(ChatMessage(role: 'assistant', content: answer));
        _capHistory();
      }
      status = 'Qwen готов';
      return answer;
    } finally {
      generating = false;
      notifyListeners();
    }
  }

  List<ChatMessage> _trimmedHistory() {
    if (_history.length <= 4) return List<ChatMessage>.from(_history);
    return List<ChatMessage>.from(_history.sublist(_history.length - 4));
  }

  void _capHistory() {
    while (_history.length > 6) {
      _history.removeAt(0);
    }
  }

  Future<void> clearConversation() async {
    _history.clear();
    await _controller.clearContext();
    status = 'Контекст очищен';
    notifyListeners();
  }

  @override
  Future<void> stop() async {
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
