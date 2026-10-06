from pathlib import Path

for path in ['lib/ui/assistant_page.dart', 'lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    s = p.read_text().replace('v0.9.5 FIX', 'v0.9.6 FAST').replace('v0.9.5', 'v0.9.6')
    p.write_text(s)
