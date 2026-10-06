import 'dart:math';

import 'package:flutter/foundation.dart';

import 'critic_ring.dart';
import 'models.dart';

/// Live Dream Pulse state.
///
/// Unlike the old visual simulator, this engine never invents trusted
/// knowledge during idle ticks. Trusted knowledge can enter CORE only through
/// [absorbVerified], which is called by the real task coordinator after Critic.
class DreamPulseEngine extends ChangeNotifier {
  DreamPulseEngine() {
    _spawnInitialRing();
  }

  final CriticRing criticRing = const CriticRing();
  final List<PulseNode> nodes = <PulseNode>[];
  final Map<String, KnowledgeUnit> trusted = <String, KnowledgeUnit>{};

  double coreMass = 100;
  int generation = 0;
  int pulse = 0;
  bool running = false;
  String phase = 'IDLE';
  int rejectedByCritic = 0;
  String lastDomain = 'general';

  static const int maxWorkers = 48;
  static const int maxProcessors = 16;

  Iterable<PulseNode> get workers =>
      nodes.where((n) => n.kind == NodeKind.worker || n.kind == NodeKind.blank);
  Iterable<PulseNode> get processors => nodes.where(
      (n) => n.kind == NodeKind.processor && n.state != NodeState.assimilated);
  Iterable<PulseNode> get critics => nodes.where((n) => n.kind == NodeKind.critic);

  CoreSnapshot get snapshot => CoreSnapshot(
        mass: coreMass,
        generation: generation,
        workers: workers.length,
        processors: processors.length,
        critics: critics.length,
        trustedKnowledge: trusted.length,
        pulse: pulse,
      );

  void _spawnInitialRing() {
    const domains = ['code', '3d', 'research', 'memory', 'vision', 'action'];
    for (var i = 0; i < 18; i++) {
      nodes.add(PulseNode(
        id: 'w-$i',
        kind: NodeKind.worker,
        domain: domains[i % domains.length],
        state: NodeState.idle,
      ));
    }
    for (var i = 0; i < 3; i++) {
      nodes.add(PulseNode(
        id: 'critic-$i',
        kind: NodeKind.critic,
        domain: 'validation',
        state: NodeState.active,
        confidence: 0.9,
      ));
    }
  }

  void restoreTrusted(Iterable<KnowledgeUnit> units) {
    for (final unit in units) {
      if (unit.rule == 'validated-method') continue;
      trusted['${unit.topic}:${unit.rule}'] = unit;
    }
    coreMass = 100 + min(25.0, trusted.length * 0.45);
    notifyListeners();
  }

  void beginLiveTask(String domain) {
    running = true;
    pulse += 1;
    phase = 'EXPLORE';
    lastDomain = domain;
    final worker = _workerFor(domain);
    worker
      ..kind = NodeKind.worker
      ..state = NodeState.active
      ..experience += 1
      ..confidence = min(0.78, 0.52 + worker.experience * 0.025);
    notifyListeners();
  }

  PulseNode beginProcessor(String domain, {int evidenceCount = 0}) {
    phase = 'COMPRESS';
    final processor = _processorFor(domain);
    processor
      ..state = NodeState.active
      ..experience += max(1, evidenceCount)
      ..confidence = min(0.88, 0.58 + evidenceCount * 0.07);
    notifyListeners();
    return processor;
  }

  CriticVerdict reviewLive(
    String domain, {
    required double confidence,
    required int evidenceCount,
  }) {
    phase = 'CRITIC';
    final processor = _processorFor(domain);
    processor
      ..state = NodeState.mature
      ..experience = max(processor.experience, evidenceCount * 3 + 2)
      ..confidence = confidence.clamp(0.0, 0.99);
    final verdict = criticRing.review(processor);
    if (!verdict.accepted) {
      processor.state = NodeState.quarantined;
      rejectedByCritic += 1;
    }
    notifyListeners();
    return verdict;
  }

  void absorbVerified(KnowledgeUnit unit) {
    phase = 'ABSORB';
    final key = '${unit.topic}:${unit.rule}';
    final existing = trusted[key];
    if (existing == null) {
      trusted[key] = unit;
      coreMass += 0.45;
    } else {
      existing.tests += unit.tests;
      existing.successes += unit.successes;
      existing.confidence = max(existing.confidence, unit.confidence);
      coreMass += 0.08;
    }
    for (final p in processors.where((p) => p.domain == unit.topic)) {
      p.state = NodeState.assimilated;
    }
    notifyListeners();
  }

  void cleanLive() {
    phase = 'CLEAN';
    nodes.removeWhere((n) =>
        n.kind == NodeKind.processor &&
        (n.state == NodeState.assimilated || n.state == NodeState.quarantined));
    notifyListeners();
  }

  void spawnFromRealExperience(String domain) {
    phase = 'SPAWN';
    if (workers.length < maxWorkers && trusted.values.any((k) => k.topic == domain)) {
      nodes.add(PulseNode(
        id: 'blank-$generation-$pulse-${workers.length}',
        kind: NodeKind.blank,
        domain: domain,
        state: NodeState.idle,
      ));
    }
    notifyListeners();
  }

  void finishLiveTask() {
    for (final w in workers.where((w) => w.state == NodeState.active)) {
      w.state = NodeState.idle;
    }
    phase = 'IDLE';
    running = false;
    notifyListeners();
  }

  /// Kept only for compatibility with older UI code. It animates a harmless
  /// pulse and never creates or absorbs knowledge.
  Future<void> step() async {
    if (running) return;
    beginLiveTask('general');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    beginProcessor('general');
    await Future<void>.delayed(const Duration(milliseconds: 80));
    phase = 'CRITIC';
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    cleanLive();
    finishLiveTask();
  }

  Future<void> runPulses(int count) async {
    for (var i = 0; i < count; i++) {
      await step();
    }
  }

  PulseNode _workerFor(String domain) {
    final same = workers.where((w) => w.domain == domain).toList();
    if (same.isNotEmpty) return same.first;
    final reusable = workers.where((w) => w.kind == NodeKind.blank).toList();
    if (reusable.isNotEmpty) {
      reusable.first.domain = domain;
      return reusable.first;
    }
    final node = PulseNode(
      id: 'w-live-${nodes.length}',
      kind: NodeKind.worker,
      domain: domain,
      state: NodeState.idle,
    );
    nodes.add(node);
    return node;
  }

  PulseNode _processorFor(String domain) {
    final same = processors.where((p) => p.domain == domain).toList();
    if (same.isNotEmpty) return same.first;
    final node = PulseNode(
      id: 'p-live-$domain-$pulse',
      kind: NodeKind.processor,
      domain: domain,
      state: NodeState.idle,
    );
    nodes.add(node);
    return node;
  }
}
