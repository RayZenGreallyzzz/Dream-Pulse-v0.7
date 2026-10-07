import 'package:flutter/material.dart';

import '../avatar/avatar_session.dart';
import '../avatar/speech_controller.dart';
import '../core/dream_pulse_engine.dart';
import '../core/pulse_coordinator.dart';
import '../llm/brain_router.dart';
import '../llm/deepseek_api_backend.dart';
import '../llm/deepseek_model_installer.dart';
import '../llm/groq_api_backend.dart';
import '../llm/local_deepseek_backend.dart';
import '../net/tablet_web_search.dart';
import '../personality/personality_engine.dart';
import '../storage/memory_store.dart';
import '../voice/voice_input_controller.dart';
import 'assistant_page.dart';
import 'avatar_page.dart';
import 'home_page.dart';

class AssistantShell extends StatefulWidget {
  const AssistantShell({super.key});

  @override
  State<AssistantShell> createState() => _AssistantShellState();
}

class _AssistantShellState extends State<AssistantShell> {
  late final AvatarSession session;
  late final SpeechController speech;
  late final VoiceInputController voiceInput;
  late final LocalDeepSeekBackend localBrain;
  late final GroqApiBackend groqBrain;
  late final DeepSeekApiBackend apiBrain;
  late final DeepSeekModelInstaller installer;
  late final BrainRouter brain;
  late final DreamPulseEngine engine;
  late final MemoryStore memory;
  late final PersonalityEngine personality;
  late final PulseCoordinator core;

  int index = 0;

  @override
  void initState() {
    super.initState();

    session = AvatarSession();
    speech = SpeechController(session);
    voiceInput = VoiceInputController();
    localBrain = LocalDeepSeekBackend();
    groqBrain = GroqApiBackend();
    apiBrain = DeepSeekApiBackend();
    installer = DeepSeekModelInstaller();
    brain = BrainRouter(
      local: localBrain,
      groq: groqBrain,
      api: apiBrain,
    );
    engine = DreamPulseEngine();
    memory = MemoryStore();
    personality = PersonalityEngine();
    core = PulseCoordinator(
      engine: engine,
      memory: memory,
      brain: brain,
      webSearch: TabletWebSearch(),
      personality: personality,
    );

    speech.init();
    voiceInput.init();
    groqBrain.init();
    apiBrain.init();
    installer.refresh();
    core.init();
  }

  @override
  void dispose() {
    speech.dispose();
    voiceInput.cancel();
    localBrain.unload();
    groqBrain.stop();
    apiBrain.stop();
    core.close();
    installer.dispose();
    personality.dispose();
    engine.dispose();
    session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      AssistantPage(
        session: session,
        speech: speech,
        voiceInput: voiceInput,
        brain: brain,
        localBrain: localBrain,
        installer: installer,
        core: core,
      ),
      AvatarPage(session: session, speech: speech),
      HomePage(core: core),
    ];

    return Scaffold(
      backgroundColor: const Color(0xFF090A0E),
      appBar: AppBar(
        toolbarHeight: 54,
        backgroundColor: const Color(0xFF090A0E),
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 16,
        title: AnimatedBuilder(
          animation: Listenable.merge([brain, core, engine]),
          builder: (_, __) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Dream Pulse',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  letterSpacing: .2,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                engine.running
                    ? core.status
                    : 'v0.10.1 · ${brain.lastBackend == 'none' ? 'готов' : brain.lastBackend}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 10,
                  color: Color(0xFF8B8E98),
                ),
              ),
            ],
          ),
        ),
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 56,
          color: const Color(0xFF090A0E),
          child: Row(
            children: [
              _NavCell(
                index: 0,
                selected: index == 0,
                icon: Icons.chat_bubble_outline_rounded,
                label: 'Чат',
                onTap: _select,
              ),
              _NavCell(
                index: 1,
                selected: index == 1,
                icon: Icons.view_in_ar_outlined,
                label: 'Аватар',
                onTap: _select,
              ),
              _NavCell(
                index: 2,
                selected: index == 2,
                icon: Icons.hub_outlined,
                label: 'Pulse',
                onTap: _select,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _select(int value) => setState(() => index = value);
}

class _NavCell extends StatelessWidget {
  const _NavCell({
    required this.index,
    required this.selected,
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final int index;
  final bool selected;
  final IconData icon;
  final String label;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    final color = selected
        ? const Color(0xFFFF7A2F)
        : const Color(0xFF6F737E);

    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 19, color: color),
            const SizedBox(height: 3),
            Text(
              label,
              style: TextStyle(fontSize: 9, color: color),
            ),
          ],
        ),
      ),
    );
  }
}
