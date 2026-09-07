import hashlib
import json
import os
from pathlib import Path
import plistlib
import stat
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
import warnings
import zipfile

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "scripts"))
import check_package
import git_version
import release


class PackagingTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.dist = Path(self.temporary.name)
        self.version = "0.1.0-3-gabc1234"
        self.archive = self.dist / f"SMAC-Launcher-{self.version}-macOS.zip"
        self.source = self.dist / f"ffmpeg-{check_package.SOURCE_VERSION}.tar.xz"
        self.source.write_bytes(b"synthetic source fixture")
        self.source_hash = hashlib.sha256(self.source.read_bytes()).hexdigest()
        source_patch = patch.object(check_package, "SOURCE_SHA256", self.source_hash)
        source_patch.start()
        self.addCleanup(source_patch.stop)
        self.write_archive()

    def write_archive(self, omit=(), version=None):
        with zipfile.ZipFile(self.archive, "w") as archive:
            for name in sorted(check_package.REQUIRED - set(omit)):
                content = b"synthetic app fixture"
                if name.endswith("Info.plist"):
                    content = plistlib.dumps({
                        "CFBundleIdentifier": "com.drhelius.centauri",
                        "CFBundleShortVersionString": version or self.version,
                    })
                archive.writestr(name, content)
        self.write_checksums()

    def write_checksums(self):
        self.sums = self.dist / "SHA256SUMS"
        self.sums.write_text("".join(
            f"{hashlib.sha256(path.read_bytes()).hexdigest()}  {path.name}\n"
            for path in [self.archive, self.source]))

    def verify(self):
        check_package.verify_dist(self.dist, self.version)

    def test_complete_release(self):
        self.verify()

    def test_missing_helper_or_license(self):
        for name in ["centauri-movie-player", "FFmpeg-LICENSE.txt"]:
            with self.subTest(name=name):
                self.write_archive(omit=[check_package.PREFIX + "Resources/MovieTools/" + name])
                with self.assertRaisesRegex(SystemExit, "Missing app files"):
                    self.verify()

    def test_game_data_cannot_hide_in_metadata(self):
        for name in ["SMAC Launcher.app/game/terran.exe", "__MACOSX/game/terran.exe",
                     "__MACOSX/SMAC Launcher.app/Contents/Resources/._terran.exe"]:
            with self.subTest(name=name):
                self.write_archive()
                with zipfile.ZipFile(self.archive, "a") as archive:
                    archive.writestr(name, b"game data")
                self.write_checksums()
                with self.assertRaisesRegex(SystemExit, "Unexpected"):
                    self.verify()

    def test_path_traversal_and_symlinks_are_rejected(self):
        self.write_archive()
        with zipfile.ZipFile(self.archive, "a") as archive:
            archive.writestr("SMAC Launcher.app/../secret", b"private")
        self.write_checksums()
        with self.assertRaisesRegex(SystemExit, "Unsafe archive member"):
            self.verify()
        self.write_archive()
        with zipfile.ZipFile(self.archive, "a") as archive:
            link = zipfile.ZipInfo(check_package.PREFIX + "_CodeSignature/CodeResources")
            link.create_system = 3
            link.external_attr = (stat.S_IFLNK | 0o777) << 16
            archive.writestr(link, "/private/file")
        self.write_checksums()
        with self.assertRaisesRegex(SystemExit, "Symlink"):
            self.verify()

    def test_duplicate_members_are_rejected(self):
        with warnings.catch_warnings():
            warnings.simplefilter("ignore", UserWarning)
            with zipfile.ZipFile(self.archive, "a") as archive:
                archive.writestr(check_package.PREFIX + "Info.plist", b"duplicate")
        self.write_checksums()
        with self.assertRaisesRegex(SystemExit, "Duplicate archive"):
            self.verify()

    def test_stale_app_version_is_rejected(self):
        self.write_archive(version="older-build")
        with self.assertRaisesRegex(SystemExit, "version does not match"):
            self.verify()

    def test_source_is_required_and_must_match_even_with_updated_checksums(self):
        self.source.unlink()
        with self.assertRaisesRegex(SystemExit, "Missing release file"):
            self.verify()
        self.source.write_bytes(b"different source")
        self.write_checksums()
        with self.assertRaisesRegex(SystemExit, "source does not match"):
            self.verify()

    def test_tampered_archive_and_extra_checksums_are_rejected(self):
        self.archive.write_bytes(self.archive.read_bytes() + b"changed")
        with self.assertRaisesRegex(SystemExit, "checksums or file list"):
            self.verify()
        self.write_archive()
        with self.sums.open("a") as file:
            file.write("0" * 64 + "  unwanted-file.zip\n")
        with self.assertRaisesRegex(SystemExit, "checksums or file list"):
            self.verify()


class ReleaseTests(unittest.TestCase):
    def test_release_tag_must_be_the_current_git_version(self):
        with patch.object(release, "git_version", return_value="0.1.0"):
            release.check_tag("0.1.0")
            with self.assertRaises(SystemExit):
                release.check_tag("0.2.0")
        for version in ["0.1.0-2-gabc1234", "0.1.0-dirty", "abc1234"]:
            with patch.object(release, "git_version", return_value=version):
                with self.assertRaises(SystemExit):
                    release.check_tag("0.1.0")

    def test_git_descriptions_are_valid_filename_versions(self):
        for version in ["0.1.0", "0.1.0-3-gabc1234", "abc1234", "abc1234-dirty"]:
            self.assertEqual(git_version.validate_version(version), version)
        for version in ["", "../0.1.0", "release/0.1.0", "bad\nvalue", "@version@"]:
            with self.assertRaises(SystemExit):
                git_version.validate_version(version)

    def test_rejected_notarization_never_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(release, "DIST", Path(directory)), patch.object(release, "run"), \
                 patch.object(release, "package") as package, \
                 patch.object(release.subprocess, "run", side_effect=[
                     subprocess.CompletedProcess([], 1, json.dumps({"id": "submission", "status": "Invalid"}), ""),
                     subprocess.CompletedProcess([], 0, '{"issues": []}', "")]):
                with self.assertRaisesRegex(SystemExit, "not accepted"):
                    release.notarize()
                package.assert_not_called()
                self.assertTrue((Path(directory) / "notarization-log.json").exists())

    def test_required_signing_fails_without_secrets(self):
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            env = {"PATH": os.environ["PATH"], "GITHUB_OUTPUT": str(output), "REQUIRE_SIGNING": "true"}
            command = ["bash", str(ROOT / "scripts/notarize-ci.sh")]
            required = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertNotEqual(required.returncode, 0)
            self.assertFalse(output.exists())
            env["REQUIRE_SIGNING"] = "false"
            optional = subprocess.run(command, env=env, capture_output=True, text=True)
            self.assertEqual(optional.returncode, 0)
            self.assertEqual(output.read_text(), "signed=false\n")


if __name__ == "__main__":
    unittest.main()
