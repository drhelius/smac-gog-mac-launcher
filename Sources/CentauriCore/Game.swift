import Foundation

public enum Game: String, Codable, CaseIterable
{
    case alphaCentauri = "terran.exe"
    case alienCrossfire = "terranx.exe"

    public var title: String
    {
        self == .alphaCentauri ? "Alpha Centauri" : "Alien Crossfire"
    }
}

public struct GameManifest: Codable
{
    public let schema: Int
    public let installedAt: Date
    public let runtimeID: String
    public let executableHashes: [String: String]
    public let recognizedLegacyBuild: Bool
    public let skippedLinks: [String]
    public let sourceKind: String
}

public struct PlayOptions: Codable, Equatable
{
    public var windowed: Bool = false
    public var width: Int = 1024
    public var height: Int = 768
    public var skipIntro: Bool = true
    public init() {}

    public func validate() throws
    {
        guard (800...3840).contains(width), (600...2160).contains(height) else
        {
            throw CentauriError.message("Choose a resolution between 800×600 and 3840×2160.")
        }
    }
}

public enum GameSource
{
    public static let legacyHashes = [
        "terran.exe": "0a61eb3642df750c0d5e516c3e3efeb4ad5ae7e1ce3163617759449327952a01",
        "terranx.exe": "01901cbf7196b0c5d0df9540a029520f5df8fd9a6b343deef8b5663872805fcf"
    ]

    public static func discover(_ source: URL) throws -> URL
    {
        try Files.requireRealDirectory(source)
        if Files.isRegular(source.appendingPathComponent("terran.exe")) { return source }
        // Bounded traversal supports both old GOG wrapper layouts without following drive aliases.
        var pending: [(URL, Int)] = [(source, 0)]
        var visited = 0
        while !pending.isEmpty
        {
            let (directory, depth) = pending.removeFirst()
            visited += 1
            guard visited < 10_000 else { break }
            guard depth < 9 else { continue }
            let children = try FileManager.default.contentsOfDirectory(at: directory,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey], options: [.skipsHiddenFiles])
            for child in children
            {
                let values = try child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
                if values.isSymbolicLink == true || values.isDirectory != true { continue }
                if Files.isRegular(child.appendingPathComponent("terran.exe")) { return child }
                pending.append((child, depth + 1))
            }
        }
        throw CentauriError.message("No Alpha Centauri game files were found. Choose the GOG Mac app, the installed game folder, or the Windows offline setup executable.")
    }

    public static func validate(_ directory: URL, cancellation: Cancellation = Cancellation()) throws -> [String: String]
    {
        try Files.requireRealDirectory(directory)
        var hashes: [String: String] = [:]
        for game in Game.allCases
        {
            let executable = directory.appendingPathComponent(game.rawValue)
            guard Files.isRegular(executable), try isWindowsX86(executable) else
            {
                throw CentauriError.message("Missing or invalid \(game.rawValue). Both games from the GOG Planetary Pack are required.")
            }
            hashes[game.rawValue] = try Files.sha256(executable, cancellation: cancellation)
        }
        for name in ["alpha.txt", "alphax.txt", "palette.pcx"]
        {
            guard Files.isRegular(directory.appendingPathComponent(name)) else
            {
                throw CentauriError.message("The game is incomplete: \(name) is missing or is a symbolic link.")
            }
        }
        for name in ["fx", "movies"]
        {
            try Files.requireRealDirectory(directory.appendingPathComponent(name))
        }
        return hashes
    }

    public static func isWindowsX86(_ file: URL) throws -> Bool
    {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard let dos = try handle.read(upToCount: 64), dos.count == 64,
              dos[0] == 0x4d, dos[1] == 0x5a else { return false }
        let offset = UInt64(dos[60]) | UInt64(dos[61]) << 8 | UInt64(dos[62]) << 16 | UInt64(dos[63]) << 24
        guard offset >= 64, offset <= 16 * 1024 * 1024 else { return false }
        try handle.seek(toOffset: offset)
        guard let pe = try handle.read(upToCount: 26), pe.count == 26 else { return false }
        return Array(pe[0..<6]) == [0x50, 0x45, 0, 0, 0x4c, 0x01] && pe[24] == 0x0b && pe[25] == 0x01
    }
}

public enum GameConfiguration
{
    // Preserve unrelated sections/settings and the legacy Windows text encoding.
    public static func setting(_ text: String, section: String, key: String, value: String) -> String
    {
        var lines = text.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        while lines.last == "" { lines.removeLast() }
        var inSection = false
        var foundSection = false
        var insertion = lines.count
        var matches: [Int] = []
        for (index, line) in lines.enumerated()
        {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
            {
                if inSection { insertion = index }
                inSection = trimmed.lowercased() == "[\(section.lowercased())]"
                if inSection { foundSection = true; insertion = index + 1 }
            }
            else if inSection
            {
                insertion = index + 1
                let existingKey = trimmed.split(separator: "=", maxSplits: 1).first.map(String.init) ?? ""
                if existingKey.trimmingCharacters(in: .whitespaces).lowercased() == key.lowercased()
                {
                    matches.append(index)
                }
            }
        }
        if let first = matches.first
        {
            lines[first] = "\(key)=\(value)"
            for index in matches.dropFirst().reversed() { lines.remove(at: index) }
        }
        else if foundSection { lines.insert("\(key)=\(value)", at: insertion) }
        else { lines.append(contentsOf: ["[\(section)]", "\(key)=\(value)"]) }
        return lines.joined(separator: "\r\n") + "\r\n"
    }

    public static func apply(_ options: PlayOptions, gameDirectory: URL) throws
    {
        try options.validate()
        let file = gameDirectory.appendingPathComponent("Alpha Centauri.Ini")
        guard !Files.isLink(file) else { throw CentauriError.message("The game's configuration is an external link. Reimport the game to repair it.") }
        let original = FileManager.default.fileExists(atPath: file.path) ? try Data(contentsOf: file) : Data()
        guard let text = String(data: original, encoding: .isoLatin1) else
        {
            throw CentauriError.message("Cannot read the game configuration.")
        }
        let intro = setting(text, section: "Alpha Centauri", key: "DisableOpeningMovie", value: options.skipIntro ? "1" : "0")
        let display = setting(intro, section: "Alpha Centauri", key: "DirectDraw", value: "0")
        let sound3D = setting(display, section: "Alpha Centauri", key: "ds3d", value: "0")
        let eax = setting(sound3D, section: "Alpha Centauri", key: "eax", value: "0")
        let updated = setting(eax, section: "PREFERENCES", key: "ForceOldVoxelAlgorithm", value: "1")
        guard let data = updated.data(using: .isoLatin1) else { throw CentauriError.message("Cannot encode the game configuration.") }
        if !original.isEmpty
        {
            try original.write(to: gameDirectory.appendingPathComponent("Alpha Centauri.Ini.centauri-backup"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }
}
