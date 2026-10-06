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
  int index = 0;

  @override
  void initState() {
    super.initState();
    session = AvatarSession();
    speech = SpeechController(session);
    voiceInput = VoiceInputController();
    localBrain = LocalQwenBackend();
    brain = BrainRouter(local: localBrain);
    speech.init();
    voiceInput.init();
    _loadInstalledBrain();
  }

  Future<void> _loadInstalledBrain() async {
    try {
      final installer = QwenModelInstaller();
      final path = await installer.installedPathIfValid();
      installer.dispose();
      if (path != null && !localBrain.ready && !localBrain.loading) {
        await localBrain.load(path, smartProfile: true);
      }
    } catch (_) {
      // The rest of the assistant remains usable if the model cannot load.
    }
  }

  @override
  void dispose() {
    speech.dispose();
    voiceInput.cancel();
    localBrain.unload();
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
      ),
      AvatarPage(session: session, speech: speech),
      const HomePage(),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'DREAM PULSE · v0.8.1',
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
