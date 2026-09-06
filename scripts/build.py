#!/usr/bin/env python3
"""Build a universal, game-free Mac application. No external Python packages."""
import pathlib
import shutil
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent


def main():
    subprocess.run(["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64"],
                   cwd=ROOT, check=True)
    binary_dir = pathlib.Path(subprocess.check_output(
        ["swift", "build", "-c", "release", "--arch", "arm64", "--arch", "x86_64", "--show-bin-path"],
        cwd=ROOT, text=True).strip())
    app = ROOT / "build/Centauri.app"
    if app.exists():
        shutil.rmtree(app)
    macos = app / "Contents/MacOS"
    resources = app / "Contents/Resources"
    macos.mkdir(parents=True)
    resources.mkdir()
    shutil.copy2(binary_dir / "Centauri", macos / "Centauri")
    shutil.copy2(ROOT / "resources/Info.plist", app / "Contents/Info.plist")
    for name in ["LICENSE", "THIRD_PARTY.md"]:
        if (ROOT / name).exists():
            shutil.copy2(ROOT / name, resources / name)
    shutil.copy2(binary_dir / "centauri-cli", ROOT / "build/centauri-cli")
    subprocess.run(["codesign", "--force", "--sign", "-", str(app)], check=True)
    subprocess.run(["lipo", "-archs", str(macos / "Centauri")], check=True)
    print(app)


if __name__ == "__main__":
    main()
