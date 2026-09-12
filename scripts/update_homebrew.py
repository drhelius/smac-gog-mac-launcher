#!/usr/bin/env python3
"""Generate the Homebrew cask from a verified, published SMAC Launcher release."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import subprocess
import tempfile
import zipfile

REPOSITORY = "drhelius/smac-gog-mac-launcher"


def version_tuple(version):
    if not re.fullmatch(r"(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)", version):
        raise ValueError("The Homebrew tap requires a stable x.y.z release tag.")
    return tuple(int(part) for part in version.split("."))


def render_cask(version, checksum):
    version_tuple(version)
    if not re.fullmatch(r"[0-9a-f]{64}", checksum):
        raise ValueError("Invalid SHA256 checksum.")
    return f'''cask "smac-launcher" do
  version "{version}"
  sha256 "{checksum}"

  url "https://github.com/{REPOSITORY}/releases/download/#{{version}}/SMAC-Launcher-#{{version}}-macOS.zip"
  name "SMAC Launcher"
  desc "Launcher for the GOG edition of Alpha Centauri and Alien Crossfire"
  homepage "https://github.com/{REPOSITORY}"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "SMAC Launcher.app"

  uninstall quit: "com.drhelius.centauri"

  zap trash: "~/Library/Preferences/com.drhelius.centauri.plist"

  caveats do
    requires_rosetta
  end
end
'''


def verify_archive(directory, version):
    version_tuple(version)
    filename = f"SMAC-Launcher-{version}-macOS.zip"
    archive = directory / filename
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    matches = [line.split() for line in (directory / "SHA256SUMS").read_text().splitlines()
               if len(line.split()) == 2 and line.split()[1] == filename]
    if len(matches) != 1 or matches[0][0] != checksum:
        raise ValueError("The app ZIP does not match the published SHA256SUMS.")
    with zipfile.ZipFile(archive) as package:
        if package.getinfo("SMAC Launcher.app/Contents/MacOS/SMACLauncher").file_size == 0:
            raise ValueError("The release has no application executable.")
        info = plistlib.loads(package.read("SMAC Launcher.app/Contents/Info.plist"))
        if info.get("CFBundleShortVersionString") != version:
            raise ValueError("The app version does not match the release tag.")
        if info.get("CFBundleIdentifier") != "com.drhelius.centauri":
            raise ValueError("Unexpected application identifier.")
        if info.get("LSMinimumSystemVersion") != "13.0":
            raise ValueError("Update the cask's macOS requirement for this release.")
    return checksum


def write_cask(destination, version, checksum):
    if destination.exists():
        match = re.search(r'^\s*version "([^"]+)"', destination.read_text(), re.MULTILINE)
        if not match:
            raise ValueError("Cannot read the existing cask version.")
        if version_tuple(version) < version_tuple(match[1]):
            raise ValueError("Refusing to replace a newer Homebrew release with an older one.")
    text = render_cask(version, checksum)
    destination.parent.mkdir(parents=True, exist_ok=True)
    destination.write_text(text)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--version", default="", help="Published stable tag; defaults to the latest release")
    parser.add_argument("--output", type=Path, required=True, help="Destination Casks/smac-launcher.rb")
    args = parser.parse_args()
    if args.version:
        version_tuple(args.version)
    command = ["gh", "release", "view"] + ([args.version] if args.version else [])
    result = subprocess.check_output(command + ["--repo", REPOSITORY, "--json", "tagName,isDraft,isPrerelease"], text=True)
    release = json.loads(result)
    if release["isDraft"] or release["isPrerelease"]:
        raise ValueError("Only published stable releases can update the Homebrew tap.")
    version = release["tagName"]
    version_tuple(version)
    with tempfile.TemporaryDirectory(prefix="smac-homebrew-") as temporary:
        directory = Path(temporary)
        subprocess.run(["gh", "release", "download", version, "--repo", REPOSITORY,
            "--pattern", f"SMAC-Launcher-{version}-macOS.zip", "--pattern", "SHA256SUMS", "--dir", str(directory)], check=True)
        checksum = verify_archive(directory, version)
    write_cask(args.output, version, checksum)
    print(f"Prepared smac-launcher {version}: {checksum}")


if __name__ == "__main__":
    try:
        main()
    except (ValueError, OSError, KeyError, zipfile.BadZipFile) as error:
        raise SystemExit(str(error))
