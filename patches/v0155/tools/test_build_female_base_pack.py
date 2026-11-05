"""Small isolated fixture tests; no Silero weights needed for this CI test."""
import pathlib
import tempfile
import unittest
import zipfile

from build_female_base_pack import MODEL_FILES, build


class PackBuilderTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = pathlib.Path(self.tmp.name)
        self.source = root / "ruvoice"
        self.stress = root / "stress.bin"
        self.destination = root / "female-base.zip"
        for filename, subpath in MODEL_FILES.items():
            path = self.source / subpath
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_bytes((filename + "_fixture").encode("utf-8"))
        self.stress.write_bytes(b"stress_fixture")

    def test_pack_manifest_contains_original_license_and_no_new_voice_claim(self):
        manifest = build(self.source, self.stress, self.destination)
        self.assertEqual(manifest["model_id"], "v5_5_ru")
        self.assertEqual(manifest["license"], "CC BY-NC-SA 4.0")
        self.assertEqual(manifest["speaker_filter"], ["baya", "kseniya", "xenia"])
        self.assertEqual(manifest["ui_voices"], [])
        self.assertFalse(manifest["user_recordings_trained"])
        self.assertFalse(manifest["native_runtime_embedded"])
        with zipfile.ZipFile(self.destination) as packed:
            self.assertIn("silero/manifest.json", packed.namelist())
            self.assertEqual(
                len([x for x in packed.namelist() if x.endswith((".ptl", ".pte", ".bin"))]),
                6,
            )

    def test_missing_or_empty_module_is_rejected(self):
        (self.source / MODEL_FILES["tts_mel.ptl"]).unlink()
        with self.assertRaises(FileNotFoundError):
            build(self.source, self.stress, self.destination)
        self.assertFalse(self.destination.exists())

    def test_existing_archive_never_overwritten(self):
        self.destination.write_bytes(b"custom user data")
        with self.assertRaises(FileExistsError):
            build(self.source, self.stress, self.destination)
        self.assertEqual(self.destination.read_bytes(), b"custom user data")


if __name__ == "__main__":
    unittest.main()
