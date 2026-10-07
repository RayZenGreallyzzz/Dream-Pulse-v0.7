from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()

deps = {
    'image_picker:': '  image_picker: ^1.1.2\n',
    'file_picker:': '  file_picker: ^11.0.3\n',
    'video_thumbnail:': '  video_thumbnail: ^0.5.6\n',
    'url_launcher:': '  url_launcher: ^6.3.1\n',
}

anchor = 'dependencies:\n  flutter:\n    sdk: flutter\n'
if anchor not in s:
    raise SystemExit('pubspec dependencies anchor not found')

insert = ''
for key, line in deps.items():
    if key not in s:
        insert += line

if insert:
    s = s.replace(anchor, anchor + insert)

lines = s.splitlines()
lines = ['version: 0.11.0+24' if line.startswith('version:') else line for line in lines]
p.write_text('\n'.join(lines) + '\n')

for path in ['lib/ui/assistant_shell.dart', 'lib/ui/launch_gate.dart']:
    p = Path(path)
    if not p.exists():
        continue
    s = p.read_text()
    for old in ['v0.10.1', 'v0.10.2', 'v0.10.3']:
        s = s.replace(old, 'v0.11')
    p.write_text(s)
