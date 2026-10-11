from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
if '  archive:' not in s:
    s = s.replace(
        'dependencies:\n',
        'dependencies:\n  archive: ^4.5.0\n',
        1,
    )
s = '\n'.join(
    'version: 0.15.0+34'
    if line.startswith('version:')
    else line
    for line in s.splitlines()
) + '\n'
p.write_text(s)

ui = Path('lib/ui/assistant_page.dart')
text = ui.read_text()
text = text.replace(
    'SAFE Voice работает в отдельном Android-процессе · не системный TTS. '
    'Если голосовой процесс упадёт, чат Dream Pulse останется открыт.',
    'Dream Pulse Voice Core · sherpa-onnx · отдельный Android-процесс. '
    'Профиль Dream · Zoey-style настроен по голосовому референсу.'
)
text = text.replace(
    'Установить SAFE Voice · Baya + Kseniya',
    'Установить Dream Voice · Zoey-style'
)
text = text.replace(
    "status = 'Голос работает · ${widget.speech.voiceLabel}',",
    "status = 'Dream Voice работает · ${widget.speech.voiceLabel}',"
)
ui.write_text(text)
