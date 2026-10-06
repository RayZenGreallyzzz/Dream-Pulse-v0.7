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
  late final BrainRouter brain;
  late final QwenModelInstaller installer;
  int index = 0;

  @override
  void initState() {
    super.initState();
    session = AvatarSession();
    speech = SpeechController(session);
    voiceInput = VoiceInputController();
    localBrain = LocalQwenBackend();
    brain = BrainRouter(local: localBrain);
    installer = QwenModelInstaller();
    speech.init();
    voiceInput.init();
    installer.refresh();
    // IMPORTANT for 4 GB devices: do not auto-load the 1.7B model here.
    // The user starts it explicitly from Assistant, after RAM is checked.
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
        title: const Text(
          'DREAM PULSE · v0.8.2 SAFE',
          style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.1),
        ),
      ),
      body: IndexedStack(index: index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (value) => setState(() => index = value),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline),
            selectedIcon: Icon(Icons.chat_bubble),
            label: 'ASSISTANT',
          ),
          NavigationDestination(
            icon: Icon(Icons.view_in_ar_outlined),
            selectedIcon: Icon(Icons.view_in_ar),
            label: 'AVATAR',
          ),
          NavigationDestination(
            icon: Icon(Icons.hub_outlined),
            selectedIcon: Icon(Icons.hub),
            label: 'PULSE',
          ),
        ],
      ),
    );
  }
}
