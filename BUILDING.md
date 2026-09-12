# Build instructions

## Build

Requires macOS 13+, Xcode with Swift 5.9+, Python 3 and Make.

Clone the repository with its tags. Versions come from `git describe --abbrev=7 --dirty --always --tags`, as in the Gear emulators: a tag such as `0.1.0`, an intermediate build such as `0.1.0-3-gabc1234`, or a commit hash before the first tag. The app, About panel and ZIP use that same version. There is no version number to edit in source.

```sh
brew install llvm lld
export PATH="$(brew --prefix llvm)/bin:$(brew --prefix lld)/bin:$PATH"
make test
make app
open "build/SMAC Launcher.app"
```

`make app` builds a universal arm64/x86_64 app and `build/smac-launcher-cli`. The first build downloads verified FFmpeg source. Developer builds are ad-hoc signed. `LLVM_DLLTOOL` and `LLD` can override the corresponding tool paths.

`make dist` builds and checks the application ZIP, matching FFmpeg source archive and checksums in `dist/`. It does not publish anything.

## Work on the launcher

Keep changes focused and add tests for behavior that can regress. Use the existing Swift style; native code uses C99 and Allman braces. Run `make test` and `make dist` before submitting a pull request.

Use a separate data directory when testing installation or gameplay:

```sh
open "build/SMAC Launcher.app" --args --data-dir "$PWD/.local/test"
build/smac-launcher-cli --help
```

The CLI also supports `create-profile`, `configure-profile`, `add-mod` and `install-mod`. Use `play smacx --profile NAME` to test a specific mod configuration. `status` lists configuration IDs. Keep mod downloads and game-based acceptance fixtures in `.local/`; the automated tests use synthetic executables and files.

Keep game files, saves, runtime downloads, logs and signing credentials out of Git. `.local/`, `build/` and `dist/` are ignored. `make clean` removes build outputs and release archives; it keeps `.local/`.

Bug reports should include the app version, macOS version, Mac model and steps to reproduce. Diagnostics are available in **File → Export Diagnostics**; review logs for personal information before attaching them.

## Homebrew releases

**Update Homebrew Tap** updates `Casks/smac-launcher.rb` in `drhelius/homebrew-centauri` when a stable GitHub release is published. It uses the existing universal release ZIP and verifies its published checksum. Drafts and prereleases are excluded. The workflow can also be run manually for the latest stable release or a specified `x.y.z` tag; it refuses version downgrades.

Set `HOMEBREW_TAP_TOKEN` in this launcher's repository secrets. Use a fine-grained GitHub token owned by `drhelius`, limited to `homebrew-centauri`, with **Contents: Read and write**. No secret or workflow is needed in the tap repository. The same token name is used by the emulator tap workflows.

After pushing the workflow and configuring the secret, run **Actions → Update Homebrew Tap → Run workflow** to add the current release. Future published releases update the cask automatically. Homebrew downloads the app from GitHub Releases; the matching FFmpeg source stays alongside that release. Game files and saves are preserved when uninstalling, including with `--zap`.
