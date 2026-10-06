from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
lines = s.splitlines()
out = []
for line in lines:
    if line.startswith('version:'):
        out.append('version: 0.9.1+12')
    elif line.startswith('description:'):
        out.append('description: Dream Pulse v0.9.1 - live Core, personality engine, lightweight local Qwen, web worker, avatar and voice.')
    else:
        out.append(line)
p.write_text('\n'.join(out) + '\n')
