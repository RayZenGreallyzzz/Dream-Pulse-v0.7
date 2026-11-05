"""Expose installed Android TTS services for optional RuVoice bridge.

Run AFTER the Flutter Android project has been bootstrapped.
"""
from pathlib import Path
p = Path("android/app/src/main/AndroidManifest.xml")
text = p.read_text(encoding="utf-8")
if "android.intent.action.TTS_SERVICE" not in text:
    query = (
        "    <queries>\n"
        "        <intent>\n"
        '            <action android:name="android.intent.action.TTS_SERVICE" />\n'
        "        </intent>\n"
        "    </queries>\n"
    )
    if "<queries>" in text:
        text = text.replace(
            "</queries>",
            '        <intent>\n'
            '            <action android:name="android.intent.action.TTS_SERVICE" />\n'
            '        </intent>\n'
            "</queries>", 1)
    else:
        text = text.replace("<application", query + "    <application", 1)
p.write_text(text, encoding="utf-8")
