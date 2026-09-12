import Foundation

extension CentauriService
{
    public var modsDirectory: URL { layout.root.appendingPathComponent("Mods", isDirectory: true) }

    public func profileDirectory(_ profile: LaunchProfile) throws -> URL
    {
        try profile.validate()
        try Files.requireRealDirectory(modsDirectory)
        let directory = modsDirectory.appendingPathComponent(profile.id, isDirectory: true)
        try Files.requireRealDirectory(directory)
        return directory
    }

    public func gameDirectory(profile: LaunchProfile? = nil) throws -> URL
    {
        let root = try profile.map { try profileDirectory($0) } ?? layout.installation
        let game = root.appendingPathComponent("game", isDirectory: true)
        try Files.requireRealDirectory(game)
        return game
    }

    func recoverProfileGame(_ profile: LaunchProfile) throws
    {
        // Called only while holding the installation lock.
        let root = try profileDirectory(profile)
        let game = root.appendingPathComponent("game", isDirectory: true)
        let previous = root.appendingPathComponent("previous-game", isDirectory: true)
        if !FileManager.default.fileExists(atPath: game.path), Files.isDirectory(previous)
        {
            try FileManager.default.moveItem(at: previous, to: game)
        }
    }

    public func profiles() -> [LaunchProfile]
    {
        guard !Files.isLink(modsDirectory), let directories = try? FileManager.default.contentsOfDirectory(
            at: modsDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return [] }
        return directories.compactMap
        { directory in
            guard !Files.isLink(directory),
                  let profile = try? Files.readJSON(LaunchProfile.self, from: directory.appendingPathComponent("profile.json")),
                  profile.id == directory.lastPathComponent, (try? profile.validate()) != nil else { return nil }
            return profile
        }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    public func saveProfile(_ profile: LaunchProfile) throws
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        let directory = try profileDirectory(profile)
        if let old = try? Files.readJSON(LaunchProfile.self, from: directory.appendingPathComponent("profile.json")),
           let working = try? LaunchPlan.directory(in: directory.appendingPathComponent("game"), relative: old.workingDirectory ?? "")
        {
            try ModConfiguration.restoreMovies(in: working, receipt: directory.appendingPathComponent("movie-settings.json"))
        }
        try Files.writeJSON(profile, to: directory.appendingPathComponent("profile.json"))
    }

