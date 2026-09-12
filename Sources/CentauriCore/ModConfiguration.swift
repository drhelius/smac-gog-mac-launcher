import Foundation

// Restore only our temporary movie settings; preserve settings changed by the mod or user.
public enum ModConfiguration
{
    public static func presentationOptions(_ options: PlayOptions, desktopWidth: Int, desktopHeight: Int) -> PlayOptions
    {
        var result = options
        if !options.windowed
        {
            result.width = max(800, min(16384, desktopWidth / 8 * 8))
            result.height = max(600, min(16384, desktopHeight / 8 * 8))
        }
        // Keep Thinker away from physical mode switching; the window helper owns presentation.
        result.windowed = true
        return result
    }

    private struct Entry: Codable
    {
        let section: String
        let key: String
        let original: String?
        let applied: String
    }

    public static func restoreMovies(in directory: URL, receipt: URL) throws
    {
        guard Files.isRegular(receipt) else { return }
        let entries = try Files.readJSON([Entry].self, from: receipt)
        let file = directory.appendingPathComponent("Alpha Centauri.Ini")
        guard Files.isRegular(file) else { throw CentauriError.message("Cannot restore the mod's movie settings.") }
        var text = try String(contentsOf: file, encoding: .isoLatin1)
        for entry in entries
        {
            let value = GameConfiguration.values(text)[entry.section.lowercased() + "/" + entry.key.lowercased()]
            if value != entry.applied { continue }
            if let original = entry.original
            {
                text = GameConfiguration.setting(text, section: entry.section, key: entry.key, value: original)
            }
            else { text = GameConfiguration.removing(text, section: entry.section, key: entry.key) }
        }
        try text.data(using: .isoLatin1)!.write(to: file, options: .atomic)
        try FileManager.default.removeItem(at: receipt)
    }

    public static func applyMovies(in directory: URL, receipt: URL, integration: LaunchIntegration) throws
    {
        try restoreMovies(in: directory, receipt: receipt)
        let file = directory.appendingPathComponent("Alpha Centauri.Ini")
        guard Files.isRegular(file) else { throw CentauriError.message("The game configuration is missing.") }
        var text = try String(contentsOf: file, encoding: .isoLatin1)
        let fields: [(String, String, String)]
        switch integration
        {
        case .pracx:
            fields = [("PRACX", "MoviePlayerCommand", "centauri-movie-request.exe")]
        case .thinker:
            fields = [("Alpha Centauri", "MoviePlayerPath", "centauri-movie-request.exe"),
                      ("Alpha Centauri", "MoviePlayerArgs", "")]
        default: return
        }
        let original = GameConfiguration.values(text)
        let entries = fields.map { Entry(section: $0.0, key: $0.1,
            original: original[$0.0.lowercased() + "/" + $0.1.lowercased()], applied: $0.2) }
        try Files.writeJSON(entries, to: receipt)
        for (section, key, value) in fields
        {
            text = GameConfiguration.setting(text, section: section, key: key, value: value)
        }
        try text.data(using: .isoLatin1)!.write(to: file, options: .atomic)
    }

    public static func applyDisplay(in directory: URL, plan: LaunchPlan, options: PlayOptions) throws -> [String]
    {
        if plan.integration == .thinker
        {
            let file = directory.appendingPathComponent("thinker.ini")
            guard Files.isRegular(file) else { throw CentauriError.message("Thinker's thinker.ini is missing.") }
            var text = try String(contentsOf: file, encoding: .isoLatin1)
            text = GameConfiguration.setting(text, section: "thinker", key: "DirectDraw", value: "0")
            text = GameConfiguration.setting(text, section: "thinker", key: "DisableOpeningMovie", value: options.skipIntro || !options.moviesEnabled ? "1" : "0")
            if options.windowed && !plan.usesPRACX
            {
                guard options.height % 8 == 0 else { throw CentauriError.message("Thinker window height must be divisible by 8 (for example, 896 instead of 900).") }
                text = GameConfiguration.setting(text, section: "thinker", key: "window_width", value: String(options.width))
                text = GameConfiguration.setting(text, section: "thinker", key: "window_height", value: String(options.height))
            }
            try text.data(using: .isoLatin1)!.write(to: file, options: .atomic)
            if plan.usesPRACX { return plan.arguments }
            // Explicit user arguments can override the default mode.
            let modes = ["-native", "-screen", "-windowed"]
            return plan.arguments.contains(where: modes.contains) ? plan.arguments :
                [options.windowed ? "-windowed" : "-native"] + plan.arguments
        }
        return plan.arguments
    }
}
