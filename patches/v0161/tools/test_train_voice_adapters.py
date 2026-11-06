"""Synthetic unit tests — no user recording may be committed."""
import hashlib
import io
import json
from pathlib import Path
import tempfile
import unittest
import zipfile
import numpy as np
import soundfile as sf

from train_voice_adapters import SR, SPEAKERS, read_references, train_one


class VoiceTrainingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.archive = Path(self.tmp.name) / "private-test-fixture.zip"
        time = np.arange(SR * 3, dtype=np.float64) / SR
        voices = []
        parts = {}
        for i, (voice_id, filename) in enumerate(SPEAKERS.items()):
            samples = (.1*np.sin(2*np.pi*(180+i*28)*time)
                       *np.sin(np.pi*time/3)**2).astype(np.float32)
            buffer = io.BytesIO()
            sf.write(buffer, samples, SR, format="WAV", subtype="PCM_16")
            blob = buffer.getvalue()
            voices.append({
                "id": voice_id,
                "file": filename,
                "sha256": hashlib.sha256(blob).hexdigest(),
            })
            parts["dream-voice-references/" + filename] = blob
        with zipfile.ZipFile(self.archive, "w") as z:
            z.writestr("dream-voice-references/manifest.json",
                       json.dumps({"voices": voices}))
            for name, blob in parts.items():
                z.writestr(name, blob)

    def test_five_voice_mixup_prevented_four_separate_training_ids(self):
        data = read_references(self.archive)
        self.assertEqual(set(data), set(SPEAKERS))
        self.assertEqual(len(data), 4)

    def test_sha256_prevents_tampered_private_samples(self):
        with zipfile.ZipFile(self.archive) as z:
            files = {k:z.read(k) for k in z.namelist()}
        path = "dream-voice-references/hello.wav"
        files[path] = files[path][:-5] + b"WRONG"
        with zipfile.ZipFile(self.archive, "w") as z:
            for k, blob in files.items():
                z.writestr(k, blob)
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            read_references(self.archive)

    def test_eq_adapter_trains_but_is_not_claimed_voice_clone(self):
        sounds = read_references(self.archive)
        a = train_one(sounds["dream_ref_hello"],
                      sounds["dream_ref_weather"], "dream_ref_weather")
        self.assertEqual(a["voice_id"], "dream_ref_weather")
        self.assertEqual(len(a["trained_gain_db"]), 24)
        self.assertLessEqual(max(abs(g) for g in a["trained_gain_db"]), 6.01)
        self.assertFalse(a["is_faithful_voice_clone"])
        self.assertFalse(a["silero_weights_modified"])
        self.assertFalse(a["mobile_inference_ready"])
        self.assertTrue(a["needs_verified_transcripts"])


if __name__ == "__main__":
    unittest.main()
