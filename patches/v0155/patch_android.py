"""Remove v0.15.4's unnecessary external RuVoice discovery requirement."""
from pathlib import Path
import re

path = Path("android/app/src/main/AndroidManifest.xml")
text = path.read_text(encoding="utf-8")
text = re.sub(
    r'(?m)^\s*<intent>\s*'
    r'<action android:name="android\.intent\.action\.TTS_SERVICE"\s*/>\s*'
    r'</intent>\s*',
    "\n",
    text,
    count=1,
)
text = re.sub(r'<queries>\s*</queries>\s*', "", text, count=1)
path.write_text(text, encoding="utf-8")
