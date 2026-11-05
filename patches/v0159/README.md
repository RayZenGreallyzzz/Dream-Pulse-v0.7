# Dream Pulse TTS v0.15.9

Это экспериментальный встроенный синтезатор Silero v5_5_ru через PyTorch Lite. Без Piper или установленного RuVoice. Ядро Dream Pulse не меняется.

## Как подготовить веса

На компьютере с PyTorch >=2.4 скачать оригинальную модель v5_5_ru.pt с https://models.silero.ai/models/tts/ru/v5_5_ru.pt и выполнить:

```sh
python3 patches/v0159/tools/export_full_lite.py --source-model /private/v5_5_ru.pt --output /private/dream-pulse-silero-full-lite.zip
```

Скрипт проверяет выход TorchScript Lite численно по оригинальной модели и создаёт ZIP с весами, словарём символов, лицензионными данными и SHA-256.

В Android: настройки голоса → Импортировать веса Dream Pulse TTS → выбрать ZIP → Технический тест Silero (Baya, не авторский голос).

Это *служебная проверка* стандартной женской модели Silero, а не Ирина и не четыре авторских голоса. Они требуют отдельного обучения и не объявляются рабочими.

Оригинальные веса отсутствуют в GitHub и в APK. Лицензия Silero v5_5_ru: CC BY-NC-SA 4.0, условия сохраняются для производных моделей. Работа на реальном Android-устройстве ещё не проверена.
