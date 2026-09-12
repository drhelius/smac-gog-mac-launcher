#!/usr/bin/env python3
"""Build a small LGPL FFmpeg converter and our MIT Win32 movie hook from source."""
import hashlib
import os
import pathlib
import shutil
import subprocess
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
VERSION = "8.0"
URL = f"https://ffmpeg.org/releases/ffmpeg-{VERSION}.tar.xz"
SHA256 = "b2751fccb6cc4c77708113cd78b561059b6fa904b24162fa0be2d60273d27b8e"
FLAGS = [
    "--disable-everything", "--disable-autodetect", "--disable-doc", "--disable-debug",
    "--disable-network", "--disable-ffplay", "--disable-ffprobe", "--enable-ffmpeg",
    "--enable-protocol=file", "--enable-demuxer=ea",
    "--enable-decoder=eatqi,eatgq,eatgv,eamad,adpcm_ea,adpcm_ea_r1,adpcm_ea_r2,adpcm_ea_r3,adpcm_ea_xas,pcm_s16le,pcm_s16le_planar",
    "--enable-muxer=mp4", "--enable-encoder=h264_videotoolbox,aac", "--enable-videotoolbox",
    "--enable-filter=buffer,buffersink,abuffer,abuffersink,scale,format,aresample,anull,null",
    "--disable-x86asm", "--enable-cross-compile", "--target-os=darwin", "--cc=/usr/bin/clang",
]


def run(args, **kwargs):
    subprocess.run([str(arg) for arg in args], check=True, **kwargs)


def build(destination):
    destination.mkdir(parents=True, exist_ok=True)
    work = ROOT / ".local/movie-dependencies"
    work.mkdir(parents=True, exist_ok=True)
    archive = ROOT / f".local/runtime/ffmpeg-{VERSION}.tar.xz"
    archive.parent.mkdir(parents=True, exist_ok=True)
    if not archive.exists():
        temporary = archive.with_suffix(".download")
        with urllib.request.urlopen(URL, timeout=60) as response, temporary.open("wb") as output:
            shutil.copyfileobj(response, output)
        temporary.replace(archive)
    if hashlib.sha256(archive.read_bytes()).hexdigest() != SHA256:
        raise SystemExit("FFmpeg source checksum mismatch. Remove the invalid archive and retry.")
    source = work / f"ffmpeg-{VERSION}"
    if not source.exists():
        entries = subprocess.check_output(["/usr/bin/tar", "-tf", str(archive)], text=True).splitlines()
        for entry in entries:
            parts = pathlib.PurePosixPath(entry).parts
            if not parts or parts[0] != f"ffmpeg-{VERSION}" or ".." in parts:
                raise SystemExit("Unsafe path in the verified FFmpeg source archive.")
        run(["/usr/bin/tar", "-xf", archive, "-C", work, "--no-same-owner"])
    outputs = []
    for arch in ["arm64", "x86_64"]:
        build_dir = work / arch
        build_dir.mkdir(exist_ok=True)
        options = FLAGS + [f"--arch={arch}", f"--extra-cflags=-arch {arch} -mmacosx-version-min=13.0",
                           f"--extra-ldflags=-arch {arch} -mmacosx-version-min=13.0"]
        config = build_dir / "centauri-config.txt"
        expected = SHA256 + "\n" + "\n".join(options)
        if not config.exists() or config.read_text() != expected:
            with (build_dir / "configure.log").open("w") as log:
                run([source / "configure", *options], cwd=build_dir, stdout=log, stderr=subprocess.STDOUT)
            config.write_text(expected)
        with (build_dir / "build.log").open("w") as log:
            run(["make", f"-j{min(os.cpu_count() or 2, 8)}", "ffmpeg"], cwd=build_dir, stdout=log, stderr=subprocess.STDOUT)
        outputs.append(build_dir / "ffmpeg")
    run(["lipo", "-create", *outputs, "-output", destination / "centauri-convert"])
    shutil.copy2(source / "COPYING.LGPLv2.1", destination / "FFmpeg-LICENSE.txt")

    dlltool = os.environ.get("LLVM_DLLTOOL") or shutil.which("llvm-dlltool")
    linker = os.environ.get("LLD") or shutil.which("lld-link") or shutil.which("lld")
    if not dlltool or not linker:
        raise SystemExit("Movie hook needs LLVM's llvm-dlltool and lld-link. Install llvm and lld, and add their bin directories to PATH. See BUILDING.md.")
    hook_dir = work / "hook"
    hook_dir.mkdir(exist_ok=True)
    run(["xcrun", "clang", "--target=i686-pc-windows-msvc", "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
         "-ffreestanding", "-fno-builtin", "-fno-stack-protector", "-c", ROOT / "native/movie_hook.c", "-o", hook_dir / "movie_hook.obj"])
    for library in ["kernel32", "user32"]:
        run([dlltool, "-m", "i386", "-k", "-d", ROOT / f"native/{library}.def", "-l", hook_dir / f"{library}.lib"])
    command = [linker] + (["-flavor", "link"] if pathlib.Path(linker).name == "lld" else [])
    run(command + ["/dll", "/machine:x86", "/nodefaultlib", "/entry:DllMain@12", "/safeseh:no", "/timestamp:0",
        "/base:0x18000000", f"/out:{destination / 'centauri_movies.dll'}", hook_dir / "movie_hook.obj", hook_dir / "kernel32.lib", hook_dir / "user32.lib"])
    run(["xcrun", "clang", "--target=i686-pc-windows-msvc", "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
         "-ffreestanding", "-fno-builtin", "-fno-stack-protector", "-c", ROOT / "native/movie_request.c", "-o", hook_dir / "movie_request.obj"])
    run(command + ["/machine:x86", "/subsystem:windows", "/nodefaultlib", "/entry:mainCRTStartup", "/safeseh:no", "/timestamp:0",
        f"/out:{destination / 'centauri-movie-request.exe'}", hook_dir / "movie_request.obj", hook_dir / "kernel32.lib"])
    for name in ["window_hook", "window_loader"]:
        run(["xcrun", "clang", "--target=i686-pc-windows-msvc", "-std=c99", "-O2", "-Wall", "-Wextra", "-Werror",
             "-ffreestanding", "-fno-builtin", "-fno-stack-protector", "-c", ROOT / f"native/{name}.c", "-o", hook_dir / f"{name}.obj"])
    run(command + ["/dll", "/machine:x86", "/nodefaultlib", "/entry:DllMain@12", "/safeseh:no", "/timestamp:0",
        "/base:0x19000000", f"/out:{destination / 'centauri_window.dll'}", hook_dir / "window_hook.obj", hook_dir / "kernel32.lib", hook_dir / "user32.lib"])
    run(command + ["/machine:x86", "/subsystem:windows", "/nodefaultlib", "/entry:mainCRTStartup", "/safeseh:no", "/timestamp:0",
        f"/out:{destination / 'centauri-window-loader.exe'}", hook_dir / "window_loader.obj", hook_dir / "kernel32.lib"])
    # Keep the source available beside the release artifact to satisfy the converter's source distribution.
    dist = ROOT / "dist"
    dist.mkdir(exist_ok=True)
    shutil.copy2(archive, dist / archive.name)
    return destination


if __name__ == "__main__":
    build(ROOT / "build/MovieTools")
