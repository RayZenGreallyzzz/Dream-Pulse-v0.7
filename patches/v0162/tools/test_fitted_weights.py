"""Synthetic/no-audio checks for independently fitted public style weights."""
import json
import math
from pathlib import Path
import unittest

DIR = Path(__file__).resolve().parents[1] / "voice_weights"
IDS = {
    "dream_ref_hello",
    "dream_ref_calm",
    "dream_ref_weather",
    "dream_ref_long",
}

class TrainedWeightTests(unittest.TestCase):
    def test_four_distinct_voice_filters_exist(self):
        self.assertEqual({x.stem for x in DIR.glob("*.json")}, IDS)
        signatures = set()
        for voice_id in sorted(IDS):
            raw = json.loads((DIR / (voice_id + ".json")).read_text())
            self.assertEqual(raw["format"], "dream-pulse-timbre-fir-v1")
            self.assertEqual(raw["voice_id"], voice_id)
            self.assertEqual(raw["sample_rate"], 24000)
            self.assertEqual(raw["train_epochs"], 420)
            self.assertEqual(raw["source_model"], "silero-v5_5_ru")
            coeffs = raw["fir_center_to_edge"]
            self.assertEqual(len(coeffs), 129)
            self.assertTrue(all(math.isfinite(x) and abs(x) < 3 for x in coeffs))
            self.assertLess(raw["heldout_spectral_distance_after_db"],
                            raw["heldout_spectral_distance_before_db"])
            self.assertFalse(raw["is_author_voice_clone"])
            self.assertFalse(raw["silero_neural_weights_changed"])
            self.assertFalse(raw["user_voice_recording_included"])
            signatures.add(tuple(coeffs))
        self.assertEqual(len(signatures), 4)

    def test_symmetric_filter_impulse_is_bounded(self):
        # Read only public coefficients. No private voice WAV needed.
        for voice_id in sorted(IDS):
            taps = json.loads((DIR / (voice_id + ".json")).read_text())[
                "fir_center_to_edge"]
            full = list(reversed(taps[1:])) + taps
            self.assertEqual(len(full), 257)
            self.assertLess(sum(abs(x) for x in full), 5.0)
            self.assertAlmostEqual(full[128], taps[0])

if __name__ == "__main__":
    unittest.main()
