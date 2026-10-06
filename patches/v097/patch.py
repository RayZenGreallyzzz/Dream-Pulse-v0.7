from pathlib import Path

p = Path('lib/ui/assistant_page.dart')
s = p.read_text()

# While local Qwen is streaming, show the actual runtime status/speed instead
# of replacing it with the generic Core phase.
s = s.replace(
    "status = '${widget.brain.lastBackend} · ${widget.core.status}';",
    "status = widget.brain.lastBackend == widget.localBrain.name\n"
    "    ? widget.localBrain.status\n"
    "    : '${widget.brain.lastBackend} · ${widget.core.status}';",
)

s = s.replace('v0.9.6 FAST', 'v0.9.7 CORE FIX')
s = s.replace('v0.9.6', 'v0.9.7')
p.write_text(s)

for path in ['lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    s = p.read_text().replace('v0.9.6 FAST', 'v0.9.7 CORE FIX').replace('v0.9.6', 'v0.9.7')
    p.write_text(s)
