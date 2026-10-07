import 'dart:async';

import 'package:flutter/foundation.dart';

import 'deepseek_api_backend.dart';
import 'groq_api_backend.dart';
import 'local_deepseek_backend.dart';

enum BrainMode { auto, groq, local, deepseek }

class BrainRouter extends ChangeNotifier {
  BrainRouter({
    required this.local,
    required this.groq,
    required this.api,
  });

  final LocalDeepSeekBackend local;
  final GroqApiBackend groq;
  final DeepSeekApiBackend api;

  BrainMode _mode = BrainMode.auto;
  String lastBackend = 'none';

  BrainMode get mode => _mode;

  set mode(BrainMode value) {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
  }

  Future<String> ask(
    String prompt, {
    bool thinking = false,
    bool allowWeb = false,
  }) async {
    final out = StringBuffer();
    await for (final chunk in streamAsk(
      prompt,
      thinking: thinking,
      allowWeb: allowWeb,
    )) {
      out.write(chunk);
    }
    return out.toString();
  }

  Stream<String> streamAsk(
    String prompt, {
    bool thinking = false,
    bool allowWeb = false,
  }) async* {
    if (mode == BrainMode.groq) {
      if (!groq.ready) throw StateError('Groq Free не настроен');
      lastBackend = groq.name;
      notifyListeners();
      yield* groq.streamAsk(prompt, thinking: thinking);
      return;
    }

    if (mode == BrainMode.deepseek) {
      if (!api.ready) throw StateError('DeepSeek API не настроен');
      lastBackend = api.name;
      notifyListeners();
      yield* api.streamAsk(prompt, thinking: thinking);
      return;
    }

    if (mode == BrainMode.local) {
      if (!local.ready) {
        throw StateError('Локальный DeepSeek 1.5B не загружен');
      }
      lastBackend = local.name;
      notifyListeners();
      yield* local.streamAsk(prompt, thinking: false);
      return;
    }

    // AUTO never spends money. It prefers Groq Free, then falls back to LOCAL.
    if (groq.ready) {
      var emitted = false;
      try {
        lastBackend = groq.name;
        notifyListeners();
        await for (final chunk in groq.streamAsk(
          prompt,
          thinking: thinking,
        )) {
          emitted = true;
          yield chunk;
        }
        return;
      } catch (_) {
        if (emitted || !local.ready) rethrow;
      }
    }

    if (!local.ready) {
      throw StateError(
        'AUTO: настрой Groq Free или установи локальный DeepSeek 1.5B',
      );
    }

    lastBackend = local.name;
    notifyListeners();
    yield* local.streamAsk(prompt, thinking: false);
  }

  Future<void> stop() async {
    await Future.wait([
      local.stop(),
      groq.stop(),
      api.stop(),
    ]);
  }
}
