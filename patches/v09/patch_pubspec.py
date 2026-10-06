from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
lines = s.splitlines()
lines = ['version: 0.9.0+11' if line.startswith('version:') else line for line in lines]
s = '\n'.join(lines) + '\n'
s = s.replace('Dream Pulse v0.8.2', 'Dream Pulse v0.9')
s = s.replace('Dream Pulse v0.8.1', 'Dream Pulse v0.9')
s = s.replace('Dream Pulse v0.8', 'Dream Pulse v0.9')
p.write_text(s)
