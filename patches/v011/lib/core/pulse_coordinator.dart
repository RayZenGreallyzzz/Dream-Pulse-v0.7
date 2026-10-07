import 'dart:math';

import 'package:flutter/foundation.dart';

import '../llm/brain_router.dart';
import '../llm/response_sanitizer.dart';
import '../net/tablet_web_search.dart';
import '../personality/personality_engine.dart';
import '../storage/memory_store.dart';
import '../tools/attachments.dart';
import '../tools/tool_registry.dart';
import 'dream_pulse_engine.dart';
import 'models.dart';

/// Connects real assistant tasks to the Dream Pulse rings.
///
/// Raw user text, raw web pages and plain LLM output are never persisted as
/// trusted knowledge by default. Only an answer backed by at least two
/// independent web hosts can pass the local Critic and be absorbed.
class PulseCoordinator extends ChangeNotifier {
  PulseCoordinator({
    required this.engine,
    required this.memory,
    required this.brain,
    required this.webSearch,
    required this.personality,
    required this.tools,
  });

  final DreamPulseEngine engine;
  final MemoryStore memory;
  final BrainRouter brain;
  final TabletWebSearch webSearch;
  final PersonalityEngine personality;
  final ToolRegistry tools;

  bool memoryReady = false;
  String memoryStatus = 'SQLite: opening...';
  String status = 'CORE IDLE';
  String lastTask = '';
  String lastDomain = 'general';
  String lastVerdict = 'none';
  bool lastUsedWeb = false;
  List<SearchHit> lastSources = const [];
  List<ToolRunResult> lastToolRuns = const [];
  List<String> lastToolTrace = const [];

  Future<void> init() async {
    try {
      await memory.open();
      final purged = await memory.purgeSimulatedKnowledge();
      final restored = await memory.loadKnowledge();
      engine.restoreTrusted(restored);

      final restoredPersonality = await memory.loadPersonalityState();
      personality.restore(restoredPersonality);
      final changed = personality.ensureDaily(DateTime.now());
      if (restoredPersonality == null || changed) {
        await memory.savePersonalityState(personality.state);
      }

      memoryReady = true;
      memoryStatus = 'SQLite: ${restored.length} trusted${purged > 0 ? ' · purged $purged simulated' : ''}';
    } catch (e) {
      memoryReady = false;
      memoryStatus = 'SQLite error: $e';
    }
    notifyListeners();
  }

  Future<String> ask(
    String prompt, {
    bool thinking = false,
    bool allowWeb = false,
    List<ChatAttachment> attachments = const [],
  }) async {
    final out = StringBuffer();
    await for (final chunk in askStream(
      prompt,
      thinking: thinking,
      allowWeb: allowWeb,
      attachments: attachments,
    )) {
      out.write(chunk);
    }
    return ResponseSanitizer.finalOnly(out.toString());
  }

