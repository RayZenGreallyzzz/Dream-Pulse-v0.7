from pathlib import Path

p = Path('scripts/bootstrap_android.sh')
s = p.read_text()

if 'android.intent.action.TTS_SERVICE' not in s:
    old = '''        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n    </queries>'''
    new = '''        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n        <intent>\n            <action android:name="android.intent.action.TTS_SERVICE" />\n        </intent>\n    </queries>'''
    if old not in s:
        raise SystemExit('bootstrap_android: queries block not found')
    s = s.replace(old, new, 1)

p.write_text(s)
