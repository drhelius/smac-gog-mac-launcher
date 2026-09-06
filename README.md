# Centauri

A small native Mac launcher for the GOG edition of **Sid Meier's Alpha Centauri Planetary Pack**.

**Development preview.** Fullscreen Alpha Centauri gameplay has been tested interactively on an Apple M4 running macOS 26.6.2. Broader compatibility and release acceptance are still in progress. See [validation](docs/VALIDATION.md) for the exact results and limitations.

Centauri imports your purchased game, prepares a dedicated Wine environment, and launches either Alpha Centauri or Alien Crossfire. It preserves your original installation. No game files are included in this repository or its application download.

## Requirements

- macOS 13 or later for the launcher. Currently verified hardware: Apple M4; other Macs remain unverified.
- Rosetta on Apple Silicon. Centauri provides an installation action in Help if needed.
- Your own GOG Planetary Pack: an installed legacy Mac application, an installed Windows game folder, or the Windows offline installer with every companion `.bin` file.
- At least 4 GB free during setup and an internet connection for the first runtime download (about 342 MB). Later play is offline.

The current Windows offline installer path is implemented but has not yet been tested against a newly downloaded GOG installer. The legacy Mac payload is the initial tested source. GOG Galaxy is not required.

## Use

1. Open **Centauri.app**.
2. Choose your GOG application, game folder, or offline setup executable.
3. Optionally select an existing saves folder, then click **Install Game**.
4. Choose a game and click **Play**. Fullscreen is the default; choose **Window** for a fixed-size desktop.

The opening movie is skipped by default to avoid the old movie/display transition problems. **Other movie categories are not yet validated.** The current profile disables EAX/3D audio and selects the older voxel renderer; regular sound remains enabled. Rules and AI are unchanged, and neither game executable is patched.

Use **Open Saves** to find your saves. Imported saves are placed in a separate `Imported-…` subfolder to avoid overwriting same-named files. Save and quit through the game normally. **Stop Game** force-closes only this installation and may lose unsaved progress.

## Build

Requires Xcode/Command Line Tools with Swift 5.9 or later, Python 3, and Make. The application has no third-party Swift package dependencies.

```sh
make test
make app
open build/Centauri.app
```

`make app` produces a universal arm64/x86_64 application and `build/centauri-cli`. Developer builds receive an ad-hoc signature. `make dist` builds a game-free ZIP; it does not publish it.

For isolated development, use the CLI:

```sh
build/centauri-cli inspect --source "/Applications/Sid Meier's Alpha Centauri Planetary Pack.app"
build/centauri-cli install --data-dir "$PWD/.local/test" --source "/path/to/your/game.app"
build/centauri-cli play smac --data-dir "$PWD/.local/test" --fullscreen
build/centauri-cli play smacx --data-dir "$PWD/.local/test" --fullscreen
```

Use `--help` for offline runtime-archive inputs and diagnostics. The first setup downloads two pinned, SHA-256-verified upstream archives. It extracts only the WineCX engine and the required shared libraries; it does not install the Sikarugir launcher.

## Data and troubleshooting

User data lives in:

```text
~/Library/Application Support/DrHelius/Centauri/
    Installation/game/       Imported game and saves
    Installation/prefix/     Dedicated Windows environment
    Runtimes/                Verified runtime, separate from the signed app
    Logs/                    Recent bounded diagnostic logs
```

Removing or updating `Centauri.app` does not remove this data. The preview refuses to overwrite an existing installation. Back up this folder before manually replacing it. An existing game with altered executable hashes is rejected at launch; mod management is outside the initial scope.

- **Game disappears or minimizes:** use the Centauri display options. Do not launch GOG's old wrapper or `start.exe`.
- **Runtime download fails:** retry; corrupt downloads cannot replace the installed runtime.
- **Rosetta missing:** use Help → Install Rosetta. Installation is performed by Apple's tool after your explicit agreement.
- **Already running:** close the other Centauri/CLI session. Operations are protected by a process lock that automatically releases after a crash.
- **Game hangs:** use Stop Game, then Help → Export Diagnostics. Review the exported text before sharing; file names can appear in Wine logs. Saves and game assets are excluded.
- **Runtime was removed or manually changed:** preserve `Installation/` and its saves. The current preview has no graphical repair/reinstall flow; do not delete your data to troubleshoot it.

## Open source and releases

Centauri's code is MIT licensed. Wine and its dependencies retain their own licenses; the game belongs to its rights holders. See [third-party components](THIRD_PARTY.md).

Repository: [drhelius/smac-gog-mac-launcher](https://github.com/drhelius/smac-gog-mac-launcher). Signing, notarization, GitHub release preparation and website publication are described in [the release guide](docs/RELEASING.md). Publication is a separate step from building.

Rosetta is a current dependency. Apple's general Rosetta support extends through macOS 27; this project does not promise macOS 28 support. [Apple's Rosetta information](https://support.apple.com/en-us/102527).

Centauri is not affiliated with or endorsed by Firaxis, Electronic Arts, GOG, CodeWeavers or Apple.
