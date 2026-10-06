from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
lines = s.splitlines()
lines = ['version: 0.9.2+13' if line.startswith('version:') else line for line in lines]
s = '\n'.join(lines) + '\n'

if '  audioplayers:' not in s:
    s = s.replace('dependencies:\n', 'dependencies:\n  audioplayers: ^6.8.1\n', 1)
if '  flutter_secure_storage:' not in s:
    s = s.replace('dependencies:\n', 'dependencies:\n  flutter_secure_storage: ^11.2.0\n', 1)

p.write_text(s)
