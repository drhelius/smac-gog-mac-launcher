# Third-party components and provenance

The application source is MIT licensed. That license does not cover the game, Wine, fonts, codecs or other upstream components.

## Runtime assembly

The runtime is assembled locally from two unmodified, hash-pinned public downloads. The version, URLs and expected digests are authoritative in `Sources/CentauriCore/Runtime.swift`. The preview application ZIP contains neither archive nor an installed runtime.

| Component | Source artifact | SHA-256 |
| --- | --- | --- |
| WineCX engine | [WS12WineCX24.0.7_7.tar.xz](https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz) | `203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c` |
| Supporting Mac dylibs | [wine-stable-11.0_1-osx64.tar.xz](https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz) | `b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388` |

The engine identifies itself as `wine-9.0 (SikarugirCX 24.0.7)`. The archive's `version` file says `WineCX 24.0.7 (revision 6)`; preserve both labels rather than infer the source revision from the `_7` packaging suffix.

Only top-level `.dylib` files under `Wine Stable.app/Contents/Resources/wine/lib/` are taken from the second archive. They are copied alongside `wswine.bundle`; a controlled `DYLD_FALLBACK_LIBRARY_PATH` supplies the runtime's library lookup path. The upstream Wine 11 executable is not used. This assembled combination is project-specific and must be retested when either artifact changes.

Primary upstream references:

- [WineHQ macOS package maintainer](https://github.com/Gcenx/macOS_Wine_builds), including build/dependency information.
- [Wine engine distribution](https://github.com/Sikarugir-App/Engines).
- [CodeWeavers source distributions](https://www.codeweavers.com/crossover/source), the starting point for WineCX source provenance.
- [Sikarugir Wine source repository](https://github.com/Sikarugir-App/wine).
- [Published Rosetta transition workaround](https://github.com/Gcenx/game-porting-toolkit/blob/main/dlls/wow64cpu/cpu.c), useful diagnostic context, not code copied into Centauri.

Wine is LGPL-licensed; its engine includes additional upstream components such as Wine Mono/Gecko, each with separate terms. The support dylibs have multiple licenses. Do not treat every component as MIT or assume that the engine archive name completely identifies all downstream source modifications.

## Public binary distribution boundary

The current package distributes only our launcher and notices. Runtime downloads come directly from the pinned upstream URLs. Before hosting a combined runtime or bundling one in our ZIP, complete an artifact-level license inventory and provide the corresponding source, notices and build/patch materials required by those licenses. That additional redistribution audit is not complete in this preview.

The Sikarugir launcher and Creator are not used or redistributed. Its mixed wrapper licensing does not become our launcher's license. Apple's D3DMetal/GPTK binaries are not included or downloaded by Centauri.

## Game ownership

The user supplies their GOG installer or installed game. Executables, DLLs, audio, fonts, videos and other game assets remain local. Do not commit game files, user saves or copied Wine prefixes. The original game EULA still applies to the user's installation.
