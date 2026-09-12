#!/usr/bin/env python3
"""Build a universal, game-free Mac application. No external Python packages."""
import pathlib
import shutil
import subprocess
import json
import plistlib
from build_movies import build as build_movies
from git_version import git_version

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    version = git_version()
    subprocess.run(["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64"],
                   cwd=ROOT, check=True)
    binary_dir = pathlib.Path(subprocess.check_output(
        ["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64", "--show-bin-path"],
        cwd=ROOT, text=True).strip())
    app = ROOT / "build/SMAC Launcher.app"
    if app.exists():
        shutil.rmtree(app)
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(binary_dir / "Centauri", macos / "SMACLauncher")
    with (ROOT / "resources/Info.plist").open("rb") as file:
        info = plistlib.load(file)
    info["CFBundleShortVersionString"] = version
    info["CFBundleVersion"] = version
    info["SMACBuildCommit"] = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    with (app / "Contents/Info.plist").open("wb") as file:
        plistlib.dump(info, file, sort_keys=False)
    for name in ["LICENSE", "THIRD_PARTY.md"]:
        if (ROOT / name).exists():
            shutil.copy2(ROOT / name, resources / name)
    shutil.copy2(binary_dir / "centauri-cli", ROOT / "build/smac-launcher-cli")
    artwork = ROOT / "resources/artwork/smac-launcher-square.png"
    shutil.copy2(artwork, resources / "AppIcon.png")
    iconset = ROOT / "build/AppIcon.iconset"
    if iconset.exists():
        shutil.rmtree(iconset)
    iconset.mkdir()
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            suffix = "@2x" if scale == 2 else ""
            subprocess.run(["sips", "-z", str(size * scale), str(size * scale), str(artwork),
                "--out", str(iconset / f"icon_{size}x{size}{suffix}.png")], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(resources / "AppIcon.icns")], check=True)
    catalog = ROOT / "build/Icons.xcassets"
    appicons = catalog / "AppIcon.appiconset"
    if catalog.exists():
        shutil.rmtree(catalog)
    appicons.mkdir(parents=True)
    entries = []
    for size in [16, 32, 128, 256, 512]:
        for scale in [1, 2]:
            suffix = "@2x" if scale == 2 else ""
            name = f"icon_{size}x{size}{suffix}.png"
            shutil.copy2(iconset / name, appicons / name)
            entries.append({"idiom": "mac", "size": f"{size}x{size}", "scale": f"{scale}x", "filename": name})
    (appicons / "Contents.json").write_text(json.dumps({"images": entries, "info": {"author": "xcode", "version": 1}}))
    subprocess.run(["xcrun", "actool", str(catalog), "--compile", str(resources), "--platform", "macosx",
        "--minimum-deployment-target", "13.0", "--app-icon", "AppIcon", "--output-partial-info-plist",
        str(ROOT / "build/icon-info.plist")], check=True)
    tools = build_movies(ROOT / "build/MovieTools")
    shutil.copy2(binary_dir / "centauri-movie-player", tools / "centauri-movie-player")
    # Linker byproducts are developer-only; the app needs only the DLL itself.
    for suffix in [".lib", ".exp"]:
        for name in ["centauri_movies", "centauri_window"]:
            generated = tools / (name + suffix)
            if generated.exists():
                generated.unlink()
    shutil.copytree(tools, resources / "MovieTools")
    for name in ["centauri-convert", "centauri-movie-player"]:
        subprocess.run(["codesign", "--force", "--sign", "-", str(resources / "MovieTools" / name)], check=True)
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["lipo", "-archs", str(macos / "SMACLauncher")], check=True)
    print(app)


if __name__ == "__main__":
    main()
