import 'package:flutter_test/flutter_test.dart';

import '../lib/core/evidence_gate.dart';
import '../lib/core/models.dart';
import '../lib/net/tablet_web_search.dart';
import '../lib/storage/memory_store.dart';

void main() {
  const gate = ConservativeEvidenceGate();
  const question = 'Как работает трансформатор тока?';
  const answer =
      'Трансформатор тока используется для измерения больших токов '
      'и защиты электрических сетей.';
  const snippet =
      'Трансформатор тока работает в электрических сетях и '
      'используется для измерения больших токов и защиты оборудования.';

  test('two related HTTPS snippets from independent domains are eligible',
      () {
    final result = gate.assess(
      question: question,
      answer: answer,
      sources: const [
        SearchHit(
          title: 'Трансформатор тока',
          url: 'https://docs.example.org/transformer',
          snippet: snippet,
        ),
        SearchHit(
          title: 'Измерение тока',
          url: 'https://manuals.example.net/current',
          snippet: snippet,
        ),
      ],
    );
    expect(result.sourceSupported, isTrue);
    expect(result.supportedHosts, 2);
  });

  test('two subdomains of one site cannot impersonate independent sources',
      () {
    final result = gate.assess(
      question: question,
      answer: answer,
      sources: const [
        SearchHit(
          title: 'Трансформатор тока',
          url: 'https://docs.example.org/transformer',
          snippet: snippet,
        ),
        SearchHit(
          title: 'Трансформатор тока',
          url: 'https://blog.example.org/transformer',
          snippet: snippet,
        ),
      ],
    );
    expect(result.sourceSupported, isFalse);
    expect(result.supportedHosts, 1);
  });

  test('two unrelated snippets cannot be saved as evidence', () {
    final result = gate.assess(
      question: question,
      answer: 'На Луне обнаружено несколько новых океанов.',
      sources: const [
        SearchHit(
          title: 'Трансформатор тока',
          url: 'https://docs.example.org/transformer',
          snippet: snippet,
        ),
        SearchHit(
          title: 'Трансформатор тока',
          url: 'https://manuals.example.net/transformer',
          snippet: snippet,
        ),
      ],
    );
    expect(result.sourceSupported, isFalse);
  });

  test('plain HTTP snippets do not enter trusted knowledge', () {
    final result = gate.assess(
      question: question,
      answer: answer,
      sources: const [
        SearchHit(
          title: 'Трансформатор тока',
          url: 'http://docs.example.org/transformer',
          snippet: snippet,
        ),
        SearchHit(
          title: 'Трансформатор тока',
          url: 'https://manuals.example.net/transformer',
          snippet: snippet,
        ),
      ],
    );
    expect(result.sourceSupported, isFalse);
    expect(result.supportedHosts, 1);
  });

  test('repeated knowledge merges transactionally in SQLite', () async {
    final store = MemoryStore();
    await store.open();
    final rule =
        'regression-core-0153-${DateTime.now().microsecondsSinceEpoch}';
    try {
      await store.saveKnowledge(KnowledgeUnit(
        topic: 'code',
        rule: rule,
        confidence: 0.79,
        tests: 2,
        successes: 2,
      ));
      await store.saveKnowledge(KnowledgeUnit(
        topic: 'code',
        rule: rule,
        confidence: 0.91,
        tests: 3,
        successes: 2,
      ));

      final records = await store.loadKnowledge();
      final unit = records.singleWhere(
        (value) => value.topic == 'code' && value.rule == rule,
      );
      expect(unit.tests, 5);
      expect(unit.successes, 4);
      expect(unit.confidence, 0.91);
    } finally {
      await store.close();
    }
  });
}
