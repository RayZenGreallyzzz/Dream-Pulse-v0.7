import 'package:flutter/services.dart';

/// Status of an in-app Silero v5_5_ru weight pack.
/// Staged weights are NOT a speech synthesizer until the native inference
/// backend is linked and proven on an Android device.
class SileroPackStatus {
  const SileroPackStatus({
    required this.modelStaged,
    required this.nativeRuntimeReady,
    required this.canSynthesize,
    required this.message,
  });

  final bool modelStaged;
  final bool nativeRuntimeReady;
  final bool canSynthesize;
  final String message;

  factory SileroPackStatus.fromMap(Map<dynamic, dynamic> value) {
    return SileroPackStatus(
      modelStaged: value['modelStaged'] == true,
      nativeRuntimeReady: value['nativeRuntimeReady'] == true,
      canSynthesize: value['canSynthesize'] == true,
      message: value['message']?.toString() ?? 'Неизвестный статус Silero',
    );
  }
}

class DreamPulseSileroPackBackend {
  const DreamPulseSileroPackBackend();

  static const _channel = MethodChannel('dream_pulse/silero-pack');

  Future<SileroPackStatus> status() async {
    final result = await _channel.invokeMapMethod<dynamic, dynamic>('status');
    return SileroPackStatus.fromMap(result ?? const {});
  }

  Future<SileroPackStatus> installFromLocalZip(String path) async {
    if (path.trim().isEmpty) {
      throw ArgumentError.value(path, 'path', 'Путь к архиву Silero пуст');
    }
    final result = await _channel.invokeMapMethod<dynamic, dynamic>(
      'install',
      <String, String>{'path': path},
    );
    return SileroPackStatus.fromMap(result ?? const {});
  }
}
