from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()

if 'version:' in s:
    lines = s.splitlines()
    lines = ['version: 0.8.1+9' if line.startswith('version:') else line for line in lines]
    s = '\n'.join(lines) + '\n'

s = s.replace('Dream Pulse v0.8', 'Dream Pulse v0.8.1')
s = s.replace('Dream Pulse v0.7', 'Dream Pulse v0.8.1')

if 'path_provider:' not in s:
    if '  path: ' in s:
        s = s.replace('  path: ^1.9.0\n', '  path: ^1.9.0\n  path_provider: ^2.1.5\n  crypto: ^3.0.6\n')
    else:
        marker = 'dependencies:\n  flutter:\n    sdk: flutter\n'
        s = s.replace(marker, marker + '  path_provider: ^2.1.5\n  crypto: ^3.0.6\n')
elif 'crypto:' not in s:
    s = s.replace('  path_provider: ^2.1.5\n', '  path_provider: ^2.1.5\n  crypto: ^3.0.6\n')

p.write_text(s)
