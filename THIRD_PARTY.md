# Third-party notices

SMAC Launcher's code and original artwork are provided under the [MIT license](LICENSE). That license does not cover the game or third-party components.

## FFmpeg

The app includes a separate converter built from unmodified [FFmpeg 8.0](https://ffmpeg.org/releases/ffmpeg-8.0.tar.xz), under LGPL-2.1-or-later. GPL, nonfree and autodetected external dependencies are disabled. The build recipe is [scripts/build_movies.py](scripts/build_movies.py).

The app includes `MovieTools/FFmpeg-LICENSE.txt`. Every binary release includes the matching `ffmpeg-8.0.tar.xz` source archive, with SHA-256 `b2751fccb6cc4c77708113cd78b561059b6fa904b24162fa0be2d60273d27b8e`. The converter can be rebuilt using the checked-in recipe and macOS system frameworks.

## Wine

Wine and supporting libraries are downloaded directly from upstream during setup; they are not bundled in the application download. Wine is LGPL-licensed, and its dependencies retain their respective licenses.

- [Sikarugir WineCX engine](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz)
- [Gcenx macOS libraries](https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz)
- [WineCX source](https://www.codeweavers.com/crossover/source) and [Sikarugir Wine source](https://github.com/Sikarugir-App/wine)

Exact runtime URLs and checksums are maintained in [Runtime.swift](Sources/CentauriCore/Runtime.swift). A combined runtime is not distributed by this project; doing so would require the applicable dependency notices, source and build materials.

## Acknowledgements

[PRACX](https://github.com/DrazharLn/pracx) provided reference information for movie entry points and the original renderer's teardown. Its renderer and binaries are not included. SMAC Launcher's movie hook and native player are MIT-licensed project code.

The user supplies the GOG game. Its files, fonts, music, videos and saved games are not included in this repository or releases. Sid Meier's Alpha Centauri and Alien Crossfire belong to their respective rights holders. SMAC Launcher is not affiliated with Firaxis, Electronic Arts, GOG, CodeWeavers or Apple.
