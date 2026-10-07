from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
if '  crypto:' not in s:
    s = s.replace('dependencies:\n', 'dependencies:\n  crypto: ^3.0.6\n', 1)
s = '\n'.join('version: 0.13.0+29' if line.startswith('version:') else line for line in s.splitlines()) + '\n'
p.write_text(s)

ui = Path('lib/ui/assistant_page.dart')
s = ui.read_text()
s = s.replace('  bool autoSpeak = true;', '  bool autoSpeak = false;', 1)
ui.write_text(s)
