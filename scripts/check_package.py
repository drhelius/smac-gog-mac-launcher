#!/usr/bin/env python3
"""Validate the application payload, matching source archive and release checksums."""
import argparse
import hashlib
import pathlib
import plistlib
import stat
import zipfile
from build_movies import VERSION as SOURCE_VERSION, SHA256 as SOURCE_SHA256
from git_version import git_version, validate_version

ROOT = pathlib.Path(__file__).resolve().parent.parent
PREFIX = "SMAC Launcher.app/Contents/"
REQUIRED = {
    PREFIX + "Info.plist",
    PREFIX + "Resources/AppIcon.icns",
    PREFIX + "Resources/AppIcon.png",
    PREFIX + "Resources/Assets.car",
    PREFIX + "MacOS/SMACLauncher",
    PREFIX + "Resources/LICENSE",
    PREFIX + "Resources/THIRD_PARTY.md",
    PREFIX + "Resources/MovieTools/centauri-convert",
    PREFIX + "Resources/MovieTools/centauri-movie-player",
    PREFIX + "Resources/MovieTools/centauri_movies.dll",
    PREFIX + "Resources/MovieTools/FFmpeg-LICENSE.txt",
}
# stapler adds Contents/CodeResources alongside the separate code-signature manifest.
ALLOWED = REQUIRED | {PREFIX + "_CodeSignature/CodeResources", PREFIX + "CodeResources"}
DIRECTORIES = {str(parent) for name in ALLOWED for parent in pathlib.PurePosixPath(name).parents if str(parent) != "."}


def verify_archive(archive, version):
    with zipfile.ZipFile(archive) as file:
        names = file.namelist()
        if len(names) != len(set(names)):
            raise SystemExit("Duplicate archive members.")
        for item in file.infolist():
            name = item.filename
            path = pathlib.PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or "\\" in name:
                raise SystemExit(f"Unsafe archive member: {name}")
            if stat.S_ISLNK(item.external_attr >> 16):
                raise SystemExit(f"Symlink in release payload: {name}")
            if name.startswith("__MACOSX/"):
                # ditto's AppleDouble metadata is allowed only for known app entries.
                metadata = name.removeprefix("__MACOSX/").rstrip("/")
                if item.is_dir() and (not metadata or metadata in DIRECTORIES):
                    continue
                target = str(pathlib.PurePosixPath(metadata).with_name(path.name[2:]))
                if path.name.startswith("._") and target in ALLOWED | DIRECTORIES:
                    continue
                raise SystemExit(f"Unexpected archive metadata: {name}")
            if item.is_dir() and name.rstrip("/") in DIRECTORIES:
                continue
            if name not in ALLOWED:
                raise SystemExit(f"Unexpected release payload: {name}")
            if item.file_size == 0:
                raise SystemExit(f"Empty app file: {name}")
        missing = REQUIRED - set(names)
        if missing:
            raise SystemExit(f"Missing app files: {', '.join(sorted(missing))}")
        info = plistlib.loads(file.read(PREFIX + "Info.plist"))
        if info.get("CFBundleShortVersionString") != version:
            raise SystemExit("The archive version does not match the release.")
        if info.get("CFBundleIdentifier") != "com.drhelius.centauri":
            raise SystemExit("Unexpected application identifier.")


def verify_dist(directory, version):
    archive = directory / f"SMAC-Launcher-{version}-macOS.zip"
    source = directory / f"ffmpeg-{SOURCE_VERSION}.tar.xz"
    for path in [archive, source, directory / "SHA256SUMS"]:
        if not path.is_file():
            raise SystemExit(f"Missing release file: {path.name}")
    if hashlib.sha256(source.read_bytes()).hexdigest() != SOURCE_SHA256:
        raise SystemExit("FFmpeg source does not match the pinned build.")
    expected = {archive.name: hashlib.sha256(archive.read_bytes()).hexdigest(), source.name: SOURCE_SHA256}
    checksums = {}
    for line in (directory / "SHA256SUMS").read_text().splitlines():
        parts = line.split("  ", 1)
        if len(parts) != 2 or parts[1] in checksums:
            raise SystemExit("Malformed or duplicate release checksum.")
        checksums[parts[1]] = parts[0]
    if checksums != expected:
        raise SystemExit("Release checksums or file list do not match.")
    verify_archive(archive, version)
    print(f"Verified release payload and source: {archive.name}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dist", type=pathlib.Path, default=ROOT / "dist")
    parser.add_argument("--version", help="Expected Git version (defaults to this checkout)")
    args = parser.parse_args()
    verify_dist(args.dist, validate_version(args.version) if args.version else git_version())
