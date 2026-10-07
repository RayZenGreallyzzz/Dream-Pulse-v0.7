from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()

# Internal Dream Pulse Voice replaces Android system TTS.
lines = []
for line in s.splitlines():
    if line.strip().startswith('flutter_tts:'):
        continue
    if line.startswith('version:'):
        line = 'version: 0.12.0+26'
    lines.append(line)
p.write_text('\n'.join(lines) + '\n')

for path in ['lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    if not p.exists():
        continue
    s = p.read_text()
    for old in ['v0.11.1', 'v0.11']:
        s = s.replace(old, 'v0.12')
    p.write_text(s)
