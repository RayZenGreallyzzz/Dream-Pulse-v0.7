from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
lines = s.splitlines()
lines = ['version: 0.10.1+21' if line.startswith('version:') else line for line in lines]
p.write_text('\n'.join(lines) + '\n')
