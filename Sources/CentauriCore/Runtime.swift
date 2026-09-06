import Foundation

public struct RuntimeDescriptor: Codable, Equatable
{
    public let id: String
    public let url: URL
    public let sha256: String
    public let bundle: String
    public let librariesURL: URL
    public let librariesSHA256: String

    public static let pinned = RuntimeDescriptor(
        id: "winecx-24.0.7-7-libs-11.0_1",
        url: URL(string: "https://github.com/Sikarugir-App/Engines/releases/download/v1.0/WS12WineCX24.0.7_7.tar.xz")!,
        sha256: "203f9e9fd6c2cc77e6525d798a434ced326145db34a356355e05659d3445fd1c",
        bundle: "wswine.bundle",
        librariesURL: URL(string: "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.0_1/wine-stable-11.0_1-osx64.tar.xz")!,
        librariesSHA256: "b50dc50ec7f41d58b115a6b685d4d1315ba3c797bd3aa0f49213f2703cb82388")
}

public struct WineRuntime
{
    public let directory: URL
    public let descriptor: RuntimeDescriptor
    public var bin: URL { directory.appendingPathComponent(descriptor.bundle + "/bin") }
    public var wine: URL { bin.appendingPathComponent("wine") }
    public var server: URL { bin.appendingPathComponent("wineserver") }

    public func environment(prefix: URL) -> [String: String]
    {
        // Do not inherit WINEPREFIX, WINEARCH, DLL overrides, or DYLD injection from another installation.
        var env = [
            "HOME": FileManager.default.homeDirectoryForCurrentUser.path,
            "TMPDIR": NSTemporaryDirectory(),
            "PATH": bin.path + ":/usr/bin:/bin:/usr/sbin:/sbin",
            "LANG": "en_US.UTF-8",
            "WINEPREFIX": prefix.path,
            "WINEDEBUG": "-all,err+all",
            // WineCX's dlopen calls use bare library names; use only our verified dependency directory.
            "DYLD_FALLBACK_LIBRARY_PATH": directory.path + ":/usr/lib",
            "MVK_CONFIG_LOG_LEVEL": "0"
        ]
        if let user = ProcessInfo.processInfo.environment["USER"] { env["USER"] = user }
        return env
    }

    public func stop(prefix: URL, log: URL)
    {
        // wineserver -k only addresses the server belonging to this exact prefix.
        _ = try? Commands.run(server, ["-k"], environment: environment(prefix: prefix), log: log, timeout: 10)
        _ = try? Commands.run(server, ["-w"], environment: environment(prefix: prefix), log: log, timeout: 10)
    }

    public func initialize(prefix: URL, log: URL, cancellation: Cancellation) throws
    {
        try Files.makeDirectory(prefix)
        do
        {
            let status = try Commands.run(wine, ["wineboot", "-u"], environment: environment(prefix: prefix),
                                          log: log, cancellation: cancellation, timeout: 240)
            guard status == 0 else { throw CentauriError.message("Windows environment setup failed (\(status)). Export diagnostics for details.") }
        }
        catch
        {
            stop(prefix: prefix, log: log)
            throw error
        }
        stop(prefix: prefix, log: log)
        // Avoid exposing unrelated home folders through Wine's default user directory links.
        let users = prefix.appendingPathComponent("drive_c/users")
        if let enumerator = FileManager.default.enumerator(at: users, includingPropertiesForKeys: [.isSymbolicLinkKey])
        {
            for case let item as URL in enumerator
            {
                if Files.isLink(item)
                {
                    enumerator.skipDescendants()
                    try FileManager.default.removeItem(at: item)
                    try Files.makeDirectory(item)
                }
            }
        }
    }
}

