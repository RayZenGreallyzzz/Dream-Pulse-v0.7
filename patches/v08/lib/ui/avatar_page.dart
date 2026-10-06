import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../avatar/avatar_session.dart';
import '../avatar/avatar_stage.dart';
import '../avatar/speech_controller.dart';
import '../net/pc_bridge.dart';

class AvatarPage extends StatefulWidget {
  const AvatarPage({
    super.key,
    required this.session,
    required this.speech,
  });

  final AvatarSession session;
  final SpeechController speech;

  @override
  State<AvatarPage> createState() => _AvatarPageState();
}

class _AvatarPageState extends State<AvatarPage> {
  final host = TextEditingController(text: '127.0.0.1');
  final token = TextEditingController();
  final testSpeech = TextEditingController(text: 'Привет. Я Dream Pulse.');
  String status = 'GLB НЕ ЗАГРУЖЕН';
  int modelRevision = 0;

  PcBridge get bridge => PcBridge(host: host.text.trim(), token: token.text.trim());

  Future<void> _pickAvatar() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['glb'],
    );
    if (file == null) return;
    final Uint8List bytes = await file.xFile.readAsBytes();
    if (bytes.isEmpty) {
      setState(() => status = 'ОШИБКА ЧТЕНИЯ GLB');
      return;
    }

    widget.session.setModel(bytes, file.name);
    setState(() {
      modelRevision++;
      status = 'LOCAL AVATAR // ${file.name}';
    });

    try {
      final response = await bridge.uploadAvatar(bytes, file.name);
      final summary = Map<String, dynamic>.from(response['summary'] as Map? ?? const {});
      widget.session.setMetadata(summary);
      if (!mounted) return;
      setState(() => status = 'AVATAR CORE // ${summary['joint_count'] ?? 0} BONES // ${summary['animation_count'] ?? 0} ANIM');
    } catch (_) {
      if (!mounted) return;
      setState(() => status = 'LOCAL AVATAR READY // PC CORE OFFLINE');
    }
  }

  void _openControls() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(14, 14, 14, MediaQuery.viewInsetsOf(context).bottom + 14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text('AVATAR CONTROL', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: testSpeech,
                        decoration: const InputDecoration(labelText: 'Фраза для проверки голоса'),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      onPressed: () => widget.speech.speak(testSpeech.text),
                      icon: const Icon(Icons.volume_up_outlined),
                    ),
                    const SizedBox(width: 4),
                    IconButton.outlined(
                      onPressed: widget.speech.stop,
                      icon: const Icon(Icons.stop_outlined),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                const Divider(height: 1),
                const SizedBox(height: 10),
                const Text('PC AVATAR CORE // OPTIONAL', style: TextStyle(fontSize: 10, letterSpacing: 0.8, color: Color(0xFF8F98AA))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(child: TextField(controller: host, decoration: const InputDecoration(labelText: 'PC host'))),
                    const SizedBox(width: 6),
                    Expanded(child: TextField(controller: token, obscureText: true, decoration: const InputDecoration(labelText: 'LAN token'))),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    host.dispose();
    token.dispose();
    testSpeech.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    return AnimatedBuilder(
      animation: session,
      builder: (context, _) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
            child: Container(
              decoration: BoxDecoration(
                color: const Color(0xFF07090D),
                border: Border.all(color: const Color(0xFF2D3340)),
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: session.modelBytes == null
                        ? _EmptyAvatar(onPick: _pickAvatar)
                        : AvatarStage(
                            key: ValueKey('${session.fileName}-$modelRevision'),
                            modelBytes: session.modelBytes!,
                            speaking: session.speaking,
                            mouthOpen: session.mouthOpen,
                          ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopBar(
                      status: status,
                      loaded: session.modelBytes != null,
                      onPick: _pickAvatar,
                    ),
                  ),
                  if (session.modelBytes != null)
                    Positioned(
                      left: 10,
                      right: 10,
                      bottom: 10,
                      child: Row(
                        children: [
                          _SquareAction(
                            icon: Icons.volume_up_outlined,
                            label: session.speaking.value ? 'SPEAKING' : 'VOICE',
                            onTap: () => widget.speech.speak(testSpeech.text),
                          ),
                          const SizedBox(width: 6),
                          _SquareAction(
                            icon: Icons.stop_outlined,
                            label: 'STOP',
                            onTap: widget.speech.stop,
                          ),
                          const Spacer(),
                          _SquareAction(
                            icon: Icons.tune_outlined,
                            label: 'CONTROL',
                            onTap: _openControls,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.status,
    required this.loaded,
    required this.onPick,
  });

  final String status;
  final bool loaded;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: const BoxDecoration(
        color: Color(0xD9080B10),
        border: Border(bottom: BorderSide(color: Color(0xFF2A3040))),
      ),
      child: Row(
        children: [
          Container(width: 6, height: 6, color: loaded ? const Color(0xFF23D5E7) : const Color(0xFF687082)),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              status,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 9, letterSpacing: 0.8),
            ),
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            onPressed: onPick,
            icon: const Icon(Icons.view_in_ar_outlined, size: 15),
            label: Text(loaded ? 'CHANGE' : 'LOAD GLB'),
          ),
        ],
      ),
    );
  }
}

class _SquareAction extends StatelessWidget {
  const _SquareAction({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xD90A0D13),
      child: InkWell(
        onTap: onTap,
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(border: Border.all(color: const Color(0xFF323848))),
          child: Row(
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Text(label, style: const TextStyle(fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.7)),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyAvatar extends StatelessWidget {
  const _EmptyAvatar({required this.onPick});
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0, -0.1),
              radius: 1.15,
              colors: [Color(0xFF19162E), Color(0xFF0B0E14), Color(0xFF06080C)],
            ),
          ),
        ),
        Center(
          child: Container(
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              color: const Color(0xCC0B0E14),
              border: Border.all(color: const Color(0xFF343A4A)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.view_in_ar_outlined, size: 48, color: Color(0xFFBFB5FF)),
                const SizedBox(height: 12),
                const Text('AVATAR SLOT EMPTY', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, letterSpacing: 1.2)),
                const SizedBox(height: 5),
                const Text('GLB + rig // drag: rotate // pinch: zoom // double tap: reset', textAlign: TextAlign.center, style: TextStyle(fontSize: 10, color: Color(0xFF8F98AA))),
                const SizedBox(height: 14),
                FilledButton.icon(onPressed: onPick, icon: const Icon(Icons.add), label: const Text('LOAD GLB')),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
