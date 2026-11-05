// ignore_for_file: avoid_relative_lib_imports
import 'package:flutter_test/flutter_test.dart';
import '../lib/voice/dream_voice_catalog.dart';

void main() {
  test('only Irina can currently synthesize speech', () {
    expect(DreamVoiceCatalog.playable.length, 1);
    final voice = DreamVoiceCatalog.playable.single;
    expect(voice.id, 'irina');
    expect(voice.engine, DreamVoiceEngine.piper);
    expect(voice.canSynthesize, isTrue);
    expect(DreamVoiceCatalog.find('zoey')?.id, 'irina');
  });

  test('all four private female reference recordings stay untrained', () {
    expect(DreamVoiceCatalog.references.length, 4);
    expect(DreamVoiceCatalog.references.every(
      (voice) => !voice.canSynthesize &&
          voice.engine == DreamVoiceEngine.customModelPending &&
          voice.referenceFile != null &&
          voice.referenceFile!.endsWith('.wav'),
    ), isTrue);
  });

  test('no external RuVoice or male stock voices appear in catalogue', () {
    final visibleIds = [
      ...DreamVoiceCatalog.playable,
      ...DreamVoiceCatalog.references,
    ].map((voice) => voice.id).toList();
    expect(visibleIds.toSet().length, visibleIds.length);
    for (final banned in [
      'ruvoice_baya', 'ruvoice_kseniya', 'ruvoice_xenia',
      'aidar', 'eugene',
    ]) {
      expect(visibleIds, isNot(contains(banned)));
      expect(DreamVoiceCatalog.find(banned), isNull);
    }
  });

  test('embedded Silero weight contract includes required modules', () {
    expect(DreamSileroEmbeddedSpec.baseModel, 'v5_5_ru');
    expect(DreamSileroEmbeddedSpec.license, contains('NC'));
    expect(DreamSileroEmbeddedSpec.baseModelComponents,
        containsAll(<String>['tts_mel.ptl', 'head.ptl', 'backbone.pte']));
    expect(DreamSileroEmbeddedSpec.customVoicesReady, isFalse);
  });
}
