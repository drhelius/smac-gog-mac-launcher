#!/usr/bin/env python3
"""Sign, notarize, or package an existing build. Never publishes automatically."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "build/Centauri.app"
DIST = ROOT / "dist"


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def version():
    with (APP / "Contents/Info.plist").open("rb") as file:
        return plistlib.load(file)["CFBundleShortVersionString"]


def package():
    DIST.mkdir(exist_ok=True)
    archive = DIST / f"Centauri-{version()}-macOS.zip"
    if archive.exists():
        archive.unlink()
    # App is assembled from explicit inputs; no game, prefix, credential or test artifact is packaged.
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n")
    print(archive)


def sign():
    identity = os.environ.get("MACOS_CERTIFICATE_NAME")
    if not identity:
        raise SystemExit("Set MACOS_CERTIFICATE_NAME to your Developer ID Application identity.")
    run("codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, APP)
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", APP)


def notarize():
    profile = os.environ.get("NOTARY_PROFILE", "centauri-notary")
    DIST.mkdir(exist_ok=True)
    submission = DIST / "Centauri-notarization.zip"
    if submission.exists():
        submission.unlink()
    run("codesign", "--verify", "--deep", "--strict", APP)
    run("ditto", "-c", "-k", "--keepParent", APP, submission)
    # Polling is performed by Apple's tool. Credentials stay in the keychain, never command arguments.
    result = subprocess.check_output(
        ["xcrun", "notarytool", "submit", str(submission), "--keychain-profile", profile,
         "--wait", "--output-format", "json"], cwd=ROOT, text=True)
    report = json.loads(result)
    (DIST / "notarization.json").write_text(json.dumps(report, indent=2) + "\n")
    if report.get("status") != "Accepted":
        raise SystemExit(f"Notarization was not accepted; submission {report.get('id')}. Inspect Apple's log.")
    run("xcrun", "stapler", "staple", APP)
    run("xcrun", "stapler", "validate", APP)
    run("spctl", "--assess", "--type", "execute", "--verbose=2", APP)
    package()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["sign", "notarize", "package"])
    args = parser.parse_args()
    if not APP.is_dir():
        raise SystemExit("Run make app first.")
    {"sign": sign, "notarize": notarize, "package": package}[args.action]()
