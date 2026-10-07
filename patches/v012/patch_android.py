from pathlib import Path
import re

gradle = Path('android/app/build.gradle.kts')
s = gradle.read_text()

deps = '''
dependencies {
    implementation("org.pytorch:pytorch_android_lite:2.1.0")
    implementation(files("libs/executorch-1.5.0-xnnpack.aar"))
}

android {
    packaging {
        jniLibs.pickFirsts += listOf(
            "lib/arm64-v8a/libfbjni.so",
            "lib/arm64-v8a/libc++_shared.so"
        )
    }
}
'''

if 'pytorch_android_lite:2.1.0' not in s:
    s = s.rstrip() + '\n\n' + deps

gradle.write_text(s)

manifest = Path('android/app/src/main/AndroidManifest.xml')
m = manifest.read_text()

# Dream Pulse Voice is deliberately not an Android TTS engine. Remove the old
# TTS-service discovery query left by the RuVoice integration.
m = re.sub(
    r'\s*<intent>\s*<action android:name="android\.intent\.action\.TTS_SERVICE"\s*/>\s*</intent>',
    '',
    m,
    flags=re.S,
)

manifest.write_text(m)
