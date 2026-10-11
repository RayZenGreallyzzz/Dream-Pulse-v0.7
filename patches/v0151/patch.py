from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
s = '\n'.join(
    'version: 0.15.1+35'
    if line.startswith('version:')
    else line
    for line in s.splitlines()
) + '\n'
p.write_text(s)

ui = Path('lib/ui/assistant_page.dart')
text = ui.read_text()
text = text.replace(
    'Dream Pulse Voice Core · sherpa-onnx · отдельный Android-процесс. '
    'Профиль Dream · Zoey-style настроен по голосовому референсу.',
    'Dream Pulse Voice Core · sherpa-onnx streaming · отдельный Android-процесс. '
    'Звук теперь идёт напрямую из TTS в AudioTrack.'
)
ui.write_text(text)
