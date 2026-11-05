// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../lib/voice/dream_voice_catalog.dart';

void main() {
  test('Voice catalogue contains Piper Irina and three Silero slots', () {
    expect(DreamVoiceCatalog.find('irina')?.engine, DreamVoiceEngine.piper);
    expect(DreamVoiceCatalog.playable
        .where((voice) => voice.engine == DreamVoiceEngine.ruVoiceSystemBridge)
        .length, 3);
    expect(DreamVoiceCatalog.playable.every((voice) => voice.canSynthesize),
        isTrue);
  });

  test('private user recordings are never advertised as trained TTS', () {
    expect(DreamVoiceCatalog.references.length, 4);
    expect(DreamVoiceCatalog.references
        .every((voice) => !voice.canSynthesize
            && voice.engine == DreamVoiceEngine.customModelPending
            && voice.referenceFile != null), isTrue);
  });

  test('catalogue voice identifiers are distinct', () {
    final ids = [
      ...DreamVoiceCatalog.playable,
      ...DreamVoiceCatalog.references,
    ].map((voice) => voice.id).toList();
    expect(ids.toSet().length, ids.length);
    expect(DreamVoiceCatalog.find('not-a-voice'), isNull);
  });
}
