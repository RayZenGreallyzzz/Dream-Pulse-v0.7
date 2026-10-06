from pathlib import Path

# Assistant page: route every real question through the shared PulseCoordinator.
p = Path('lib/ui/assistant_page.dart')
s = p.read_text()

if "../core/pulse_coordinator.dart" not in s:
    marker = "import '../avatar/speech_controller.dart';\n"
    s = s.replace(marker, marker + "import '../core/pulse_coordinator.dart';\n")

s = s.replace(
    "    required this.installer,\n  });",
    "    required this.installer,\n    required this.core,\n  });",
    1,
)
s = s.replace(
    "  final QwenModelInstaller installer;\n",
    "  final QwenModelInstaller installer;\n  final PulseCoordinator core;\n",
    1,
)

# 4 GB tablet: never auto-download or auto-load a model just by opening chat.
s = s.replace(
    "    WidgetsBinding.instance.addPostFrameCallback((_) => _prepareLocalBrain());\n",
    "    // v0.9: Qwen loads only when the user explicitly starts a real task.\n",
)

# Set PC config before availability check, so AUTO can genuinely bypass local Qwen.
needle = "    if (text.isEmpty || busy) return;\n\n"
insert = "    if (text.isEmpty || busy) return;\n\n    widget.brain.pcHost = host.text.trim();\n    widget.brain.pcToken = token.text.trim();\n    final pcReady = widget.brain.mode != BrainMode.local && await widget.brain.pcAvailable();\n\n"
s = s.replace(needle, insert, 1)
s = s.replace(
    "    if (!widget.localBrain.ready && widget.brain.mode != BrainMode.pc) {",
    "    if (!widget.localBrain.ready && !pcReady) {",
    1,
)

old_call = """      final answer = await widget.brain.ask(
        text,
        thinking: thinking,
        allowWeb: allowWeb,
      );"""
new_call = """      final answer = await widget.core.ask(
        text,
        thinking: thinking,
        allowWeb: allowWeb,
      );"""
if old_call not in s:
    raise SystemExit('assistant_page: BrainRouter ask call not found')
s = s.replace(old_call, new_call, 1)

s = s.replace(
    "        status = '${widget.brain.lastBackend} · готов';",
    "        status = '${widget.brain.lastBackend} · ${widget.core.status}';",
)

# TTS always receives only the final sanitized answer and a mood-derived
# expression. Hidden reasoning never goes to the voice layer.
s = s.replace(
    "      if (autoSpeak) await widget.speech.speak(answer);",
    "      if (autoSpeak) await widget.speech.speak(answer, expression: widget.core.personality.voiceExpression);",
)

# Make the page rebuild while Worker/Processor/Critic phases change.
s = s.replace(
    "        widget.installer,\n      ]),",
    "        widget.installer,\n        widget.core,\n        widget.core.personality,\n      ]),",
    1,
)

# Add a compact voice chooser to the existing brain sheet.
voice_button_anchor = """              OutlinedButton.icon(
                onPressed: _pickAndLoadModel,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Выбрать другой GGUF'),
              ),"""
voice_button = voice_button_anchor + """
              OutlinedButton.icon(
                onPressed: _showVoiceSheet,
                icon: const Icon(Icons.record_voice_over_outlined),
                label: Text('Голос: ${widget.speech.voiceLabel}'),
              ),"""
if voice_button_anchor not in s:
    raise SystemExit('assistant_page: voice button anchor not found')
s = s.replace(voice_button_anchor, voice_button, 1)

voice_method_anchor = "  Future<void> _toggleMic() async {\n"
voice_method = r'''  Future<void> _showVoiceSheet() async {
    await widget.speech.refreshVoices();
    if (!mounted) return;
    final voices = widget.speech.voiceOptions;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: false,
      backgroundColor: const Color(0xFF0D1016),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text('ГОЛОС DREAM PULSE', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 1.0)),
              const SizedBox(height: 6),
              Text('Сейчас: ${widget.speech.voiceLabel}', style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 10),
              if (voices.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 18),
                  child: Text('На устройстве не найдено дополнительных русских TTS-голосов.'),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 380),
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: voices.length,
                    itemBuilder: (_, i) {
                      final voice = voices[i];
                      final selected = widget.speech.selectedVoice?.name == voice.name;
                      return ListTile(
                        dense: true,
                        title: Text(voice.label, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(voice.locale),
                        leading: Icon(selected ? Icons.radio_button_checked : Icons.radio_button_off),
                        trailing: IconButton(
                          tooltip: 'Прослушать',
                          icon: const Icon(Icons.play_arrow_rounded),
                          onPressed: () => widget.speech.previewVoice(voice),
                        ),
                        onTap: () async {
                          await widget.speech.selectVoice(voice);
                          if (sheetContext.mounted) Navigator.pop(sheetContext);
                          if (mounted) setState(() {});
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

'''
if voice_method_anchor not in s:
    raise SystemExit('assistant_page: toggle mic anchor not found')
s = s.replace(voice_method_anchor, voice_method + voice_method_anchor, 1)

# Update visible model copy.
s = s.replace('Qwen3 1.7B Q4_K_M', 'Qwen3 0.6B Q4_0')
s = s.replace('Qwen3 1.7B', 'Qwen3 0.6B')
s = s.replace('Qwen 1.7B', 'Qwen 0.6B')
s = s.replace('~1.28 ГБ', '~429 МБ')
s = s.replace('~1.28 GB', '~429 MB')
s = s.replace('1.28 ГБ', '429 МБ')
s = s.replace('1.28 GB', '429 MB')
p.write_text(s)

# Launch screen: same artwork, new lightweight local brain and v0.9 label.
p = Path('lib/ui/launch_gate.dart')
s = p.read_text()
s = s.replace('LOCAL CORE · v0.8.1', 'LIVE CORE · v0.9.1')
s = s.replace('Qwen3 1.7B Q4_K_M', 'Qwen3 0.6B Q4_0')
s = s.replace('Qwen3 1.7B', 'Qwen3 0.6B')
s = s.replace('QWEN 1.7B', 'QWEN 0.6B')
s = s.replace('Qwen 1.7B', 'Qwen 0.6B')
s = s.replace('~1.28 GB', '~429 MB')
s = s.replace('~1.28 ГБ', '~429 МБ')
p.write_text(s)

# Android 9+ blocks plain HTTP by default. Future PC Brain is a LAN service
# (192.168.x.x), so enable cleartext for the app's local bridge. Tablet web
# search itself still uses HTTPS endpoints only.
p = Path('scripts/bootstrap_android.sh')
s = p.read_text()
needle = "if 'android:largeHeap=' not in s:\n    s=s.replace('<application', '<application android:largeHeap=\"true\"')"
replacement = "if 'android:largeHeap=' not in s:\n    s=s.replace('<application', '<application android:largeHeap=\"true\" android:usesCleartextTraffic=\"true\"')\nelif 'android:usesCleartextTraffic=' not in s:\n    s=s.replace('android:largeHeap=\"true\"', 'android:largeHeap=\"true\" android:usesCleartextTraffic=\"true\"')"
if needle not in s:
    raise SystemExit('bootstrap_android: largeHeap block not found')
s = s.replace(needle, replacement, 1)
p.write_text(s)
