import 'dart:async';
import 'package:flutter/foundation.dart';

import '../net/pc_bridge.dart';
import 'local_qwen_backend.dart';

enum BrainMode { auto, local, pc }

class BrainRouter extends ChangeNotifier {
  BrainRouter({required this.local});

  final LocalQwenBackend local;
  BrainMode _mode = BrainMode.auto;

  BrainMode get mode => _mode;

  set mode(BrainMode value) {
    if (_mode == value) return;
    _mode = value;
    notifyListeners();
  }

  String pcHost = '';
  String pcToken = '';
  String lastBackend = 'none';

  Future<bool> pcAvailable() async {
    final host = pcHost.trim();
    if (host.isEmpty) return false;
    try {
      await PcBridge(host: host, token: pcToken.trim())
          .getState()
          .timeout(const Duration(milliseconds: 900));
      return true;
    } catch (_) {
      return false;
    }
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
    if (mode != BrainMode.local && await pcAvailable()) {
      final bridge = PcBridge(host: pcHost.trim(), token: pcToken.trim());
      final result = await bridge.submitAssistantTask(
        prompt,
        mode: allowWeb ? 'hybrid' : 'local',
        allowWeb: allowWeb,
      );
      lastBackend = 'PC Brain';
      notifyListeners();
      yield result['answer']?.toString() ?? result.toString();
      return;
    }

    if (mode == BrainMode.pc) {
      throw StateError('PC Brain недоступен');
    }

    lastBackend = local.name;
    notifyListeners();
    yield* local.streamAsk(prompt, thinking: thinking);
  }

  Future<void> stop() => local.stop();
}
