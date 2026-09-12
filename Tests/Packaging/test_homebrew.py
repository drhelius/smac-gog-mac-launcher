import hashlib
import json
from pathlib import Path
import plistlib
import sys
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "scripts"))
import update_homebrew


class HomebrewTests(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        self.archive = self.root / "SMAC-Launcher-1.0.0-macOS.zip"
        self.write_archive()

    def write_archive(self, version="1.0.0", minimum="13.0"):
        with zipfile.ZipFile(self.archive, "w") as archive:
            archive.writestr("SMAC Launcher.app/Contents/Info.plist", plistlib.dumps({
                "CFBundleIdentifier": "com.drhelius.centauri",
                "CFBundleShortVersionString": version,
                "LSMinimumSystemVersion": minimum,
            }))
            archive.writestr("SMAC Launcher.app/Contents/MacOS/SMACLauncher", b"test executable")
        self.checksum = hashlib.sha256(self.archive.read_bytes()).hexdigest()
        (self.root / "SHA256SUMS").write_text(f"{self.checksum}  {self.archive.name}\n")

    def test_cask_uses_universal_zip_and_keeps_game_data(self):
        checksum = update_homebrew.verify_archive(self.root, "1.0.0")
        text = update_homebrew.render_cask("1.0.0", checksum)
        self.assertIn('app "SMAC Launcher.app"', text)
        self.assertIn('depends_on macos: :ventura', text)
        self.assertIn('SMAC-Launcher-#{version}-macOS.zip', text)
        self.assertNotIn('container nested:', text)
        self.assertNotIn('arch arm:', text)
        self.assertNotIn('Application Support', text)

    def test_checksum_mismatch_and_duplicate_are_rejected(self):
        self.archive.write_bytes(self.archive.read_bytes() + b"changed")
        with self.assertRaises(ValueError):
            update_homebrew.verify_archive(self.root, "1.0.0")
        self.write_archive()
        sums = self.root / "SHA256SUMS"
        sums.write_text(sums.read_text() * 2)
        with self.assertRaises(ValueError):
            update_homebrew.verify_archive(self.root, "1.0.0")

    def test_archive_metadata_must_match_the_cask(self):
        self.write_archive(version="0.9.0")
        with self.assertRaises(ValueError):
            update_homebrew.verify_archive(self.root, "1.0.0")
        self.write_archive(minimum="14.0")
        with self.assertRaises(ValueError):
            update_homebrew.verify_archive(self.root, "1.0.0")

    def test_only_plain_stable_versions_are_accepted(self):
        for version in ["1.0.0-beta.1", "v1.0.0", "latest", "01.0.0", "../1.0.0", '1.0.0";system("bad")']:
            with self.subTest(version=version), self.assertRaises(ValueError):
                update_homebrew.render_cask(version, self.checksum)

    def test_downgrade_is_rejected_and_rerun_is_unchanged(self):
        destination = self.root / "Casks/smac-launcher.rb"
        update_homebrew.write_cask(destination, "1.1.0", self.checksum)
        original = destination.read_bytes()
        update_homebrew.write_cask(destination, "1.1.0", self.checksum)
        self.assertEqual(destination.read_bytes(), original)
        with self.assertRaises(ValueError):
            update_homebrew.write_cask(destination, "1.0.0", self.checksum)
        self.assertEqual(destination.read_bytes(), original)

    def test_draft_and_prerelease_never_download_or_write(self):
        for draft, prerelease in [(True, False), (False, True)]:
            with patch.object(sys, "argv", ["update_homebrew.py", "--output", str(self.root / "cask.rb")]), \
                 patch.object(update_homebrew.subprocess, "check_output", return_value=json.dumps({
                     "tagName": "1.0.0", "isDraft": draft, "isPrerelease": prerelease})), \
                 patch.object(update_homebrew.subprocess, "run") as download:
                with self.assertRaises(ValueError):
                    update_homebrew.main()
                download.assert_not_called()
                self.assertFalse((self.root / "cask.rb").exists())


if __name__ == "__main__":
    unittest.main()
