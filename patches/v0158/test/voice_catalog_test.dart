// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';
import '../lib/voice/dream_voice_catalog.dart';
import '../lib/voice/dream_pulse_voice_backend.dart';

void main() {
  test('five author-designed identities survive without Piper', () {
    expect(DreamVoiceCatalog.all.length, 5);
    final ids = DreamVoiceCatalog.all.map((voice) => voice.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(ids, contains('irina'));
    expect(DreamVoiceCatalog.references.length, 4);
    expect(DreamVoiceCatalog.find('zoey'), isNull);
  });

  test('Irina is separate from Silero training references', () {
    expect(DreamVoiceCatalog.irina.engine,
        DreamVoiceEngine.irinaMigrationPending);
    expect(DreamVoiceCatalog.references.every((voice) =>
        voice.engine == DreamVoiceEngine.sileroCustomPending), isTrue);
  });

  test('no untrained model is marked playable', () {
    expect(DreamVoiceCatalog.playable, isEmpty);
    expect(DreamVoiceCatalog.all.every((voice) => !voice.canSynthesize), isTrue);
    expect(DreamSileroEmbeddedSpec.nativeRuntimeReady, isFalse);
  });

  test('Piper removed: no download or synthesis is attempted', () async {
    final backend = DreamPulseVoiceBackend();
    expect(backend.ready, isFalse);
    await backend.speak('Привет, Dream Pulse.');
    expect(backend.ready, isFalse);
    expect(backend.status, contains('синтез ещё не подключён'));
    expect(() => backend.install(), throwsA(isA<StateError>()));
  });

  test('Silero base file contract has six modules and original license', () {
    expect(DreamSileroEmbeddedSpec.baseModel, 'v5_5_ru');
    expect(DreamSileroEmbeddedSpec.license, 'CC BY-NC-SA 4.0');
    expect(DreamSileroEmbeddedSpec.expectedFiles.length, 6);
    expect(DreamSileroEmbeddedSpec.expectedFiles,
        containsAll(['tts_mel.ptl', 'head.ptl', 'backbone.pte']));
  });
}
