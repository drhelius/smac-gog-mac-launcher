#!/usr/bin/env python3
"""Decode a user's local WVE files without opening windows. Outputs stay outside the game."""
import argparse
from concurrent.futures import ThreadPoolExecutor
import json
import pathlib
import subprocess


def main():
    root = pathlib.Path(__file__).resolve().parent.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", required=True, type=pathlib.Path)
    parser.add_argument("--output", required=True, type=pathlib.Path)
    parser.add_argument("--converter", type=pathlib.Path, default=root / "build/MovieTools/centauri-convert")
    args = parser.parse_args()
    source = args.source.resolve()
    if (source / "movies").is_dir():
        source /= "movies"
    output = args.output.resolve()
    if output == source or source in output.parents:
        raise SystemExit("Use an output folder outside the source movies folder.")
    movies = sorted(p for p in source.glob("*.wve") if p.is_file() and not p.is_symlink())
    if not movies:
        raise SystemExit("No WVE movies found.")
    output.mkdir(parents=True, exist_ok=True)

    def check(movie):
        log = output / (movie.stem + ".log")
        target = output / (movie.stem + ".mp4")
        with log.open("wb") as file:
            try:
                status = subprocess.run([str(args.converter), "-nostdin", "-y", "-i", str(movie),
                    "-c:v", "h264_videotoolbox", "-b:v", "2M", "-pix_fmt", "yuv420p",
                    "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", str(target)],
                    stdout=file, stderr=subprocess.STDOUT, timeout=180).returncode
            except subprocess.TimeoutExpired:
                status = 124
        text = log.read_text(errors="replace")
        return {"movie": movie.name, "exit": status, "bytes": target.stat().st_size if target.exists() else 0,
                "decode_warning": "Decoding error" in text}

    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(check, movies))
    (output / "results.json").write_text(json.dumps(results, indent=2) + "\n")
    failures = [r for r in results if r["exit"] or not r["bytes"]]
    print(json.dumps({"count": len(results), "failed": failures,
                      "with_decode_warnings": sum(r["decode_warning"] for r in results)}, indent=2))
    if failures:
        raise SystemExit(1)


if __name__ == "__main__":
    main()
