from pathlib import Path

manifest = Path('android/app/src/main/AndroidManifest.xml')
s = manifest.read_text()

service = '''        <service
            android:name=".DreamPulseVoiceService"
            android:process=":voice"
            android:exported="false"
            android:stopWithTask="true" />
'''

if 'android:name=".DreamPulseVoiceService"' not in s:
    if '</application>' not in s:
        raise SystemExit('AndroidManifest application block not found')
    s = s.replace('</application>', service + '    </application>', 1)

manifest.write_text(s)