  /// Runs the full Dream Pulse pipeline while exposing model output as a
  /// stream. Core validation, memory absorption and personality updates still
  /// happen only after the complete final answer exists.
  Stream<String> askStream(
    String prompt, {
    bool thinking = false,
    bool allowWeb = false,
    List<ChatAttachment> attachments = const [],
  }) async* {
    final cleanPrompt = prompt.trim().isEmpty && attachments.isNotEmpty
        ? 'Проанализируй вложение.'
        : prompt.trim();
    if (cleanPrompt.isEmpty) return;

    if (personality.ensureDaily(DateTime.now()) && memoryReady) {
      await memory.savePersonalityState(personality.state);
    }

    final domain = _classifyDomain(
      cleanPrompt,
      attachments: attachments,
    );
    lastTask = cleanPrompt;
    lastDomain = domain;
    lastSources = const [];
    lastUsedWeb = false;
    lastToolRuns = const [];
    lastToolTrace = const [];
    lastVerdict = 'pending';

    engine.beginLiveTask(domain);
    status = 'EXPLORE · worker:$domain';
    notifyListeners();

    try {
      final toolRuns = attachments.isEmpty
          ? const <ToolRunResult>[]
          : await () async {
              status = 'TOOLS · analyze attachments';
              notifyListeners();
              final runs = await tools.runFor(cleanPrompt, attachments);
              lastToolRuns = runs;
              lastToolTrace = List<String>.from(tools.lastTrace);
              return runs;
            }();

      final useWeb = allowWeb || _needsFreshWeb(cleanPrompt);
      List<SearchHit> sources = const [];
      if (useWeb) {
        status = 'EXPLORE · WEB WORKER';
        notifyListeners();
        sources = await webSearch.search(cleanPrompt);
        lastSources = sources;
        lastUsedWeb = sources.isNotEmpty;
      }

      engine.beginProcessor(
        domain,
        evidenceCount: sources.length + toolRuns.where((r) => r.ok).length,
      );
      status = 'COMPRESS · processor:$domain';
      notifyListeners();

      final memoryContext = _memoryContext(cleanPrompt, domain);
      final webEvidence = webSearch.evidenceText(sources);
      final toolEvidence = tools.evidenceText(toolRuns);
      final augmented = _composePrompt(
        cleanPrompt,
        memoryContext: memoryContext,
        webEvidence: webEvidence,
        toolEvidence: toolEvidence,
        personalityInstructions: personality.promptInstructions,
      );

      status = thinking ? 'MODEL · deep final-only' : 'MODEL · streaming';
      notifyListeners();

      final answerBuffer = StringBuffer();
      await for (final chunk in brain.streamAsk(
        augmented,
        thinking: thinking,
        allowWeb: useWeb && sources.isEmpty,
      )) {
        if (chunk.isEmpty) continue;
        answerBuffer.write(chunk);
        yield chunk;
      }

      if (brain.lastBackend == brain.local.name && brain.local.stopRequested) {
        throw StateError('GENERATION_CANCELLED');
      }

      final answer = ResponseSanitizer.finalOnly(answerBuffer.toString());
      if (answer.isEmpty) {
        throw StateError('Модель не сформировала финальный ответ');
      }

      final distinctHosts =
          sources.map((e) => e.host).where((e) => e.isNotEmpty).toSet().length;
      final evidenceConfidence = distinctHosts == 0
          ? 0.56
          : min(0.92, 0.74 + distinctHosts * 0.05);

      final verdict = engine.reviewLive(
        domain,
        confidence: evidenceConfidence,
        evidenceCount: distinctHosts,
      );
      lastVerdict = verdict.accepted
          ? 'ACCEPT ${verdict.score.toStringAsFixed(2)}'
          : 'QUARANTINE ${verdict.score.toStringAsFixed(2)}';
      status = 'CRITIC · $lastVerdict';
      notifyListeners();

      if (verdict.accepted && distinctHosts >= 2) {
        final unit = KnowledgeUnit(
          topic: domain,
          rule: _knowledgeRule(cleanPrompt, answer),
          confidence: verdict.score,
          tests: distinctHosts,
          successes: distinctHosts,
          createdAt: DateTime.now(),
        );
        engine.absorbVerified(unit);
        status = 'ABSORB · verified knowledge';
        notifyListeners();
        if (memoryReady) {
          await memory.saveKnowledge(unit);
        }
      }

      engine.cleanLive();
      engine.spawnFromRealExperience(domain);
      status = 'SPAWN · live worker';
      notifyListeners();

      final personalityChanged =
          personality.observeConversation(cleanPrompt, answer);
      if (personalityChanged && memoryReady) {
        await memory.savePersonalityState(personality.state);
      }
    } catch (e) {
      lastVerdict = 'ERROR / NOT ABSORBED';
      status = 'CORE ERROR · no knowledge absorbed';
      notifyListeners();
      rethrow;
    } finally {
      if (memoryReady) {
        try {
          await memory.logPulse(engine.pulse, engine.phase, engine.coreMass);
        } catch (_) {}
      }
      engine.finishLiveTask();
      if (!status.startsWith('CORE ERROR')) {
        status =
            'CORE IDLE · ${engine.trusted.length} trusted · ${personality.moodLabel}';
      }
      notifyListeners();
    }
  }

