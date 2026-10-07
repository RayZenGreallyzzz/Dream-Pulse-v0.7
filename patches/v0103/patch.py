from pathlib import Path

for path in ['lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    s = p.read_text()
    s = s.replace('v0.10.1', 'v0.10.3')
    s = s.replace('v0.10.2', 'v0.10.3')
    p.write_text(s)
