#!/usr/bin/env python3
"""Reject accidental game data, dependencies, private keys and development files."""
import pathlib
import zipfile

root = pathlib.Path(__file__).resolve().parent.parent
archives = list((root / "dist").glob("Centauri-*-macOS.zip"))
if not archives:
    raise SystemExit("No release archive found.")
allowed = {
    "Centauri.app/Contents/Info.plist",
    "Centauri.app/Contents/MacOS/Centauri",
    "Centauri.app/Contents/Resources/LICENSE",
    "Centauri.app/Contents/Resources/THIRD_PARTY.md",
}
for archive in archives:
    with zipfile.ZipFile(archive) as file:
        for item in file.infolist():
            name = item.filename
            if name.startswith("/") or ".." in pathlib.PurePosixPath(name).parts:
                raise SystemExit(f"Unsafe archive member: {name}")
            if item.is_dir() or name.startswith("__MACOSX/"):
                continue
            if name not in allowed and not name.startswith("Centauri.app/Contents/_CodeSignature/"):
                raise SystemExit(f"Unexpected release payload: {name}")
        if not {"Centauri.app/Contents/Info.plist", "Centauri.app/Contents/MacOS/Centauri"}.issubset(file.namelist()):
            raise SystemExit("Missing app files.")
    print(f"Verified explicit game-free payload: {archive.name}")