  String _composePrompt(
    String prompt, {
    required String memoryContext,
    required String webEvidence,
    required String toolEvidence,
    required String personalityInstructions,
  }) {
    final out = StringBuffer();
    out.writeln(personalityInstructions);
    out.writeln('\nUSER TASK:');
    out.writeln(prompt);
    if (memoryContext.isNotEmpty) {
      out.writeln('\nTRUSTED CORE MEMORY:');
      out.writeln(memoryContext);
    }
    if (toolEvidence.isNotEmpty) {
      out.writeln('\nTOOL EVIDENCE (ephemeral Dream Pulse tool output):');
      out.writeln(toolEvidence);
      out.writeln('Use tool output as evidence for this answer. Do not claim the tool itself is the assistant.');
    }
    if (webEvidence.isNotEmpty) {
      out.writeln('\nWEB EVIDENCE (fresh worker output; summarize carefully):');
      out.writeln(webEvidence);
      out.writeln('Use the evidence for current facts. If sources conflict, say so.');
    }
    return out.toString().trim();
  }

  String _memoryContext(String prompt, String domain) {
    if (engine.trusted.isEmpty) return '';
    final words = _tokens(prompt);
    final scored = engine.trusted.values.map((unit) {
      var score = unit.topic == domain ? 3 : 0;
      final haystack = '${unit.topic} ${unit.rule}'.toLowerCase();
      for (final word in words) {
        if (word.length >= 4 && haystack.contains(word)) score += 1;
      }
      return (unit: unit, score: score);
    }).where((x) => x.score > 0).toList()
      ..sort((a, b) => b.score.compareTo(a.score));

    final out = StringBuffer();
    for (final item in scored.take(3)) {
      final rule = item.unit.rule.length > 700
          ? item.unit.rule.substring(0, 700)
          : item.unit.rule;
      out.writeln('- [${item.unit.confidence.toStringAsFixed(2)}] $rule');
    }
    return out.toString().trim();
  }

  String _knowledgeRule(String prompt, String answer) {
    final q = prompt.replaceAll(RegExp(r'\s+'), ' ').trim();
    final a = answer.replaceAll(RegExp(r'\s+'), ' ').trim();
    final qShort = q.length > 180 ? '${q.substring(0, 180)}…' : q;
    final aShort = a.length > 650 ? '${a.substring(0, 650)}…' : a;
    return 'Q: $qShort | VERIFIED SUMMARY: $aShort';
  }

  bool _needsFreshWeb(String prompt) {
    final p = prompt.toLowerCase();
    const markers = [
      'сегодня', 'сейчас', 'последн', 'новост', 'курс ', 'цена', 'погода',
      'найди', 'поиск', 'интернет', 'в интернете', 'проверь в сети', 'в сети',
      'сеть', 'онлайн', 'сайт', 'ссылк', 'проверь', 'посмотри в интернете',
      'актуальн', 'кто сейчас', 'web', 'browser',
      'latest', 'today', 'current', 'news', 'price', 'weather', 'search',
    ];
    return markers.any(p.contains);
  }

  String _classifyDomain(
    String prompt, {
    List<ChatAttachment> attachments = const [],
  }) {
    if (attachments.any((a) => a.isImage || a.isVideo)) return 'vision';
    if (attachments.any((a) => a.isFile)) return 'action';
    final p = prompt.toLowerCase();
    if (_containsAny(p, ['код', 'flutter', 'dart', 'python', 'github', 'api', 'ошибка', 'compile'])) return 'code';
    if (_containsAny(p, ['3d', 'glb', 'gltf', 'blender', 'mesh', 'риг', 'анимац'])) return '3d';
    if (_containsAny(p, ['картин', 'фото', 'изображ', 'визуал', 'камера'])) return 'vision';
    if (_containsAny(p, ['помни', 'памят', 'запомни', 'истори'])) return 'memory';
    if (_containsAny(p, ['сделай', 'открой', 'запусти', 'установ', 'удали', 'файл'])) return 'action';
    return 'research';
  }

  bool _containsAny(String value, List<String> needles) => needles.any(value.contains);

  Set<String> _tokens(String text) => text
      .toLowerCase()
      .split(RegExp(r'[^a-zа-яё0-9_]+', caseSensitive: false))
      .where((e) => e.isNotEmpty)
      .toSet();

  Future<void> close() async {
    await memory.close();
  }
}
