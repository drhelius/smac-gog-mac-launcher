#!/usr/bin/env python3
"""Build a universal, game-free Mac application. No external Python packages."""
import pathlib
import shutil
import subprocess
from build_movies import build as build_movies

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
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
    shutil.copy2(ROOT / "resources/Info.plist", app / "Contents/Info.plist")
    for name in ["LICENSE", "THIRD_PARTY.md"]:
        if (ROOT / name).exists():
            shutil.copy2(ROOT / name, resources / name)
    shutil.copy2(binary_dir / "centauri-cli", ROOT / "build/smac-launcher-cli")
    artwork = ROOT / "resources/artwork/smac-launcher-icon.png"
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
    tools = build_movies(ROOT / "build/MovieTools")
    shutil.copy2(binary_dir / "centauri-movie-player", tools / "centauri-movie-player")
    # Linker byproducts are developer-only; the app needs only the DLL itself.
    for suffix in [".lib", ".exp"]:
        generated = tools / ("centauri_movies" + suffix)
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
