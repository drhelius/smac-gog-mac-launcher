import Foundation

public enum LaunchIntegration: String, Codable, CaseIterable
{
    case automatic, native, pracx, thinker, custom

    public var title: String
    {
        switch self
        {
        case .automatic: return "Automatic"
        case .native: return "Original game"
        case .pracx: return "PRACX"
        case .thinker: return "Thinker"
        case .custom: return "Custom executable"
        }
    }
}

public struct LaunchProfile: Codable, Equatable
{
    public var id: String
    public var name: String
    public var game: Game
    public var executable: String
    public var arguments: String
    public var integration: LaunchIntegration
    public var workingDirectory: String?

    public init(id: String = UUID().uuidString, name: String, game: Game,
                executable: String = "", arguments: String = "", integration: LaunchIntegration = .automatic,
                workingDirectory: String = "")
    {
        self.id = id
        self.name = name
        self.game = game
        self.executable = executable
        self.arguments = arguments
        self.integration = integration
        self.workingDirectory = workingDirectory
    }

    public func validate() throws
    {
        guard UUID(uuidString: id) != nil, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name.count <= 80 else { throw CentauriError.message("Enter a configuration name of up to 80 characters.") }
        if !executable.isEmpty { try LaunchPlan.validatePath(executable) }
        try LaunchPlan.validateDirectory(workingDirectory ?? "")
        _ = try LaunchPlan.arguments(arguments)
        if integration == .thinker && game != .alienCrossfire
        {
            throw CentauriError.message("Thinker configurations use Alien Crossfire. Its -smac option can select SMAC-in-SMACX.")
        }
    }
}

public struct LaunchPlan
{
    public let executable: URL
    public let workingDirectory: URL
    public let arguments: [String]
    public let integration: LaunchIntegration
    public let knownGame: Bool
    public let usesPRACX: Bool
    public var nativeMovies: Bool { integration == .native || integration == .pracx || integration == .thinker }
    public var managesDisplay: Bool { integration == .native || (integration == .thinker && !usesPRACX) }
    public var managesSettings: Bool { integration != .custom }

    public static func validatePath(_ path: String) throws
    {
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty, !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"),
              !path.contains("\0"), path.lowercased().hasSuffix(".exe"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else
        {
            throw CentauriError.message("Choose a Windows executable inside this configuration's game folder.")
        }
    }

    public static func validateDirectory(_ path: String) throws
    {
        if path.isEmpty || path == "." { return }
        let parts = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.hasPrefix("/"), !path.contains("\\"), !path.contains(":"), !path.contains("\0"),
              parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else
        {
            throw CentauriError.message("Choose a working folder inside this configuration's game folder.")
        }
    }

    public static func directory(in root: URL, relative: String) throws -> URL
    {
        try validateDirectory(relative)
        try Files.requireRealDirectory(root)
        if relative.isEmpty || relative == "." { return root }
        var directory = root
        for part in relative.split(separator: "/")
        {
            directory.appendPathComponent(String(part), isDirectory: true)
            try Files.requireRealDirectory(directory)
        }
        return directory
    }

    // Arguments are passed directly to Wine, never evaluated by a shell.
    public static func arguments(_ text: String) throws -> [String]
    {
        guard text.utf8.count <= 8192, !text.contains("\0"), !text.contains("\n"), !text.contains("\r") else
        {
            throw CentauriError.message("The launch arguments are too long or contain invalid characters.")
        }
        var result: [String] = []
        var word = ""
        var quote: Character?
        var started = false
        for character in text
        {
            if let delimiter = quote
            {
                if character == delimiter { quote = nil }
                else { word.append(character) }
            }
            else if character == "\"" || character == "'" { quote = character; started = true }
            else if character.isWhitespace
            {
                if started { result.append(word); word = ""; started = false }
            }
            else { word.append(character); started = true }
        }
        guard quote == nil else { throw CentauriError.message("Close the quote in the launch arguments.") }
        if started { result.append(word) }
        return result
    }

    public static func executables(in directory: URL) -> [String]
    {
        guard let files = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return [] }
        return files.filter
        {
            Files.isRegular($0) && $0.pathExtension.lowercased() == "exe" &&
            !$0.lastPathComponent.lowercased().hasPrefix("centauri-")
        }.map(\.lastPathComponent).sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    public static func resolve(directory: URL, game: Game, profile: LaunchProfile? = nil) throws -> LaunchPlan
    {
        let name = profile?.executable.isEmpty == false ? profile!.executable : game.rawValue
        try validatePath(name)
        try Files.requireRealDirectory(directory)
        let working = try Self.directory(in: directory, relative: profile?.workingDirectory ?? "")
        var file = directory
        let parts = name.split(separator: "/")
        for (index, part) in parts.enumerated()
        {
            file.appendPathComponent(String(part))
            if index < parts.count - 1 { try Files.requireRealDirectory(file) }
        }
        guard Files.isRegular(file), try GameSource.isWindowsExecutable(file) else
        {
            throw CentauriError.message("Select an installed Windows executable for this configuration.")
        }
        let known = try Files.sha256(file) == GameSource.legacyHashes[game.rawValue]
        var integration = profile?.integration ?? .automatic
        if integration == .automatic
        {
            if file.lastPathComponent.lowercased() == "thinker.exe" { integration = .thinker }
            else if try hasPRACXLoader(file) { integration = .pracx }
            else { integration = known ? .native : .custom }
        }
        if integration == .native && !known
        {
            throw CentauriError.message("This executable does not support the original-game hooks. Select Automatic or the mod's integration.")
        }
        if integration == .thinker && game != .alienCrossfire
        {
            throw CentauriError.message("Select Alien Crossfire for a Thinker configuration.")
        }
        var pracx = integration == .pracx
        if integration == .thinker { pracx = try hasPRACXLoader(working.appendingPathComponent(Game.alienCrossfire.rawValue)) }
        return LaunchPlan(executable: file, workingDirectory: working, arguments: try arguments(profile?.arguments ?? ""),
                          integration: integration, knownGame: known, usesPRACX: pracx)
    }

    public static func hasPRACXLoader(_ executable: URL) throws -> Bool
    {
        let file = try FileHandle(forReadingFrom: executable)
        defer { try? file.close() }
        let data = try file.read(upToCount: 16 * 1024 * 1024) ?? Data()
        // PRACX's open-source loader: call over "prac/prax\0", then call LoadLibraryA.
        for name in ["prac", "prax"]
        {
            for call: [UInt8] in [[0xff, 0x15], [0x3e, 0xff, 0x15]]
            {
                let signature = Data([0xe8, 5, 0, 0, 0]) + Data(name.utf8) + Data([0]) + Data(call)
                if data.range(of: signature) != nil { return true }
            }
        }
        return false
    }
}
