"""Apply minimal Android-compatible Dream Pulse Core bug fixes.

Runs after patches/v0152. Retains existing Workers/Processors/Critics,
Android UI, Flutter routing, and the existing database schema.
"""
from pathlib import Path
import shutil


def replace_once(filename: str, old: str, new: str) -> None:
    path = Path(filename)
    data = path.read_text(encoding="utf-8")
    found = data.count(old)
    if found != 1:
        raise RuntimeError(f"{filename}: expected one patch anchor, found {found}: {old[:80]!r}")
    path.write_text(data.replace(old, new, 1), encoding="utf-8")


def main() -> None:
    # Create an extension seam for stronger future source verifiers.
    target = Path("lib/core/evidence_gate.dart")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile("patches/v0153/lib/core/evidence_gate.dart", target)

    c = "lib/core/pulse_coordinator.dart"
    replace_once(c,
        "import 'dream_pulse_engine.dart';\n",
        "import 'dream_pulse_engine.dart';\nimport 'evidence_gate.dart';\n")
    replace_once(c,
        "    required this.tools,\n  });",
        "    required this.tools,\n    EvidenceGate? evidenceGate,\n"
        "  }) : evidenceGate = evidenceGate ?? const ConservativeEvidenceGate();")
    replace_once(c,
        "  final ToolRegistry tools;\n",
        "  final ToolRegistry tools;\n  final EvidenceGate evidenceGate;\n")
    replace_once(c,
        "    if (cleanPrompt.isEmpty) return;\n",
        "    if (cleanPrompt.isEmpty) return;\n"
        "    if (engine.running) {\n"
        "      throw StateError('CORE_BUSY: wait for the previous task to finish');\n"
        "    }\n")
    replace_once(c,
        """      final distinctHosts =
          sources.map((e) => e.host).where((e) => e.isNotEmpty).toSet().length;
      final evidenceConfidence = distinctHosts == 0
          ? 0.56
          : min(0.92, 0.74 + distinctHosts * 0.05);
""",
        """      // Count only independently relevant HTTPS snippets, not arbitrary
      // search results. This is a conservative heuristic, NOT fact-checking.
      final grounding = evidenceGate.assess(
        question: cleanPrompt,
        answer: answer,
        sources: sources,
      );
      final distinctHosts = grounding.supportedHosts;
      final evidenceConfidence = distinctHosts == 0
          ? 0.56
          : min(0.92, 0.74 + distinctHosts * 0.05);
""")
    replace_once(c,
        """      lastVerdict = verdict.accepted
          ? 'ACCEPT ${verdict.score.toStringAsFixed(2)}'
          : 'QUARANTINE ${verdict.score.toStringAsFixed(2)}';
""",
        """      lastVerdict = !grounding.sourceSupported
          ? 'UNVERIFIED · ${grounding.reason}'
          : verdict.accepted
              ? 'SOURCE-SUPPORTED ${verdict.score.toStringAsFixed(2)}'
              : 'QUARANTINE ${verdict.score.toStringAsFixed(2)}';
""")
    replace_once(c,
        "      if (verdict.accepted && distinctHosts >= 2) {",
        "      if (verdict.accepted && grounding.sourceSupported && memoryReady) {")
    replace_once(c,
        """        engine.absorbVerified(unit);
        status = 'ABSORB · verified knowledge';
        notifyListeners();
        if (memoryReady) {
          await memory.saveKnowledge(unit);
        }
""",
        """        // Write first, then publish in RAM, so a failed database write
        // never creates a misleading in-memory 'trusted' record.
        await memory.saveKnowledge(unit);
        engine.absorbVerified(unit);
        status = 'ABSORB · source-backed (heuristic)';
        notifyListeners();
""")

    e = "lib/core/dream_pulse_engine.dart"
    replace_once(e,
        """    if (existing == null) {
      trusted[key] = unit;
      coreMass += 0.45;
    } else {
      existing.tests += unit.tests;
      existing.successes += unit.successes;
      existing.confidence = max(existing.confidence, unit.confidence);
      coreMass += 0.08;
    }
""",
        """    if (existing == null) {
      trusted[key] = unit;
    } else {
      existing.tests += unit.tests;
      existing.successes += unit.successes;
      existing.confidence = max(existing.confidence, unit.confidence);
    }
    // Derived from persisted knowledge: stable across app restarts.
    coreMass = 100 + min(25.0, trusted.length * 0.45);
""")
    replace_once(e,
        """  void finishLiveTask() {
    for (final w in workers.where((w) => w.state == NodeState.active)) {
      w.state = NodeState.idle;
    }
    phase = 'IDLE';
""",
        """  void finishLiveTask() {
    for (final w in workers.where((w) => w.state == NodeState.active)) {
      w.state = NodeState.idle;
    }
    // A failed or cancelled task must not leave processors in a mature
    // or active state for the next request.
    nodes.removeWhere((n) => n.kind == NodeKind.processor);
    phase = 'IDLE';
""")

    m = "lib/storage/memory_store.dart"
    replace_once(m,
        """    await db.insert(
      'knowledge',
      {
        'topic': unit.topic,
        'rule': unit.rule,
        'confidence': unit.confidence,
        'tests': unit.tests,
        'successes': unit.successes,
        'created_at': (unit.createdAt ?? DateTime.now()).toIso8601String(),
      },
      conflictAlgorithm: mobile.ConflictAlgorithm.replace,
    );
""",
        """    if (unit.tests <= 0 || unit.successes < 0 ||
        unit.successes > unit.tests) {
      throw ArgumentError('Invalid evidence counters');
    }
    // A transaction avoids replacing accumulated statistics with only the
    // most recent unit. Works on the older Android SQLite versions too.
    await db.transaction((txn) async {
      final rows = await txn.query(
        'knowledge',
        where: 'topic = ? AND rule = ?',
        whereArgs: [unit.topic, unit.rule],
        limit: 1,
      );
      if (rows.isEmpty) {
        await txn.insert('knowledge', {
          'topic': unit.topic,
          'rule': unit.rule,
          'confidence': unit.confidence,
          'tests': unit.tests,
          'successes': unit.successes,
          'created_at': (unit.createdAt ?? DateTime.now()).toIso8601String(),
        });
      } else {
        final old = rows.first;
        final oldConfidence = (old['confidence'] as num).toDouble();
        await txn.update(
          'knowledge',
          {
            'confidence': oldConfidence > unit.confidence
                ? oldConfidence
                : unit.confidence,
            'tests': (old['tests'] as num).toInt() + unit.tests,
            'successes': (old['successes'] as num).toInt() + unit.successes,
          },
          where: 'id = ?',
          whereArgs: [old['id']],
        );
      }
    });
""")

    p = Path("pubspec.yaml")
    data = p.read_text(encoding="utf-8")
    lines = data.splitlines()
    lines = [
        "version: 0.15.3+37" if line.startswith("version:") else line
        for line in lines
    ]
    p.write_text("\n".join(lines) + "\n", encoding="utf-8")

    # Keep the regression tests executable on GitHub Actions.
    tests = Path("test/core_hardening_test.dart")
    tests.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile("patches/v0153/test/core_hardening_test.dart", tests)


if __name__ == "__main__":
    main()
