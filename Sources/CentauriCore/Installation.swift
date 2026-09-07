import Foundation

public final class CentauriService
{
    public let layout: Layout
    public init(layout: Layout = Layout()) { self.layout = layout }

    public var manifest: GameManifest?
    {
        try? Files.readJSON(GameManifest.self, from: layout.installation.appendingPathComponent("manifest.json"))
    }

    public func install(source: URL, runtimeArchive: URL? = nil, librariesArchive: URL? = nil, saves: URL? = nil,
                        cancellation: Cancellation, progress: ProgressHandler) throws
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        try recoverInterruptedCommit()
        guard manifest == nil else
        {
            throw CentauriError.message("A game is already installed.")
        }
        let setup = source.pathExtension.lowercased() == "exe"
        let directSource: URL?
        if setup
        {
            guard Files.isRegular(source), source.lastPathComponent.lowercased().hasPrefix("setup_"),
                  source.lastPathComponent.lowercased().contains("alpha"), try GameSource.isWindowsX86(source) else
            {
                throw CentauriError.message("Choose the GOG Windows offline setup executable (setup_…alpha….exe), with all companion .bin files in the same folder.")
            }
            directSource = nil
        }
        else
        {
            let located = try GameSource.discover(source)
            let sourcePath = located.resolvingSymlinksInPath().path
            let destinationPath = layout.root.resolvingSymlinksInPath().path
            guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else
            {
                throw CentauriError.message("Choose a data directory outside the source game folder.")
            }
            _ = try GameSource.validate(located, cancellation: cancellation)
            directSource = located
        }
        try Files.requireSpace(at: layout.root, bytes: 4_000_000_000)
        let runtime = try RuntimeInstaller.ensure(layout: layout, archive: runtimeArchive, librariesArchive: librariesArchive,
                                                  cancellation: cancellation, progress: progress)
        try checkRuntime(runtime, cancellation: cancellation)
        let stage = layout.root.appendingPathComponent(".installation-" + UUID().uuidString)
        try Files.makeDirectory(stage)
        let prefix = stage.appendingPathComponent("prefix")
        let game = stage.appendingPathComponent("game")
        let log = freshLog("install.log")
        defer
        {
            runtime.stop(prefix: prefix, log: log)
            try? FileManager.default.removeItem(at: stage)
        }
        progress("Preparing the Windows environment…")
        try runtime.initialize(prefix: prefix, log: log, cancellation: cancellation)
        var actualSource = directSource
        if setup
        {
            progress("Installing your GOG download. Keep all companion files beside the installer…")
            let status = try Commands.run(runtime.wine,
                [source.path, "/SP-", "/SILENT", "/SUPPRESSMSGBOXES", "/NORESTART", "/DIR=C:\\CentauriImport"],
                environment: runtime.environment(prefix: prefix), directory: source.deletingLastPathComponent(),
                log: log, cancellation: cancellation, timeout: 1800)
            runtime.stop(prefix: prefix, log: log)
            guard status == 0 else
            {
                throw CentauriError.message("The GOG installer failed (\(status)). Check that every companion .bin file is present. Export diagnostics for details.")
            }
            actualSource = try GameSource.discover(prefix.appendingPathComponent("drive_c"))
        }
        guard let actualSource = actualSource else { throw CentauriError.message("No game source was selected.") }
        progress("Importing the game files…")
        var skipped: [String] = []
        try Files.copyTree(actualSource, to: game, cancellation: cancellation, skipped: &skipped)
        if setup { try FileManager.default.removeItem(at: actualSource) }
        try Files.makeDirectory(game.appendingPathComponent("saves"))
        if let saves = saves
        {
            progress("Importing the selected saves…")
            try Files.requireRealDirectory(saves)
            // Keep both sets without overwriting same-named saves already present in the game source.
            let destination = game.appendingPathComponent("saves/Imported-" + UUID().uuidString)
            try Files.copyTree(saves, to: destination, cancellation: cancellation, skipped: &skipped)
        }
        progress("Checking the imported files…")
        let hashes = try GameSource.validate(game, cancellation: cancellation)
        let receipt = GameManifest(schema: 1, installedAt: Date(), runtimeID: runtime.descriptor.id,
            executableHashes: hashes, recognizedLegacyBuild: hashes == GameSource.legacyHashes,
            skippedLinks: skipped, sourceKind: setup ? "gog-windows-installer" : "game-directory")
        try Files.writeJSON(receipt, to: stage.appendingPathComponent("manifest.json"))
        let initialOptions = ((try? Files.readJSON(PlayOptions.self, from: layout.root.appendingPathComponent("preferences.json")))
            ?? PlayOptions().readingGameSettings(game, includeCompatibility: false))
        try GameConfiguration.apply(initialOptions, gameDirectory: game)
        try Files.writeJSON(initialOptions, to: stage.appendingPathComponent("options.json"))
        try cancellation.check()
        runtime.stop(prefix: prefix, log: log)
        try commit(stage: stage)
        progress("Ready")
    }

    public func play(_ game: Game, options: PlayOptions, cancellation: Cancellation, progress: @escaping ProgressHandler) throws
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        try recoverInterruptedCommit()
        guard let manifest = manifest, manifest.schema == 1,
              manifest.runtimeID == RuntimeDescriptor.pinned.id,
              let runtime = RuntimeInstaller.installed(layout: layout) else
        {
            throw CentauriError.message("The installation or runtime is incomplete. See the troubleshooting guide before changing your game files.")
        }
        try options.validate()
        try checkRuntime(runtime, cancellation: cancellation)
        let directory = layout.installation.appendingPathComponent("game")
        try Files.requireRealDirectory(directory)
        let executable = directory.appendingPathComponent(game.rawValue)
        guard Files.isRegular(executable), try Files.sha256(executable, cancellation: cancellation) == manifest.executableHashes[game.rawValue] else
        {
            throw CentauriError.message("The game executable changed after import. This version supports the imported binaries only; restore your original executable before playing.")
        }
        try GameConfiguration.apply(options, gameDirectory: directory)
        try Files.writeJSON(options, to: layout.installation.appendingPathComponent("options.json"))
        let prefix = layout.installation.appendingPathComponent("prefix")
        try Files.requireRealDirectory(prefix)
        let log = freshLog("game.log")
        defer { runtime.stop(prefix: prefix, log: log) }
        var bridge: MovieBridge?
        var program = game.rawValue
        if let tools = MovieTools.discover(), manifest.recognizedLegacyBuild
        {
            program = "centauri-" + game.rawValue
            try MoviePatch.executable(original: executable, game: game, destination: directory.appendingPathComponent(program))
            let hook = directory.appendingPathComponent("centauri_movies.dll")
            if FileManager.default.fileExists(atPath: hook.path) || Files.isLink(hook)
            {
                try FileManager.default.removeItem(at: hook)
            }
            try FileManager.default.copyItem(at: tools.hook, to: hook)
            bridge = try MovieBridge(game: directory, cache: layout.installation.appendingPathComponent("MovieCache"),
                tools: tools, log: layout.logs.appendingPathComponent("movies.log"), token: cancellation,
                enabled: options.moviesEnabled, volume: options.movieVolume * options.masterVolume / 127, progress: progress)
        }
        else if !options.skipIntro && options.moviesEnabled
        {
            throw CentauriError.message("Native movie support is unavailable for this build or game version. Turn off Opening movie in the launcher.")
        }
        // A custom drive letter can be reassigned by Wine's mounted-volume discovery.
        // Resolve the executable from our explicit working directory, as in the verified prototype.
        let arguments = [program]
        var environment = runtime.environment(prefix: prefix)
        if options.windowed && bridge == nil
        {
            throw CentauriError.message("Windowed mode requires the supported GOG executables.")
        }
        environment["SMAC_WINDOWED"] = options.windowed ? "1" : "0"
        environment["SMAC_WINDOW_WIDTH"] = String(options.width)
        environment["SMAC_WINDOW_HEIGHT"] = String(options.height)
        if options.windowed
        {
            let key = "HKCU\\Software\\Wine\\AppDefaults\\\(program)\\Mac Driver"
            for (name, value) in [("Decorated", "Y"), ("AllowImmovableWindows", "N"), ("CursorClippingLocksWindows", "N")]
            {
                let result = try Commands.run(runtime.wine, ["reg", "add", key, "/v", name, "/t", "REG_SZ", "/d", value, "/f"],
                    environment: environment, log: log, cancellation: cancellation, timeout: 30)
                guard result == 0 else { throw CentauriError.message("Could not configure the game window.") }
            }
        }
        progress("Running")
        let status = try Commands.run(runtime.wine, arguments, environment: environment,
            directory: directory, log: log, cancellation: cancellation, timeout: 7 * 24 * 3600, tick: { try bridge?.tick() })
        // Retain our lock until Wine has no remaining clients for this game session.
        let output = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        if GameExit.isNormal(status, knownGame: manifest.recognizedLegacyBuild, log: output)
        {
            _ = try Commands.run(runtime.server, ["-w"], environment: runtime.environment(prefix: prefix),
                log: log, cancellation: cancellation, timeout: 7 * 24 * 3600, tick: { try bridge?.tick() })
        }
        let finalOutput = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        guard GameExit.isNormal(status, knownGame: manifest.recognizedLegacyBuild, log: finalOutput) else
        {
            throw CentauriError.message("The game stopped unexpectedly (exit code \(status)). Export diagnostics to investigate.")
        }
        progress("Ready")
    }

    public func options() -> PlayOptions
    {
        if manifest != nil
        {
            let options = (try? Files.readJSON(PlayOptions.self, from: layout.installation.appendingPathComponent("options.json"))) ?? PlayOptions()
            return options.readingGameSettings(layout.installation.appendingPathComponent("game"))
        }
        return (try? Files.readJSON(PlayOptions.self, from: layout.root.appendingPathComponent("preferences.json"))) ?? PlayOptions()
    }

    public func saveOptions(_ options: PlayOptions) throws
    {
        try options.validate()
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        if manifest != nil
        {
            try GameConfiguration.apply(options, gameDirectory: layout.installation.appendingPathComponent("game"))
            try Files.writeJSON(options, to: layout.installation.appendingPathComponent("options.json"))
        }
        else { try Files.writeJSON(options, to: layout.root.appendingPathComponent("preferences.json")) }
    }

    public func configureWine(cancellation: Cancellation, progress: ProgressHandler) throws
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        guard manifest != nil, let runtime = RuntimeInstaller.installed(layout: layout) else
        {
            throw CentauriError.message("Install the game first.")
        }
        let prefix = layout.installation.appendingPathComponent("prefix")
        let log = freshLog("wine-settings.log")
        defer { runtime.stop(prefix: prefix, log: log) }
        progress("Wine settings")
        let status = try Commands.run(runtime.wine, ["winecfg"], environment: runtime.environment(prefix: prefix),
            log: log, cancellation: cancellation, timeout: 3600)
        guard status == 0 else { throw CentauriError.message("Wine settings closed with code \(status).") }
        progress("Ready")
    }

    public func exportDiagnostics(to destination: URL) throws
    {
        let directory = destination.appendingPathComponent("SMAC-Launcher-Diagnostics-" + UUID().uuidString)
        try Files.makeDirectory(directory)
        let report = "SMAC Launcher \(BuildInfo.version)\nBuild: \(BuildInfo.revision)\nmacOS: \(ProcessInfo.processInfo.operatingSystemVersionString)\nRuntime: \(RuntimeDescriptor.pinned.id)\nInstalled: \(manifest != nil)\nKnown legacy executables: \(manifest?.recognizedLegacyBuild == true)\n"
        try report.write(to: directory.appendingPathComponent("report.txt"), atomically: true, encoding: .utf8)
        for name in ["install.log", "game.log", "runtime.log", "runtime-check.log", "movies.log"]
        {
            let input = layout.logs.appendingPathComponent(name)
            guard Files.isRegular(input) else { continue }
            let handle = try FileHandle(forReadingFrom: input)
            defer { try? handle.close() }
            let length = try handle.seekToEnd()
            try handle.seek(toOffset: length > 2_000_000 ? length - 2_000_000 : 0)
            let data = try handle.readToEnd() ?? Data()
            let text = String(decoding: data, as: UTF8.self)
                .replacingOccurrences(of: FileManager.default.homeDirectoryForCurrentUser.path, with: "~")
                .replacingOccurrences(of: layout.root.path, with: "<Centauri data>")
            try text.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
    }

    private func checkRuntime(_ runtime: WineRuntime, cancellation: Cancellation) throws
    {
        let log = freshLog("runtime-check.log")
        do
        {
            let status = try Commands.run(runtime.wine, ["--version"], environment: runtime.environment(prefix: layout.installation.appendingPathComponent("prefix")),
                log: log, cancellation: cancellation, timeout: 30)
            guard status == 0 else { throw CentauriError.message("Wine could not start (\(status)).") }
        }
        catch
        {
            try cancellation.check()
            throw CentauriError.message("Wine could not start. On Apple Silicon, install Rosetta using the Help menu, then retry. Details: \(error.localizedDescription)")
        }
    }

    private func freshLog(_ name: String) -> URL
    {
        let file = layout.logs.appendingPathComponent(name)
        if Files.isRegular(file)
        {
            let previous = layout.logs.appendingPathComponent(name + ".previous")
            try? FileManager.default.removeItem(at: previous)
            try? FileManager.default.moveItem(at: file, to: previous)
        }
        return file
    }

    // A journal makes the two renames recoverable if power fails between them.
    public func commit(stage: URL) throws
    {
        guard stage.deletingLastPathComponent().resolvingSymlinksInPath().path == layout.root.resolvingSymlinksInPath().path,
              stage.lastPathComponent.hasPrefix(".installation-") else
        {
            throw CentauriError.message("Invalid installation staging directory.")
        }
        try Files.requireRealDirectory(stage)
        let journal = layout.root.appendingPathComponent("commit.json")
        try Files.writeJSON(stage.lastPathComponent, to: journal)
        if FileManager.default.fileExists(atPath: layout.installation.path)
        {
            guard !FileManager.default.fileExists(atPath: layout.previous.path) else
            {
                throw CentauriError.message("A previous installation already exists; preserve it before replacing this installation.")
            }
            try FileManager.default.moveItem(at: layout.installation, to: layout.previous)
        }
        do { try FileManager.default.moveItem(at: stage, to: layout.installation) }
        catch
        {
            if FileManager.default.fileExists(atPath: layout.previous.path)
            {
                try? FileManager.default.moveItem(at: layout.previous, to: layout.installation)
            }
            throw error
        }
        try FileManager.default.removeItem(at: journal)
    }

    public func recoverInterruptedCommit() throws
    {
        let journal = layout.root.appendingPathComponent("commit.json")
        guard FileManager.default.fileExists(atPath: journal.path) else { return }
        // Prefer the known previous installation over an unverified staging directory after a crash.
        if !FileManager.default.fileExists(atPath: layout.installation.path),
           FileManager.default.fileExists(atPath: layout.previous.path)
        {
            try FileManager.default.moveItem(at: layout.previous, to: layout.installation)
        }
        try FileManager.default.removeItem(at: journal)
    }
}
