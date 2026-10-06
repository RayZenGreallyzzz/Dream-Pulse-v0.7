import 'package:flutter/material.dart';

import '../avatar/avatar_session.dart';
import '../avatar/speech_controller.dart';
import '../llm/brain_router.dart';
import '../llm/local_qwen_backend.dart';
import '../llm/qwen_model_installer.dart';
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
  late final LocalQwenBackend localBrain;
  late final QwenModelInstaller installer;
  late final BrainRouter brain;
  int index = 0;

  @override
  void initState() {
    super.initState();
    session = AvatarSession();
    speech = SpeechController(session);
    voiceInput = VoiceInputController();
    localBrain = LocalQwenBackend();
    installer = QwenModelInstaller();
    brain = BrainRouter(local: localBrain);
    speech.init();
    voiceInput.init();
  }

  @override
  void dispose() {
    speech.dispose();
    voiceInput.cancel();
    localBrain.unload();
    installer.dispose();
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
      ),
      AvatarPage(session: session, speech: speech),
      const HomePage(),
    ];

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 58,
        titleSpacing: 14,
        title: Row(
          children: [
            Container(width: 3, height: 28, color: const Color(0xFF23D5E7)),
            const SizedBox(width: 10),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('DREAM PULSE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.8)),
                  Text('ANDROID NODE // v0.8', style: TextStyle(fontSize: 9, letterSpacing: 1.2, color: Color(0xFF8992A5))),
                ],
              ),
            ),
            AnimatedBuilder(
              animation: localBrain,
              builder: (_, __) => _StatusLamp(
                online: localBrain.ready,
                label: localBrain.ready ? 'LOCAL' : 'NO MODEL',
              ),
            ),
          ],
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(1),
          child: Divider(height: 1, thickness: 1, color: Color(0xFF272C38)),
        ),
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Container(
          height: 58,
          decoration: const BoxDecoration(
            color: Color(0xFF0B0E14),
            border: Border(top: BorderSide(color: Color(0xFF272C38))),
          ),
          child: Row(
            children: [
              _NavCell(index: 0, selected: index == 0, icon: Icons.chat_bubble_outline, label: 'ASSISTANT', onTap: _select),
              _NavCell(index: 1, selected: index == 1, icon: Icons.view_in_ar_outlined, label: 'AVATAR', onTap: _select),
              _NavCell(index: 2, selected: index == 2, icon: Icons.hub_outlined, label: 'PULSE', onTap: _select),
            ],
          ),
        ),
      ),
    );
  }

  void _select(int value) => setState(() => index = value);
}

class _StatusLamp extends StatelessWidget {
  const _StatusLamp({required this.online, required this.label});
  final bool online;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0F1219),
        border: Border.all(color: online ? const Color(0xFF23D5E7) : const Color(0xFF3A4050)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 6, height: 6, color: online ? const Color(0xFF23D5E7) : const Color(0xFF687082)),
          const SizedBox(width: 6),
          Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
        ],
      ),
    );
  }
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
    return Expanded(
      child: InkWell(
        onTap: () => onTap(index),
        child: Container(
          decoration: BoxDecoration(
            color: selected ? const Color(0xFF15172A) : Colors.transparent,
            border: Border(
              top: BorderSide(color: selected ? const Color(0xFF8E7CFF) : Colors.transparent, width: 2),
              right: const BorderSide(color: Color(0xFF1C202A)),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 19, color: selected ? const Color(0xFFC2B9FF) : const Color(0xFF778094)),
              const SizedBox(height: 3),
              Text(label, style: TextStyle(fontSize: 9, letterSpacing: 0.7, color: selected ? const Color(0xFFE2DDFF) : const Color(0xFF778094))),
            ],
          ),
        ),
      ),
    );
  }
}