public enum RuntimeInstaller
{
    public static func installed(layout: Layout) -> WineRuntime?
    {
        let descriptor = RuntimeDescriptor.pinned
        let directory = layout.runtimes.appendingPathComponent(descriptor.id)
        guard !Files.isLink(directory),
              let receipt = try? Files.readJSON(RuntimeDescriptor.self, from: directory.appendingPathComponent("receipt.json")),
              receipt == descriptor else { return nil }
        let runtime = WineRuntime(directory: directory, descriptor: descriptor)
        guard Files.isRegular(runtime.wine), Files.isRegular(runtime.server),
              FileManager.default.isExecutableFile(atPath: runtime.wine.path),
              Files.isRegular(directory.appendingPathComponent("libinotify.0.dylib")),
              Files.isRegular(directory.appendingPathComponent("libfreetype.6.dylib")) else { return nil }
        return runtime
    }

    public static func ensure(layout: Layout, archive: URL? = nil, librariesArchive: URL? = nil, cancellation: Cancellation,
                              progress: ProgressHandler) throws -> WineRuntime
    {
        if let runtime = installed(layout: layout) { return runtime }
        let descriptor = RuntimeDescriptor.pinned
        try Files.requireSpace(at: layout.root, bytes: 2_000_000_000)
        let staging = layout.runtimes.appendingPathComponent(".staging-" + UUID().uuidString)
        try Files.makeDirectory(staging)
        defer { try? FileManager.default.removeItem(at: staging) }
        let input = staging.appendingPathComponent("runtime.tar.xz")
        if let archive = archive
        {
            guard Files.isRegular(archive) else { throw CentauriError.message("Select a regular runtime archive file.") }
            progress("Copying the runtime archive…")
            try FileManager.default.copyItem(at: archive, to: input)
        }
        else
        {
            progress("Downloading the Mac compatibility runtime (about 165 MB)…")
            try download(descriptor.url, to: input, cancellation: cancellation)
        }
        progress("Verifying the runtime download…")
        guard try Files.sha256(input, cancellation: cancellation) == descriptor.sha256 else
        {
            throw CentauriError.message("The runtime checksum does not match. Nothing was installed. Please retry the download.")
        }
        try cancellation.check()
        let log = layout.logs.appendingPathComponent("runtime.log")
        let contents = staging.appendingPathComponent("archive-list.txt")
        guard try Commands.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-tf", input.path],
                               log: contents, cancellation: cancellation) == 0 else
        {
            throw CentauriError.message("Cannot read the runtime archive.")
        }
        for entry in try String(contentsOf: contents, encoding: .utf8).split(separator: "\n")
        {
            try validateArchiveEntry(String(entry), bundle: descriptor.bundle)
        }
        let unpacked = staging.appendingPathComponent("unpacked")
        try Files.makeDirectory(unpacked)
        progress("Preparing Wine…")
        guard try Commands.run(URL(fileURLWithPath: "/usr/bin/tar"),
                               ["-xf", input.path, "-C", unpacked.path, "--no-same-owner"],
                               log: log, cancellation: cancellation) == 0 else
        {
            throw CentauriError.message("Cannot unpack the runtime.")
        }
        let runtime = WineRuntime(directory: unpacked, descriptor: descriptor)
        guard Files.isRegular(runtime.wine), Files.isRegular(runtime.server) else
        {
            throw CentauriError.message("The runtime archive is missing its executables.")
        }
        let libraries = staging.appendingPathComponent("libraries.tar.xz")
        if let librariesArchive = librariesArchive
        {
            guard Files.isRegular(librariesArchive) else { throw CentauriError.message("Select a regular library archive file.") }
            try FileManager.default.copyItem(at: librariesArchive, to: libraries)
        }
        else
        {
            progress("Downloading the runtime libraries (about 177 MB)…")
            try download(descriptor.librariesURL, to: libraries, cancellation: cancellation)
        }
        guard try Files.sha256(libraries, cancellation: cancellation) == descriptor.librariesSHA256 else
        {
            throw CentauriError.message("The library archive checksum does not match. Nothing was installed.")
        }
        let libraryStage = staging.appendingPathComponent("libraries")
        try Files.makeDirectory(libraryStage)
        // Extract only the top-level dylibs, never the unrelated upstream Wine binary or launcher.
        let listing = staging.appendingPathComponent("libraries-list.txt")
        guard try Commands.run(URL(fileURLWithPath: "/usr/bin/tar"), ["-tf", libraries.path],
            log: listing, cancellation: cancellation) == 0 else { throw CentauriError.message("Cannot read the library archive.") }
        let libraryRoot = "Wine Stable.app/Contents/Resources/wine/lib/"
        let entries = try String(contentsOf: listing, encoding: .utf8).split(separator: "\n").map(String.init)
        for entry in entries { try validateArchiveEntry(entry, bundle: "Wine Stable.app") }
        let selected = entries.filter
        {
            $0.hasPrefix(libraryRoot) && $0.hasSuffix(".dylib") && !$0.dropFirst(libraryRoot.count).contains("/")
        }
        guard !selected.isEmpty else { throw CentauriError.message("No runtime libraries found in the verified archive.") }
        guard try Commands.run(URL(fileURLWithPath: "/usr/bin/tar"),
            ["-xf", libraries.path, "-C", libraryStage.path, "--no-same-owner"] + selected,
            log: log, cancellation: cancellation) == 0 else { throw CentauriError.message("Cannot unpack the runtime libraries.") }
        for entry in selected
        {
            try cancellation.check()
            let file = libraryStage.appendingPathComponent(entry)
            try FileManager.default.copyItem(at: file, to: unpacked.appendingPathComponent(file.lastPathComponent))
        }
        try Files.writeJSON(descriptor, to: unpacked.appendingPathComponent("receipt.json"))
        try cancellation.check()
        let final = layout.runtimes.appendingPathComponent(descriptor.id)
        // A malformed existing runtime is preserved for inspection, never used or overwritten silently.
        if FileManager.default.fileExists(atPath: final.path) || Files.isLink(final)
        {
            try FileManager.default.moveItem(at: final,
                to: layout.runtimes.appendingPathComponent("unusable-" + UUID().uuidString))
        }
        try FileManager.default.moveItem(at: unpacked, to: final)
        return WineRuntime(directory: final, descriptor: descriptor)
    }

    public static func validateArchiveEntry(_ entry: String, bundle: String) throws
    {
        let parts = entry.split(separator: "/", omittingEmptySubsequences: false)
        guard !entry.hasPrefix("/"), parts.first == Substring(bundle), !parts.contains("..") else
        {
            throw CentauriError.message("Unsafe path in the runtime archive.")
        }
    }

    private static func download(_ source: URL, to destination: URL, cancellation: Cancellation) throws
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 900
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let result = DownloadResult()
        let task = session.downloadTask(with: source)
        { temporary, response, error in
            do
            {
                if let error = error { throw error }
                guard let http = response as? HTTPURLResponse, http.statusCode == 200,
                      http.url?.scheme == "https", let temporary = temporary else
                {
                    throw CentauriError.message("The runtime download failed. Check your internet connection and retry.")
                }
                try FileManager.default.moveItem(at: temporary, to: destination)
                result.finish(nil)
            }
            catch { result.finish(error) }
        }
        task.resume()
        while result.completed.wait(timeout: .now() + 0.1) == .timedOut
        {
            if cancellation.isCancelled || task.countOfBytesReceived > 512_000_000
            {
                task.cancel()
                result.completed.wait()
                try cancellation.check()
                throw CentauriError.message("The runtime download is unexpectedly large.")
            }
        }
        try cancellation.check()
        if let error = result.error { throw error }
    }
}

private final class DownloadResult: @unchecked Sendable
{
    let completed = DispatchSemaphore(value: 0)
    private(set) var error: Error?

    func finish(_ error: Error?)
    {
        self.error = error
        completed.signal()
    }
}
