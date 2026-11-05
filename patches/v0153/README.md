# Dream Pulse v0.15.3 — Android Core hardening

This is a **bug-fix release**, not a Core rewrite. It preserves the Flutter
Android app, its existing Core, Workers, Processors, Critics, personality,
local/online model routing, voice engine, and SQLite database schema.

## Changes

- `ConservativeEvidenceGate`: an optional dependency-injection seam for
  future verifiers, with a conservative **heuristic** for source relevance.
  Only relevant HTTPS snippets from two independently hosted domains can
  be counted as evidence. This is **not** semantic claim-level fact-checking,
  and source agreement alone does not guarantee correctness.
- A single active `PulseCoordinator.askStream()` request at a time to avoid
  corrupting shared runtime state. Flutter UI remains unchanged.
- `MemoryStore.saveKnowledge()` updates existing evidence counters in a
  SQLite transaction instead of replacing accumulated statistics.
- Database writes are committed before accepted knowledge is published into
  volatile Core memory.
- Transient Processor nodes are cleaned up after success, cancellation or
  failure, without changing Worker classes or the CriticRing formula.
- `coreMass` is now derived from stored knowledge count and remains stable
  across restart rather than continuously accumulating on duplicate writes.
- A focused Flutter test suite checks evidence filtering and SQLite merges.

## Explicitly *not* done

- No new self-training, LoRA, PC Brain, Arduino or Blender execution.
- No network access to sources beyond the existing search snippets.
- No removal or silent migration of previously saved knowledge.
- No changes to voice, UI, avatar, LLM model settings or Android service.
- No claim that two independent search snippets prove the answer.

## Extension contract

`lib/core/evidence_gate.dart` defines `EvidenceGate`. A future
higher-quality verification strategy can implement it and be passed to
`PulseCoordinator(evidenceGate: ...)`, without changing DreamPulseEngine.

## CI

The `android-apk.yml` workflow restores the original sources, applies
v0.8 through v0.15.2 as usual, then runs
`python3 patches/v0153/patch.py` and
`flutter test test/core_hardening_test.dart` before creating an arm64 APK.

Review the GitHub Actions result before merging the PR. No local Android
build was performed during preparation of this patch.
