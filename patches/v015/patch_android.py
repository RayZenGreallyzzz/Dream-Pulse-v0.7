from pathlib import Path
import re

manifest = Path(
    'android/app/src/main/AndroidManifest.xml'
)
s = manifest.read_text()

s = re.sub(
    r'\s*<intent>\s*'
    r'<action android:name='
    r'"android\.intent\.action\.TTS_SERVICE"\s*/>'
    r'\s*</intent>\s*',
    '\n',
    s,
    count=1,
    flags=re.S,
)

service = '''        <service
            android:name=".DreamPulseVoiceService"
            android:process=":voice"
            android:exported="false"
            android:stopWithTask="true" />
'''

if 'android:name=".DreamPulseVoiceService"' not in s:
    if '</application>' not in s:
        raise SystemExit(
            'AndroidManifest application block not found'
        )
    s = s.replace(
        '</application>',
        service + '    </application>',
        1,
    )

manifest.write_text(s)

gradle = Path('android/app/build.gradle.kts')
g = gradle.read_text()
dep = (
    '    implementation('
    '"com.github.k2-fsa.sherpa-onnx:'
    'sherpa-onnx:v1.13.8")\n'
)
if (
    'com.github.k2-fsa.sherpa-onnx:'
    'sherpa-onnx:' not in g
):
    if 'dependencies {' in g:
        g = g.replace(
            'dependencies {\n',
            'dependencies {\n' + dep,
            1,
        )
    else:
        g = g.rstrip() + '\n\ndependencies {\n' + dep + '}\n'
gradle.write_text(g)

build = Path('android/build.gradle.kts')
if build.exists():
    b = build.read_text()
    if 'https://jitpack.io' not in b:
        marker = '        mavenCentral()\n'
        if marker in b:
            b = b.replace(
                marker,
                marker +
                '        maven { '
                'url = uri("https://jitpack.io") }\n',
                1,
            )
        else:
            raise SystemExit(
                'mavenCentral marker not found '
                'in android/build.gradle.kts'
            )
    build.write_text(b)
else:
    settings = Path('android/settings.gradle.kts')
    st = settings.read_text()
    if 'https://jitpack.io' not in st:
        marker = '        mavenCentral()\n'
        if marker not in st:
            raise SystemExit(
                'mavenCentral marker not found '
                'in settings.gradle.kts'
            )
        st = st.replace(
            marker,
            marker +
            '        maven { '
            'url = uri("https://jitpack.io") }\n',
            1,
        )
    settings.write_text(st)
