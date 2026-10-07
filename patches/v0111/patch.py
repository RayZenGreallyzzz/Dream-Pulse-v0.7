from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
lines = s.splitlines()
lines = ['version: 0.11.1+25' if line.startswith('version:') else line for line in lines]
p.write_text('\n'.join(lines) + '\n')

for path in ['lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    if not p.exists():
        continue
    s = p.read_text()
    s = s.replace('v0.11', 'v0.11.1')
    p.write_text(s)
