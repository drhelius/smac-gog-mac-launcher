#!/usr/bin/env python3
"""Use the same Git version string as the Gear emulator builds."""
import pathlib
import re
import subprocess

ROOT = pathlib.Path(__file__).resolve().parent.parent


def validate_version(value):
    if not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._+-]*", value):
        raise SystemExit(f"Invalid Git version for a release filename: {value!r}")
    return value


def git_version():
    result = subprocess.run(["git", "describe", "--abbrev=7", "--dirty", "--always", "--tags"],
        cwd=ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        raise SystemExit("Build from a Git checkout with its tags; clone the repository instead of a source ZIP.")
    return validate_version(result.stdout.strip())


if __name__ == "__main__":
    print(git_version())
