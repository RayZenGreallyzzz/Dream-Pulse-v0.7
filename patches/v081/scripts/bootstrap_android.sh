#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK not found. Install Flutter 3.24+ first."
  exit 1
fi

flutter create --platforms=android --org com.dreampulse .
flutter pub get

MANIFEST="android/app/src/main/AndroidManifest.xml"
python3 - "$MANIFEST" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
for perm in [
    '<uses-permission android:name="android.permission.INTERNET" />',
    '<uses-permission android:name="android.permission.RECORD_AUDIO" />',
    '<uses-permission android:name="android.permission.BLUETOOTH" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
]:
    if perm not in s:
        s=s.replace('<manifest xmlns:android="http://schemas.android.com/apk/res/android">',
                    '<manifest xmlns:android="http://schemas.android.com/apk/res/android">\n    '+perm)
if '<queries>' not in s:
    query='''\n    <queries>\n        <intent>\n            <action android:name="android.speech.RecognitionService" />\n        </intent>\n    </queries>'''
    s=s.replace('<application', query+'\n    <application')
if 'android:largeHeap=' not in s:
    s=s.replace('<application', '<application android:largeHeap="true"')
s=s.replace('android:label="dream_pulse"', 'android:label="Dream Pulse"')
s=s.replace('android:icon="@mipmap/ic_launcher"', 'android:icon="@drawable/dream_pulse_icon" android:roundIcon="@drawable/dream_pulse_icon"')
p.write_text(s)
PY

GRADLE_KTS="android/app/build.gradle.kts"
if [ -f "$GRADLE_KTS" ]; then
python3 - <<'PY'
from pathlib import Path
p=Path('android/app/build.gradle.kts')
s=p.read_text()
s=s.replace('namespace = "com.dreampulse.dream_pulse"', 'namespace = "com.dreampulse.assistant"')
s=s.replace('applicationId = "com.dreampulse.dream_pulse"', 'applicationId = "com.dreampulse.assistant"')
s=s.replace('minSdk = flutter.minSdkVersion', 'minSdk = 26')
needle='''    buildTypes {\n        release {'''
if 'create("dreamPulseTest")' not in s:
    signing='''    signingConfigs {\n        create("dreamPulseTest") {\n            storeFile = file("dream-pulse-test.jks")\n            storePassword = "dream-pulse-test"\n            keyAlias = "dream-pulse-test"\n            keyPassword = "dream-pulse-test"\n        }\n    }\n\n'''
    s=s.replace(needle, signing+needle)
s=s.replace('signingConfig = signingConfigs.getByName("debug")', 'signingConfig = signingConfigs.getByName("dreamPulseTest")')
p.write_text(s)
PY
else
  echo "Expected Kotlin Gradle file not found" >&2
  exit 2
fi

rm -rf android/app/src/main/kotlin/com/dreampulse/dream_pulse
mkdir -p android/app/src/main/kotlin/com/dreampulse/assistant
cat > android/app/src/main/kotlin/com/dreampulse/assistant/MainActivity.kt <<'KT'
package com.dreampulse.assistant

import io.flutter.embedding.android.FlutterActivity

class MainActivity : FlutterActivity()
KT

base64 -d ci/test-signing/dream-pulse-test.jks.b64 > android/app/dream-pulse-test.jks

mkdir -p android/app/src/main/res/drawable
cat > android/app/src/main/res/drawable/dream_pulse_icon.xml <<'XML'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp"
    android:height="108dp"
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#050608" android:pathData="M0,0h108v108h-108z"/>
    <path android:fillColor="#00000000" android:strokeColor="#FF5A0A" android:strokeWidth="4"
        android:pathData="M54,13 A41,41 0,1 1,53.99 13"/>
    <path android:fillColor="#00000000" android:strokeColor="#FF9A42" android:strokeWidth="1.6"
        android:pathData="M54,20 A34,34 0,1 1,53.99 20"/>
    <path android:fillColor="#17191D" android:strokeColor="#A92D0A" android:strokeWidth="1"
        android:pathData="M54,3 L49,31 L54,27 L59,31 Z M105,54 L77,49 L81,54 L77,59 Z M54,105 L49,77 L54,81 L59,77 Z M3,54 L31,49 L27,54 L31,59 Z"/>
    <path android:fillColor="#FFC066" android:pathData="M54,29 A15,15 0,1 1,53.99 29"/>
    <path android:fillColor="#101216" android:strokeColor="#303238" android:strokeWidth="1"
        android:pathData="M20,77 L20,62 L24,56 L28,62 L28,77 Z
                          M30,77 L30,55 L34,48 L38,55 L38,77 Z
                          M40,77 L40,60 L44,54 L48,60 L48,77 Z
                          M49,77 L50,39 L54,26 L58,39 L59,77 Z
                          M61,77 L61,58 L65,50 L69,58 L69,77 Z
                          M71,77 L71,53 L75,46 L79,53 L79,77 Z
                          M81,77 L81,61 L85,55 L89,61 L89,77 Z"/>
    <path android:fillColor="#FFB348" android:pathData="M52.5,44h3v5h-3z M52.5,54h3v5h-3z M52.5,64h3v5h-3z"/>
    <path android:fillColor="#FF5A0A" android:pathData="M17,78h74v2h-74z"/>
</vector>
XML

cat > android/app/proguard-rules.pro <<'RULES'
-keep class com.write4me.llama_flutter_android.** { *; }
-keep class kotlin.jvm.functions.Function1
-keepclassmembers class * implements kotlin.jvm.functions.Function1 {
    public java.lang.Object invoke(java.lang.Object);
}
-keepclasseswithmembernames class * {
    native <methods>;
}
RULES

echo "Android bootstrap complete: com.dreampulse.assistant / fixed TEST signing"
