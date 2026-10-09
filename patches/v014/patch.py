from pathlib import Path

p = Path('pubspec.yaml')
s = p.read_text()
s = '\n'.join(
    'version: 0.14.1+32' if line.startswith('version:') else line
    for line in s.splitlines()
) + '\n'
p.write_text(s)

ui = Path('lib/ui/assistant_page.dart')
text = ui.read_text()
text = text.replace(
    'Локальный модуль внутри Dream Pulse · не системный TTS. '
    'Другие приложения не могут отправлять ему свой текст.',
    'SAFE Voice работает в отдельном Android-процессе · не системный TTS. '
    'Если голосовой процесс упадёт, чат Dream Pulse останется открыт.'
)
text = text.replace(
    'Установить Baya + Kseniya',
    'Установить SAFE Voice · Baya + Kseniya'
)
ui.write_text(text)


speech = Path('lib/avatar/speech_controller.dart')
if speech.exists():
    text = speech.read_text()
    text = text.replace(
        "'Привет! Я Dream Pulse. Это мой локальный голос ${selectedVoice.label}.'",
        "'Привет. Я Dream Pulse.'"
    )
    speech.write_text(text)
