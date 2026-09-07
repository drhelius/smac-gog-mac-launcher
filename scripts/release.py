#!/usr/bin/env python3
"""Sign, notarize, or package an existing build. Never publishes automatically."""
import argparse
import hashlib
import json
import os
import pathlib
import plistlib
import subprocess
from build_movies import VERSION as FFMPEG_VERSION, SHA256 as FFMPEG_SHA256
from check_package import verify_dist
from git_version import git_version, validate_version

ROOT = pathlib.Path(__file__).resolve().parent.parent
APP = ROOT / "build/SMAC Launcher.app"
DIST = ROOT / "dist"


def run(*args):
    subprocess.run([str(arg) for arg in args], cwd=ROOT, check=True)


def version():
    with (APP / "Contents/Info.plist").open("rb") as file:
        value = plistlib.load(file)["CFBundleShortVersionString"]
    return validate_version(value)


def check_tag(tag):
    expected = git_version()
    if tag != expected:
        raise SystemExit(f"Release tag {tag!r} must match the clean Git version {expected!r}.")
    print(f"Release version: {expected}")


def package():
    DIST.mkdir(exist_ok=True)
    source = DIST / f"ffmpeg-{FFMPEG_VERSION}.tar.xz"
    if not source.is_file() or hashlib.sha256(source.read_bytes()).hexdigest() != FFMPEG_SHA256:
        raise SystemExit("Missing or invalid matching FFmpeg source. Run make app first.")
    archive = DIST / f"SMAC-Launcher-{version()}-macOS.zip"
    if archive.exists():
        archive.unlink()
    # App is assembled from explicit inputs; no game, prefix, credential or test artifact is packaged.
    run("ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", APP, archive)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (DIST / "SHA256SUMS").write_text(f"{digest}  {archive.name}\n")
    with (DIST / "SHA256SUMS").open("a") as file:
        file.write(f"{FFMPEG_SHA256}  {source.name}\n")
    verify_dist(DIST, version())
    print(archive)


def sign():
    identity = os.environ.get("MACOS_CERTIFICATE_NAME")
    if not identity:
        raise SystemExit("Set MACOS_CERTIFICATE_NAME to your Developer ID Application identity.")
    for name in ["centauri-convert", "centauri-movie-player"]:
        helper = APP / "Contents/Resources/MovieTools" / name
        run("codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, helper)
    run("codesign", "--force", "--timestamp", "--options", "runtime", "--sign", identity, APP)
    run("codesign", "--verify", "--deep", "--strict", "--verbose=2", APP)


def notarize():
    profile = os.environ.get("NOTARY_PROFILE", "centauri-notary")
    DIST.mkdir(exist_ok=True)
    submission = DIST / "SMAC-Launcher-notarization.zip"
    if submission.exists():
        submission.unlink()
    run("codesign", "--verify", "--deep", "--strict", APP)
    run("ditto", "-c", "-k", "--keepParent", APP, submission)
    # Polling is performed by Apple's tool. Credentials stay in the keychain, never command arguments.
    keychain = ["--keychain", os.environ["NOTARY_KEYCHAIN"]] if os.environ.get("NOTARY_KEYCHAIN") else []
    result = subprocess.run(
        ["xcrun", "notarytool", "submit", str(submission), "--keychain-profile", profile,
         *keychain, "--wait", "--output-format", "json"], cwd=ROOT, text=True, capture_output=True)
    try:
        report = json.loads(result.stdout)
    except json.JSONDecodeError:
        raise SystemExit(f"Notarization submission failed: {result.stderr.strip()}")
    (DIST / "notarization.json").write_text(json.dumps(report, indent=2) + "\n")
    if result.returncode != 0 or report.get("status") != "Accepted":
        if report.get("id"):
            log = subprocess.run(["xcrun", "notarytool", "log", report["id"],
                "--keychain-profile", profile, *keychain], cwd=ROOT, text=True, capture_output=True)
            if log.returncode == 0:
                (DIST / "notarization-log.json").write_text(log.stdout)
        raise SystemExit(f"Notarization was not accepted; submission {report.get('id')}. Inspect Apple's log.")
    run("xcrun", "stapler", "staple", APP)
    run("xcrun", "stapler", "validate", APP)
    run("spctl", "--assess", "--type", "execute", "--verbose=2", APP)
    package()
    submission.unlink()


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=["sign", "notarize", "package", "check-tag"])
    parser.add_argument("--tag", help="Version tag to check against Git")
    args = parser.parse_args()
    if args.action == "check-tag":
        if not args.tag:
            parser.error("check-tag requires --tag")
        check_tag(args.tag)
        raise SystemExit(0)
    if not APP.is_dir():
        raise SystemExit("Run make app first.")
    {"sign": sign, "notarize": notarize, "package": package}[args.action]()
