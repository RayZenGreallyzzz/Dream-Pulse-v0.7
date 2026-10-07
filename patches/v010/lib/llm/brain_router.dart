import 'dart:async';

import 'package:flutter/foundation.dart';

import 'deepseek_api_backend.dart';
import 'local_deepseek_backend.dart';

enum BrainMode { auto, local, api }

class BrainRouter extends ChangeNotifier {
  BrainRouter({
    required this.local,
    required this.api,
  });

  final LocalDeepSeekBackend local;
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
    if (mode == BrainMode.api) {
      if (!api.ready) {
        throw StateError('DeepSeek API не настроен');
      }
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
      // Heavy local R1 thinking is intentionally disabled on the 4 GB tablet.
      yield* local.streamAsk(prompt, thinking: false);
      return;
    }

    // AUTO prefers API because it keeps the tablet cool. If API is not
    // configured, use the local 1.5B model.
    if (api.ready) {
      var emitted = false;
      try {
        lastBackend = api.name;
        notifyListeners();
        await for (final chunk in api.streamAsk(
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
        'Нет доступного мозга: добавь DeepSeek API key или установи локальный DeepSeek 1.5B',
      );
    }

    lastBackend = local.name;
    notifyListeners();
    yield* local.streamAsk(prompt, thinking: false);
  }

  Future<void> stop() async {
    await Future.wait([
      local.stop(),
      api.stop(),
    ]);
  }
}
