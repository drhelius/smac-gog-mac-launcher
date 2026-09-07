import Foundation
import CryptoKit
import Darwin

public enum CentauriError: LocalizedError
{
    case message(String)
    case cancelled

    public var errorDescription: String?
    {
        switch self
        {
        case .message(let text): return text
        case .cancelled: return "Cancelled. Your existing installation has been preserved."
        }
    }
}

public final class Cancellation
{
    private let lock = NSLock()
    private var value = false

    public init() {}

    public var isCancelled: Bool
    {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    public func cancel()
    {
        lock.lock()
        value = true
        lock.unlock()
    }

    public func check() throws
    {
        if isCancelled { throw CentauriError.cancelled }
    }
}

public typealias ProgressHandler = (String) -> Void

public struct Layout
{
    public let root: URL
    public var runtimes: URL { root.appendingPathComponent("Runtimes", isDirectory: true) }
    public var installation: URL { root.appendingPathComponent("Installation", isDirectory: true) }
    public var previous: URL { root.appendingPathComponent("Previous Installation", isDirectory: true) }
    public var logs: URL { root.appendingPathComponent("Logs", isDirectory: true) }
    public var saves: URL { installation.appendingPathComponent("game/saves", isDirectory: true) }

    public init(root: URL? = nil)
    {
        self.root = (root ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/DrHelius/Centauri", isDirectory: true))
            .standardizedFileURL
    }

    public func prepare() throws
    {
        for path in [root, runtimes, logs]
        {
            try Files.makeDirectory(path)
            try Files.requireRealDirectory(path)
        }
    }
}

public enum Files
{
    public static func makeDirectory(_ url: URL) throws
    {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    public static func isLink(_ url: URL) -> Bool
    {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) == true
    }

    public static func requireRealDirectory(_ url: URL) throws
    {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else
        {
            throw CentauriError.message("Expected a real directory: \(url.lastPathComponent)")
        }
    }

    public static func isRegular(_ url: URL) -> Bool
    {
        guard let v = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey]) else { return false }
        return v.isRegularFile == true && v.isSymbolicLink != true
    }

    public static func sha256(_ url: URL, cancellation: Cancellation = Cancellation()) throws -> String
    {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 1024 * 1024), !bytes.isEmpty
        {
            try cancellation.check()
            hash.update(data: bytes)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    public static func writeJSON<T: Encodable>(_ value: T, to url: URL) throws
    {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    public static func readJSON<T: Decodable>(_ type: T.Type, from url: URL) throws -> T
    {
        try JSONDecoder().decode(type, from: Data(contentsOf: url))
    }

    public static func requireSpace(at url: URL, bytes: Int64) throws
    {
        let values = try FileManager.default.attributesOfFileSystem(forPath: url.path)
        if let available = values[.systemFreeSize] as? NSNumber, available.int64Value < bytes
        {
            throw CentauriError.message("Not enough free space. This operation needs at least \((bytes + 999_999_999) / 1_000_000_000) GB free.")
        }
    }

    // Never traverse source symlinks, including directory links and dangling links.
    public static func copyTree(_ source: URL, to destination: URL, cancellation: Cancellation,
                                skipped: inout [String], relative: String = "") throws
    {
        try requireRealDirectory(source)
        let sourcePath = source.resolvingSymlinksInPath().path
        let destinationPath = destination.resolvingSymlinksInPath().path
        guard destinationPath != sourcePath, !destinationPath.hasPrefix(sourcePath + "/") else
        {
            throw CentauriError.message("The destination cannot be inside the source folder.")
        }
        try makeDirectory(destination)
        for child in try FileManager.default.contentsOfDirectory(at: source,
                    includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
        {
            try cancellation.check()
            let name = relative + child.lastPathComponent
            let values = try child.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey, .isRegularFileKey])
            if values.isSymbolicLink == true
            {
                skipped.append(name)
                continue
            }
            let target = destination.appendingPathComponent(child.lastPathComponent)
            if values.isDirectory == true
            {
                try copyTree(child, to: target, cancellation: cancellation, skipped: &skipped, relative: name + "/")
            }
            else if values.isRegularFile == true
            {
                try FileManager.default.copyItem(at: child, to: target)
            }
        }
    }
}

// Kernel-owned lock: crashes do not leave stale lock files that block future launches.
public final class InstallationLock
{
    private let descriptor: Int32

    public init(root: URL) throws
    {
        descriptor = Darwin.open(root.appendingPathComponent("operation.lock").path,
                                 O_CREAT | O_RDWR | O_NOFOLLOW | O_CLOEXEC, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw CentauriError.message("Cannot open the installation lock.") }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else
        {
            Darwin.close(descriptor)
            throw CentauriError.message("Another launcher session is active. Close it first.")
        }
    }

    deinit
    {
        flock(descriptor, LOCK_UN)
        Darwin.close(descriptor)
    }
}

public enum Commands
{
    // Arguments never pass through a shell. Logs are files, avoiding pipe-buffer deadlocks.
    @discardableResult
    public static func run(_ executable: URL, _ arguments: [String], environment: [String: String]? = nil,
                           directory: URL? = nil, log: URL, cancellation: Cancellation = Cancellation(),
                           timeout: TimeInterval = 180, tick: (() throws -> Void)? = nil) throws -> Int32
    {
        try cancellation.check()
        try Files.makeDirectory(log.deletingLastPathComponent())
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let output = try FileHandle(forWritingTo: log)
        defer { try? output.close() }
        try output.seekToEnd()
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = directory
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let deadline = Date().addingTimeInterval(timeout)
        while process.isRunning
        {
            do { try tick?() }
            catch
            {
                if process.isRunning { process.terminate() }
                throw error
            }
            // Child stdout/stderr share this file offset. Bound even a repeated runtime fault loop.
            if (try? output.offset()) ?? 0 > 8_000_000
            {
                try output.truncate(atOffset: 0)
                try output.seek(toOffset: 0)
                try output.write(contentsOf: Data("[Earlier log output trimmed after 8 MB]\n".utf8))
            }
            if cancellation.isCancelled || Date() > deadline
            {
                process.terminate()
                let stopDeadline = Date().addingTimeInterval(2)
                while process.isRunning && Date() < stopDeadline { Thread.sleep(forTimeInterval: 0.05) }
                if process.isRunning { kill(process.processIdentifier, SIGKILL) }
                process.waitUntilExit()
                try cancellation.check()
                throw CentauriError.message("The operation timed out. See the diagnostic log for details.")
            }
            Thread.sleep(forTimeInterval: 0.1)
        }
        process.waitUntilExit()
        try cancellation.check()
        return process.terminationReason == .uncaughtSignal ? 128 + process.terminationStatus : process.terminationStatus
    }
}
