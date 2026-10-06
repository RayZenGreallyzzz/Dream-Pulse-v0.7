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
)
s = s.replace(
    "  final QwenModelInstaller installer;\n",
    "  final QwenModelInstaller installer;\n  final PulseCoordinator core;\n",
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

# Make the page rebuild while Worker/Processor/Critic phases change.
s = s.replace(
    "        widget.installer,\n      ]),",
    "        widget.installer,\n        widget.core,\n      ]),",
    1,
)

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
s = s.replace('LOCAL CORE · v0.8.1', 'LIVE CORE · v0.9')
s = s.replace('Qwen3 1.7B Q4_K_M', 'Qwen3 0.6B Q4_0')
s = s.replace('Qwen3 1.7B', 'Qwen3 0.6B')
s = s.replace('QWEN 1.7B', 'QWEN 0.6B')
s = s.replace('Qwen 1.7B', 'Qwen 0.6B')
s = s.replace('~1.28 GB', '~429 MB')
s = s.replace('~1.28 ГБ', '~429 МБ')
p.write_text(s)