    public func removeProfile(_ profile: LaunchProfile) throws
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        let directory = try profileDirectory(profile)
        try FileManager.default.trashItem(at: directory, resultingItemURL: nil)
    }

    public func createProfile(name: String, game: Game, cancellation: Cancellation,
                              progress: ProgressHandler) throws -> LaunchProfile
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        guard manifest != nil else { throw CentauriError.message("Install your GOG game first.") }
        let profile = LaunchProfile(name: name, game: game)
        try profile.validate()
        try Files.makeDirectory(modsDirectory)
        try Files.requireRealDirectory(modsDirectory)
        try Files.requireSpace(at: modsDirectory, bytes: 4_000_000_000)
        let staging = modsDirectory.appendingPathComponent(".staging-" + profile.id)
        try Files.makeDirectory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        progress("Copying the game for \(name)…")
        var skipped: [String] = []
        let destination = staging.appendingPathComponent("game")
        let original = try gameDirectory()
        try ModConfiguration.restoreMovies(in: original, receipt: layout.installation.appendingPathComponent("movie-settings.json"))
        try Files.copyTree(original, to: destination, cancellation: cancellation, skipped: &skipped)
        try ModFiles.removeGeneratedFiles(destination)
        try Files.writeJSON(profile, to: staging.appendingPathComponent("profile.json"))
        try Files.writeJSON(options(), to: staging.appendingPathComponent("options.json"))
        try cancellation.check()
        try FileManager.default.moveItem(at: staging, to: modsDirectory.appendingPathComponent(profile.id))
        return profile
    }

    public func addModFiles(_ source: URL, profile: LaunchProfile, cancellation: Cancellation,
                            progress: ProgressHandler) throws
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        let root = try profileDirectory(profile)
        try recoverProfileGame(profile)
        let game = try gameDirectory(profile: profile)
        let receipt = root.appendingPathComponent("movie-settings.json")
        if Files.isRegular(receipt)
        {
            let working = try LaunchPlan.directory(in: game, relative: profile.workingDirectory ?? "")
            try ModConfiguration.restoreMovies(in: working, receipt: receipt)
        }
        try Files.requireRealDirectory(source)
        let input = source.resolvingSymlinksInPath().path
        let output = root.resolvingSymlinksInPath().path
        guard input != output, !input.hasPrefix(output + "/"), !output.hasPrefix(input + "/") else
        {
            throw CentauriError.message("Choose an extracted mod folder outside this configuration.")
        }
        try Files.requireSpace(at: root, bytes: 4_000_000_000)
        let staging = root.appendingPathComponent(".mod-files-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: staging) }
        var skipped: [String] = []
        progress("Preparing mod files…")
        try Files.copyTree(game, to: staging, cancellation: cancellation, skipped: &skipped)
        try ModFiles.overlay(source, onto: staging, cancellation: cancellation)
        try cancellation.check()
        let previous = root.appendingPathComponent("previous-game")
        if FileManager.default.fileExists(atPath: previous.path) { try FileManager.default.removeItem(at: previous) }
        try FileManager.default.moveItem(at: game, to: previous)
        do { try FileManager.default.moveItem(at: staging, to: game) }
        catch { try? FileManager.default.moveItem(at: previous, to: game); throw error }
        try? FileManager.default.removeItem(at: previous)
    }

    func prepareModPrefix(_ profile: LaunchProfile, runtime: WineRuntime,
                                 cancellation: Cancellation, log: URL) throws -> URL
    {
        let root = try profileDirectory(profile)
        try recoverProfileGame(profile)
        let prefix = root.appendingPathComponent("prefix")
        if !Files.isRegular(prefix.appendingPathComponent("system.reg"))
        {
            try runtime.initialize(prefix: prefix, log: log, cancellation: cancellation)
        }
        try Files.requireRealDirectory(prefix)
        let drive = prefix.appendingPathComponent("drive_c")
        try Files.requireRealDirectory(drive)
        let link = drive.appendingPathComponent("SMAC")
        let game = try gameDirectory(profile: profile)
        if Files.isLink(link)
        {
            guard link.resolvingSymlinksInPath().path == game.resolvingSymlinksInPath().path else
            {
                throw CentauriError.message("The configuration's C:\\SMAC mapping was changed.")
            }
        }
        else if FileManager.default.fileExists(atPath: link.path)
        {
            throw CentauriError.message("C:\\SMAC is already occupied in this configuration.")
        }
        else { try FileManager.default.createSymbolicLink(at: link, withDestinationURL: game) }
        // PRACX's installer discovers its destination through the game's DirectPlay registration.
        let key = "HKLM\\Software\\Microsoft\\DirectPlay\\Applications\\Sid Meier's Alpha Centauri"
        for view in ["32", "64"]
        {
            let status = try Commands.run(runtime.wine, ["reg", "add", key, "/v", "UnofficialPath", "/t", "REG_SZ", "/d", "C:\\SMAC", "/f", "/reg:" + view],
                environment: runtime.environment(prefix: prefix), log: log, cancellation: cancellation, timeout: 30)
            guard status == 0 else { throw CentauriError.message("Could not configure the mod installation folder.") }
        }
        return prefix
    }

    public func installMod(_ installer: URL, profile: LaunchProfile, arguments: String = "",
                           cancellation: Cancellation, progress: ProgressHandler) throws
    {
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        guard Files.isRegular(installer), try GameSource.isWindowsExecutable(installer),
              let runtime = RuntimeInstaller.installed(layout: layout) else
        {
            throw CentauriError.message("Choose a Windows mod installer after installing the GOG game.")
        }
        let log = layout.logs.appendingPathComponent("mod-installer.log")
        let prefix = try prepareModPrefix(profile, runtime: runtime, cancellation: cancellation, log: log)
        defer { runtime.stop(prefix: prefix, log: log) }
        progress("Install the mod into C:\\SMAC")
        let status = try Commands.run(runtime.wine, [installer.path] + LaunchPlan.arguments(arguments),
            environment: runtime.environment(prefix: prefix), directory: try gameDirectory(profile: profile),
            log: log, cancellation: cancellation, timeout: 3600)
        guard status == 0 else { throw CentauriError.message("The mod installer exited with code \(status).") }
        _ = try Commands.run(runtime.server, ["-w"], environment: runtime.environment(prefix: prefix),
            log: log, cancellation: cancellation, timeout: 3600)
    }

    public func options(profile: LaunchProfile?) -> PlayOptions
    {
        guard let profile = profile, let root = try? profileDirectory(profile) else { return options() }
        let saved = (try? Files.readJSON(PlayOptions.self, from: root.appendingPathComponent("options.json"))) ?? PlayOptions()
        let working = (try? LaunchPlan.directory(in: root.appendingPathComponent("game"), relative: profile.workingDirectory ?? ""))
            ?? root.appendingPathComponent("game")
        return saved.readingGameSettings(working)
    }

    public func saveOptions(_ options: PlayOptions, profile: LaunchProfile?) throws
    {
        guard let profile = profile else { try saveOptions(options); return }
        try options.validate()
        try layout.prepare()
        let lock = try InstallationLock(root: layout.root)
        defer { withExtendedLifetime(lock) {} }
        let root = try profileDirectory(profile)
        try Files.writeJSON(options, to: root.appendingPathComponent("options.json"))
    }
}

public enum ModFiles
{
    public static func overlay(_ source: URL, onto destination: URL, cancellation: Cancellation) throws
    {
        try Files.requireRealDirectory(source)
        try Files.requireRealDirectory(destination)
        for file in try FileManager.default.contentsOfDirectory(at: source, includingPropertiesForKeys: nil)
        {
            try cancellation.check()
            guard !Files.isLink(file) else { throw CentauriError.message("Mod folders cannot contain symbolic links.") }
            let target = destination.appendingPathComponent(file.lastPathComponent)
            guard !Files.isLink(target) else { throw CentauriError.message("A mod target is a symbolic link.") }
            if Files.isDirectory(file)
            {
                if FileManager.default.fileExists(atPath: target.path), !Files.isDirectory(target)
                {
                    try FileManager.default.removeItem(at: target)
                }
                try Files.makeDirectory(target)
                try overlay(file, onto: target, cancellation: cancellation)
            }
            else if Files.isRegular(file)
            {
                if FileManager.default.fileExists(atPath: target.path) { try FileManager.default.removeItem(at: target) }
                try FileManager.default.copyItem(at: file, to: target)
            }
            else { throw CentauriError.message("A mod folder contains an unsupported file type.") }
        }
    }

    static func removeGeneratedFiles(_ directory: URL) throws
    {
        for name in ["centauri-terran.exe", "centauri-terranx.exe", "centauri_movies.dll",
                     "centauri-window-loader.exe", "centauri_window.dll",
                     "centauri-movie-request.exe", "centauri-movie.request", "centauri-movie.done", "centauri-movie.tmp"]
        {
            let file = directory.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: file.path) || Files.isLink(file) { try FileManager.default.removeItem(at: file) }
        }
    }
}
