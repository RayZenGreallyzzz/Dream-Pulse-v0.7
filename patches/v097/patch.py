from pathlib import Path

p = Path('lib/ui/assistant_page.dart')
s = p.read_text()

# While local model is working, show the real runtime status/speed instead of
# replacing it with a generic Core phase.
s = s.replace(
    "status = '${widget.brain.lastBackend} · ${widget.core.status}';",
    "status = widget.brain.lastBackend == widget.localBrain.name\n"
    "    ? widget.localBrain.status\n"
    "    : '${widget.brain.lastBackend} · ${widget.core.status}';",
)

s = s.replace('v0.9.6 FAST', 'v0.9.7 SMART')
s = s.replace('v0.9.6', 'v0.9.7')
p.write_text(s)

p = Path('lib/ui/launch_gate.dart')
s = p.read_text()

s = s.replace(
    "onPressed: checking ? null : (ready ? _openAssistant : _install),",
    "onPressed: checking ? null : (installer.smartActive ? _openAssistant : _install),",
    1,
)

s = s.replace(
    """ready
                                    ? 'ЗАПУСТИТЬ DREAM PULSE'
                                    : 'УСТАНОВИТЬ QWEN 0.6B · ~429 MB',""",
    """installer.smartActive
                                    ? 'ЗАПУСТИТЬ DREAM PULSE'
                                    : 'УСТАНОВИТЬ DEEPSEEK 1.5B SMART · ~1.12 GB',""",
    1,
)

s = s.replace(
    "if (!ready) ...[",
    "if (!installer.smartActive) ...[",
    1,
)

s = s.replace(
    "child: const Text('ПРОПУСТИТЬ · БЕЗ LOCAL BRAIN'),",
    """child: Text(
                                  ready
                                      ? 'ЗАПУСТИТЬ QWEN 0.6B FAST'
                                      : 'ПРОПУСТИТЬ · БЕЗ LOCAL BRAIN',
                                ),""",
    1,
)

s = s.replace(
    "Qwen3 0.6B Q4_0 · ~429 MB",
    "DeepSeek R1 1.5B Q4_K_M · ~1.12 GB",
)

s = s.replace('v0.9.6 FAST', 'v0.9.7 SMART')
s = s.replace('v0.9.6', 'v0.9.7')
p.write_text(s)

p = Path('lib/ui/assistant_shell.dart')
s = p.read_text().replace('v0.9.6 FAST', 'v0.9.7 SMART').replace('v0.9.6', 'v0.9.7')
p.write_text(s)
