# SMAC Launcher

Play **Sid Meier's Alpha Centauri** and **Alien Crossfire** on your Mac with your own GOG Planetary Pack.

[Downloads](https://github.com/drhelius/smac-gog-mac-launcher/releases) · [GOG Planetary Pack](https://www.gog.com/en/game/sid_meiers_alpha_centauri) · [Report an issue](https://github.com/drhelius/smac-gog-mac-launcher/issues)

<img width="1012" height="840" alt="image" src="https://github.com/user-attachments/assets/10e1d573-73ea-42d0-8f7b-e2263c6a5128" />


## Requirements

- macOS 13 or later. Apple Silicon requires Rosetta, available from the launcher's Help menu.
- Your GOG game: the installed Mac app, a Windows game folder, or the Windows offline installer with its companion `.bin` files.
- 4 GB free space and an internet connection for initial setup. Play offline afterward.

## Install

With [Homebrew](https://brew.sh), run this in Terminal:

```sh
brew install --cask drhelius/centauri/smac-launcher
```

If Homebrew asks you to trust the third-party tap, run `brew trust --tap drhelius/centauri`, then retry the install command.

Or [download the macOS ZIP](https://github.com/drhelius/smac-gog-mac-launcher/releases), unzip it and move **SMAC Launcher.app** to Applications.

## Play

1. Open **SMAC Launcher** from Applications, choose your GOG game files and click **Install**. You can import existing saves during setup.
2. Select **Alpha Centauri** or **Alien Crossfire** and click **Play**.

Choose fullscreen or a movable window, watch cutscenes, and adjust display, audio and gameplay options in **Advanced Settings**. Use **Saved Games** to find your saves. Updating the launcher keeps your installed game and saves.

## Mods

Select the game, then choose **Mods → New Configuration**. This makes a separate copy of your installed game and saves. Give it a name, then install the mod using one of these actions:

| Action | When to use it |
| --- | --- |
| **Install from Folder…** | The mod is distributed as files, usually inside a ZIP. Extract it first, then select the folder containing the mod files. Its contents are copied into the selected configuration, replacing matching files there. |
| **Run Installer (.exe)…** | The mod provides a Windows setup program. Select that `.exe` and choose `C:\SMAC` as the destination inside its installer. |

These are alternatives; most mods need only one. Neither action downloads mods for you. Follow the mod author's installation instructions.

Open **Mods → Edit Configuration**, select the executable that starts the mod, and save. **Arguments** are optional command-line options. **Working folder** is an optional subfolder; leave it empty for most mods. Then click **Play**.

### Compatibility mode

This selects which launcher features are used. **It does not install, remove or switch mods.** Leave **Automatic** selected unless you need to override detection.

| Mode | Behavior |
| --- | --- |
| **Automatic** | Detects recognized original executables, PRACX and Thinker. Otherwise uses Custom executable behavior. |
| **Original game** | Enables the launcher's movie and display fixes for recognized original GOG executables. |
| **PRACX** | Uses PRACX's display controls and the launcher's native movie player. PRACX controls window/fullscreen switching with Alt+Enter. |
| **Thinker** | Enables Thinker-specific display handling and native movies. If PRACX is also installed and detected, PRACX controls the display. |
| **Custom executable** | Runs your selected executable and arguments, leaving display, audio and movie settings to the mod. No game compatibility patches are applied. |

### Examples

- **PRACX:** create a configuration and use **Run Installer (.exe)…** with its Windows installer. Select the patched `terran.exe` or `terranx.exe`. If your game already includes separate PRACX executables, select `terran_PRACX.exe` or `terranx_PRACX.exe` instead.
- **Thinker:** select **Alien Crossfire**, create a configuration, extract Thinker's ZIP and use **Install from Folder…** on the folder containing `thinker.exe`, `thinker.dll` and `thinker.ini`. Select `thinker.exe`; keep Compatibility mode on Automatic.

**Game Files**, **Saved Games** and settings refer to the selected configuration. Select **Original** to return to your original installation. **Remove Configuration…** moves that configuration, including its saves, to Trash.

---

[Build from source](BUILDING.md) · [MIT license](LICENSE) · [Third-party notices](THIRD_PARTY.md)
