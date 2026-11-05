"""Tests the unsigned pack's integrity metadata without requiring PyTorch."""
import json
import pathlib
import tempfile
import unittest
import zipfile
from export_full_lite import FORMAT, LICENSE, pack_files


class ExportPackageTest(unittest.TestCase):
    def setUp(self):
        self.t = tempfile.TemporaryDirectory()
        self.addCleanup(self.t.cleanup)
        root = pathlib.Path(self.t.name)
        self.work = root / "files"
        self.work.mkdir()
        self.out = root / "dream-silero.zip"
        (self.work / "model.ptl").write_bytes(b"SIMULATED_TORCHSCRIPT_MODEL")
        (self.work / "symbols.json").write_text(json.dumps({
            "sample_rate": 24000,
            "sos": "^",
            "eos": "$",
            "symbols": "^$_абвгдеёжзийклмнопрстуфхцчшщъыьэюя ",
            "symbol_to_id": {"^": 0, "$": 1, "п": 2, "р": 3},
            "speakers": {"baya": 0, "kseniya": 1, "xenia": 2},
        }), encoding="utf-8")

    def test_pack_is_labeled_reference_only(self):
        m = pack_files(self.work, self.out)
        self.assertEqual(m["format"], FORMAT)
        self.assertEqual(m["license"], LICENSE)
        self.assertEqual(m["public_voice_ids"], [])
        self.assertEqual(m["trained_user_voices"], [])
        self.assertTrue(m["silero_backend_test_only"])
        with zipfile.ZipFile(self.out) as z:
            names = set(z.namelist())
            self.assertEqual(names, {
                "silero/model.ptl", "silero/symbols.json", "silero/manifest.json",
            })
            saved = json.loads(z.read("silero/manifest.json"))
            self.assertEqual(saved["files"]["model.ptl"]["bytes"],
                             len(b"SIMULATED_TORCHSCRIPT_MODEL"))

    def test_existing_pack_is_never_overwritten(self):
        self.out.write_bytes(b"PRIVATE USER DATA")
        with self.assertRaises(FileExistsError):
            pack_files(self.work, self.out)
        self.assertEqual(self.out.read_bytes(), b"PRIVATE USER DATA")

    def test_missing_files_rejected(self):
        (self.work / "model.ptl").unlink()
        with self.assertRaises(FileNotFoundError):
            pack_files(self.work, self.out)
        self.assertFalse(self.out.exists())

    def test_speaker_mapping_required(self):
        (self.work / "symbols.json").write_text(json.dumps({
            "symbol_to_id": {"a": 1}, "sos": "^", "eos": "$",
            "speakers": {"baya": 1},
        }), encoding="utf-8")
        with self.assertRaises(ValueError):
            pack_files(self.work, self.out)


if __name__ == "__main__":
    unittest.main()
