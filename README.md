# SMAC Launcher

A native Mac launcher for the GOG edition of **Sid Meier's Alpha Centauri Planetary Pack**.

Fullscreen Alpha Centauri gameplay has been tested interactively on an Apple M4 running macOS 26.6.2. Broader compatibility and release acceptance are still in progress. See [validation](docs/VALIDATION.md) for the exact results and limitations.

SMAC Launcher imports your purchased game, prepares a dedicated Wine environment, and launches either Alpha Centauri or Alien Crossfire. It preserves your original installation. No game files are included in this repository or its application download.

## Requirements

- macOS 13 or later for the launcher. Currently verified hardware: Apple M4; other Macs remain unverified.
- Rosetta on Apple Silicon. SMAC Launcher provides an installation action in Help if needed.
- Your own GOG Planetary Pack: an installed legacy Mac application, an installed Windows game folder, or the Windows offline installer with every companion `.bin` file.
- At least 4 GB free during setup and an internet connection for the first runtime download (about 342 MB). Later play is offline.

The current Windows offline installer path is implemented but has not yet been tested against a newly downloaded GOG installer. The legacy Mac payload is the initial tested source. GOG Galaxy is not required.

## Use

1. Open **SMAC Launcher.app**.
2. Choose your GOG application, game folder, or offline setup executable.
3. Optionally select an existing saves folder, then click **Install**.
4. Choose a game and click **Play**. Fullscreen uses the desktop resolution; **Window** provides a movable window at the selected size.

Opening movies are enabled by default and can be switched off on the main screen. For the verified legacy GOG executables, movies use a native Mac player with an Escape/Skip button. The launcher creates derived executable copies with a presentation hook; the original executables and WVE files remain intact. Videos are converted locally and cached when first played. The default profile disables EAX/3D audio and selects the older voxel renderer; regular sound remains enabled. Rules and AI are unchanged.

Native playback of the opening movie has been visually checked; integration and later movie categories are still being tested. It presents the movie's video and audio, without recreating additional text overlays drawn by the original movie renderer. Other executable versions do not yet have the native movie hook.

Use **Saved Games** to find your saves. Imported saves are placed in a separate `Imported-…` subfolder to avoid overwriting same-named files. Save and quit through the game normally. **Stop Game** force-closes only this installation and may lose unsaved progress.

## Settings

The main window provides game selection, fullscreen/window mode, window size and the opening-movie switch. **Advanced Settings** exposes:

| Tab | Options |
| --- | --- |
| Display | Display mode, custom window dimensions, interface/interlude font sizes, gamma, cutscenes and opening movie |
| Audio | Master, music, effects, speech and movie volume |
| Gameplay | Unit animation, beginner-game preference retention and Windows file dialogs |
| Compatibility | Voxel renderer, resolution switching, 3D audio, EAX and Wine settings |

**Reset Defaults** restores the recommended configuration in the settings sheet; **Save** applies it. In-game audio and display preference changes are read back into the launcher. Existing installations and saved settings survive app updates and the product rename.

## Build

Requires Xcode/Command Line Tools with Swift 5.9 or later, Python 3, Make, LLVM's `llvm-dlltool`, and LLD. The application has no third-party Swift package dependencies. Movie support builds a minimal FFmpeg converter from checksum-verified source; the first build downloads about 11 MB of source.

```sh
brew install llvm lld
export PATH="$(brew --prefix llvm)/bin:$(brew --prefix lld)/bin:$PATH"
make test
make app
open "build/SMAC Launcher.app"
```

`make app` produces a universal arm64/x86_64 application and `build/smac-launcher-cli`. Developer builds receive an ad-hoc signature. `make dist` builds a game-free ZIP; it does not publish it.

The Win32 movie hook is built from C99 source. FFmpeg is built for both Mac architectures with only the EA movie decoders, MP4 output and Apple VideoToolbox/AAC encoding needed here. Its license and matching source archive accompany the release. `LLVM_DLLTOOL` and `LLD` can override tool paths for developers with versioned LLVM installations.

For isolated development, use the CLI:

```sh
build/smac-launcher-cli inspect --source "/Applications/Sid Meier's Alpha Centauri Planetary Pack.app"
build/smac-launcher-cli install --data-dir "$PWD/.local/test" --source "/path/to/your/game.app"
build/smac-launcher-cli play smac --data-dir "$PWD/.local/test" --fullscreen
build/smac-launcher-cli play smacx --data-dir "$PWD/.local/test" --fullscreen
```

Use `--help` for offline runtime-archive inputs and diagnostics. The first setup downloads two pinned, SHA-256-verified upstream archives. It extracts only the WineCX engine and the required shared libraries; it does not install the Sikarugir launcher.

## Data and troubleshooting

User data lives in:

```text
~/Library/Application Support/DrHelius/Centauri/
    Installation/game/       Imported game and saves
    Installation/prefix/     Dedicated Windows environment
    Installation/MovieCache/ Locally converted movies
    Runtimes/                Verified runtime, separate from the signed app
    Logs/                    Recent bounded diagnostic logs
```

Removing or updating `SMAC Launcher.app` does not remove this data. The launcher refuses to overwrite an existing installation. Back up this folder before manually replacing it. An original game executable with an altered hash is rejected at launch; mod management is outside the initial scope. Derived `centauri-terran*.exe` files are regenerated from the verified originals as needed.

- **Game disappears or minimizes:** use the launcher display options. Do not launch GOG's old wrapper or `start.exe`.
- **Runtime download fails:** retry; corrupt downloads cannot replace the installed runtime.
- **Rosetta missing:** use Help → Install Rosetta. Installation is performed by Apple's tool after your explicit agreement.
- **Already running:** close the other launcher/CLI session. Operations are protected by a process lock that automatically releases after a crash.
- **Game hangs:** use Stop Game, then File → Export Diagnostics. Review the exported text before sharing; file names can appear in Wine logs. Saves and game assets are excluded.
- **Runtime was removed or manually changed:** preserve `Installation/` and its saves. The launcher has no graphical repair/reinstall flow; do not delete your data to troubleshoot it.

## Open source and releases

SMAC Launcher's code is MIT licensed. Wine and its dependencies retain their own licenses; the game belongs to its rights holders. See [third-party components](THIRD_PARTY.md).

Repository: [drhelius/smac-gog-mac-launcher](https://github.com/drhelius/smac-gog-mac-launcher). Signing, notarization, GitHub release preparation and website publication are described in [the release guide](docs/RELEASING.md). Publication is a separate step from building.

Rosetta is a current dependency. Apple's general Rosetta support extends through macOS 27; this project does not promise macOS 28 support. [Apple's Rosetta information](https://support.apple.com/en-us/102527).

SMAC Launcher is not affiliated with or endorsed by Firaxis, Electronic Arts, GOG, CodeWeavers or Apple.
