#!/usr/bin/env python3
"""Reject accidental game data, dependencies, private keys and development files."""
import pathlib
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
archives = list((root / "dist").glob("SMAC-Launcher-*-macOS.zip"))
if not archives:
    raise SystemExit("No release archive found.")
allowed = {
    "SMAC Launcher.app/Contents/Info.plist",
    "SMAC Launcher.app/Contents/Resources/AppIcon.icns",
    "SMAC Launcher.app/Contents/Resources/AppIcon.png",
    "SMAC Launcher.app/Contents/MacOS/SMACLauncher",
    "SMAC Launcher.app/Contents/Resources/LICENSE",
    "SMAC Launcher.app/Contents/Resources/THIRD_PARTY.md",
    "SMAC Launcher.app/Contents/Resources/MovieTools/centauri-convert",
    "SMAC Launcher.app/Contents/Resources/MovieTools/centauri-movie-player",
    "SMAC Launcher.app/Contents/Resources/MovieTools/centauri_movies.dll",
    "SMAC Launcher.app/Contents/Resources/MovieTools/FFmpeg-LICENSE.txt",
}
for archive in archives:
    with zipfile.ZipFile(archive) as file:
        for item in file.infolist():
            name = item.filename
            if name.startswith("/") or ".." in pathlib.PurePosixPath(name).parts:
                raise SystemExit(f"Unsafe archive member: {name}")
            if item.is_dir() or name.startswith("__MACOSX/"):
                continue
            if name not in allowed and not name.startswith("SMAC Launcher.app/Contents/_CodeSignature/"):
                raise SystemExit(f"Unexpected release payload: {name}")
        if not {"SMAC Launcher.app/Contents/Info.plist", "SMAC Launcher.app/Contents/MacOS/SMACLauncher"}.issubset(file.namelist()):
            raise SystemExit("Missing app files.")
    print(f"Verified explicit game-free payload: {archive.name}")
