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
        try windowsMachine(file) == 0x14c
    }

    public static func isWindowsExecutable(_ file: URL) throws -> Bool
    {
        try windowsMachine(file) != nil
    }

    private static func windowsMachine(_ file: URL) throws -> Int?
    {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        guard let dos = try handle.read(upToCount: 64), dos.count == 64,
              dos[0] == 0x4d, dos[1] == 0x5a else { return nil }
        let offset = UInt64(dos[60]) | UInt64(dos[61]) << 8 | UInt64(dos[62]) << 16 | UInt64(dos[63]) << 24
        guard offset >= 64, offset <= 16 * 1024 * 1024 else { return nil }
        try handle.seek(toOffset: offset)
        guard let pe = try handle.read(upToCount: 26), pe.count == 26,
              Array(pe[0..<4]) == [0x50, 0x45, 0, 0] else { return nil }
        let machine = Int(pe[4]) | Int(pe[5]) << 8
        let magic = Int(pe[24]) | Int(pe[25]) << 8
        return (machine == 0x14c && magic == 0x10b) || (machine == 0x8664 && magic == 0x20b) ? machine : nil
    }
}

public enum GameConfiguration
{
    public static func removing(_ text: String, section: String, key: String) -> String
    {
        var current = ""
        return text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n").filter
        { raw in
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("["), line.hasSuffix("]") { current = String(line.dropFirst().dropLast()) }
            guard current.caseInsensitiveCompare(section) == .orderedSame, !line.hasPrefix(";"),
                  let separator = line.firstIndex(of: "=") else { return true }
            return line[..<separator].trimmingCharacters(in: .whitespaces).caseInsensitiveCompare(key) != .orderedSame
        }.joined(separator: "\r\n")
    }

    public static func values(_ text: String) -> [String: String]
    {
        var result: [String: String] = [:]
        var section = ""
        for raw in text.components(separatedBy: .newlines)
        {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") && line.hasSuffix("]") { section = String(line.dropFirst().dropLast()).lowercased() }
            else if !line.hasPrefix(";"), let separator = line.firstIndex(of: "=")
            {
                let key = line[..<separator].trimmingCharacters(in: .whitespaces).lowercased()
                result[section + "/" + key] = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            }
        }
        return result
    }
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
        let fields: [(String, Int)] = [
            ("DisableOpeningMovie", options.skipIntro || !options.moviesEnabled ? 1 : 0),
            ("DirectDraw", options.directDraw ? 1 : 0), ("ds3d", options.positionalAudio ? 1 : 0),
            ("eax", options.eaxAudio ? 1 : 0), ("Main Volume", options.masterVolume),
            ("Music Volume", options.musicVolume), ("SFX Volume", options.effectsVolume),
            ("Voice Volume", options.voiceVolume), ("MainFontSize", options.mainFontSize),
            ("InterludeFontSize", options.interludeFontSize), ("Gamma Correction", options.gamma),
            ("FastUnitAnim", options.animation == .fast ? 1 : 0),
            ("SmoothUnitAnim", options.animation == .smooth ? 1 : 0),
            ("WindowsFileBox", options.systemFileDialogs ? 1 : 0),
            ("DontResetBeginnerPrefs", options.preserveBeginnerPreferences ? 1 : 0)
        ]
        var updated = text
        for (key, value) in fields { updated = setting(updated, section: "Alpha Centauri", key: key, value: String(value)) }
        updated = setting(updated, section: "PREFERENCES", key: "ForceOldVoxelAlgorithm", value: options.legacyVoxel ? "1" : "0")
        guard let data = updated.data(using: .isoLatin1) else { throw CentauriError.message("Cannot encode the game configuration.") }
        if !original.isEmpty
        {
            try original.write(to: gameDirectory.appendingPathComponent("Alpha Centauri.Ini.centauri-backup"), options: .atomic)
        }
        try data.write(to: file, options: .atomic)
    }
}
