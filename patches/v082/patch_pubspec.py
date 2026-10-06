from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
lines = s.splitlines()
lines = ['version: 0.8.2+10' if line.startswith('version:') else line for line in lines]
s = '\n'.join(lines) + '\n'
p.write_text(s)
