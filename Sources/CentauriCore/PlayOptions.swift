import Foundation

public enum UnitAnimation: String, Codable, CaseIterable
{
    case standard, fast, smooth
}

public struct PlayOptions: Codable, Equatable
{
    public var windowed = false
    public var width = 1024
    public var height = 768
    public var skipIntro = false
    public var moviesEnabled = true
    public var movieVolume = 100
    public var masterVolume = 127
    public var musicVolume = 127
    public var effectsVolume = 127
    public var voiceVolume = 127
    public var mainFontSize = 16
    public var interludeFontSize = 16
    public var gamma = 100
    public var animation: UnitAnimation = .standard
    public var legacyVoxel = true
    public var directDraw = false
    public var positionalAudio = false
    public var eaxAudio = false
    public var systemFileDialogs = false
    public var preserveBeginnerPreferences = true

    public init() {}

    private enum CodingKeys: String, CodingKey
    {
        case windowed, width, height, skipIntro, moviesEnabled, movieVolume
        case masterVolume, musicVolume, effectsVolume, voiceVolume, mainFontSize, interludeFontSize
        case gamma, animation, legacyVoxel, directDraw, positionalAudio, eaxAudio
        case systemFileDialogs, preserveBeginnerPreferences
    }

    public init(from decoder: Decoder) throws
    {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        windowed = try c.decodeIfPresent(Bool.self, forKey: .windowed) ?? windowed
        width = try c.decodeIfPresent(Int.self, forKey: .width) ?? width
        height = try c.decodeIfPresent(Int.self, forKey: .height) ?? height
        skipIntro = try c.decodeIfPresent(Bool.self, forKey: .skipIntro) ?? skipIntro
        moviesEnabled = try c.decodeIfPresent(Bool.self, forKey: .moviesEnabled) ?? moviesEnabled
        movieVolume = try c.decodeIfPresent(Int.self, forKey: .movieVolume) ?? movieVolume
        masterVolume = try c.decodeIfPresent(Int.self, forKey: .masterVolume) ?? masterVolume
        musicVolume = try c.decodeIfPresent(Int.self, forKey: .musicVolume) ?? musicVolume
        effectsVolume = try c.decodeIfPresent(Int.self, forKey: .effectsVolume) ?? effectsVolume
        voiceVolume = try c.decodeIfPresent(Int.self, forKey: .voiceVolume) ?? voiceVolume
        mainFontSize = try c.decodeIfPresent(Int.self, forKey: .mainFontSize) ?? mainFontSize
        interludeFontSize = try c.decodeIfPresent(Int.self, forKey: .interludeFontSize) ?? interludeFontSize
        gamma = try c.decodeIfPresent(Int.self, forKey: .gamma) ?? gamma
        animation = try c.decodeIfPresent(UnitAnimation.self, forKey: .animation) ?? animation
        legacyVoxel = try c.decodeIfPresent(Bool.self, forKey: .legacyVoxel) ?? legacyVoxel
        directDraw = try c.decodeIfPresent(Bool.self, forKey: .directDraw) ?? directDraw
        positionalAudio = try c.decodeIfPresent(Bool.self, forKey: .positionalAudio) ?? positionalAudio
        eaxAudio = try c.decodeIfPresent(Bool.self, forKey: .eaxAudio) ?? eaxAudio
        systemFileDialogs = try c.decodeIfPresent(Bool.self, forKey: .systemFileDialogs) ?? systemFileDialogs
        preserveBeginnerPreferences = try c.decodeIfPresent(Bool.self, forKey: .preserveBeginnerPreferences) ?? preserveBeginnerPreferences
        try validate()
    }

    public func validate() throws
    {
        guard (800...3840).contains(width), (600...2160).contains(height) else
        {
            throw CentauriError.message("Window size must be between 800 × 600 and 3840 × 2160.")
        }
        if windowed && width % 8 != 0
        {
            throw CentauriError.message("Window width must be divisible by 8.")
        }
        guard [masterVolume, musicVolume, effectsVolume, voiceVolume].allSatisfy({ (0...127).contains($0) }),
              (0...100).contains(movieVolume), (50...200).contains(gamma),
              (8...32).contains(mainFontSize), (8...32).contains(interludeFontSize) else
        {
            throw CentauriError.message("A setting is outside its supported range.")
        }
    }

    public func readingGameSettings(_ directory: URL, includeCompatibility: Bool = true) -> PlayOptions
    {
        let file = directory.appendingPathComponent("Alpha Centauri.Ini")
        guard Files.isRegular(file), let text = try? String(contentsOf: file, encoding: .isoLatin1) else { return self }
        let values = GameConfiguration.values(text)
        func number(_ key: String, _ fallback: Int, _ range: ClosedRange<Int>) -> Int
        {
            guard let value = values["alpha centauri/" + key.lowercased()].flatMap(Int.init), range.contains(value) else { return fallback }
            return value
        }
        func flag(_ key: String, _ fallback: Bool) -> Bool { number(key, fallback ? 1 : 0, 0...1) == 1 }
        var result = self
        if moviesEnabled { result.skipIntro = flag("DisableOpeningMovie", skipIntro) }
        result.masterVolume = number("Main Volume", masterVolume, 0...127)
        result.musicVolume = number("Music Volume", musicVolume, 0...127)
        result.effectsVolume = number("SFX Volume", effectsVolume, 0...127)
        result.voiceVolume = number("Voice Volume", voiceVolume, 0...127)
        result.mainFontSize = number("MainFontSize", mainFontSize, 8...32)
        result.interludeFontSize = number("InterludeFontSize", interludeFontSize, 8...32)
        result.gamma = number("Gamma Correction", gamma, 50...200)
        result.systemFileDialogs = flag("WindowsFileBox", systemFileDialogs)
        result.preserveBeginnerPreferences = flag("DontResetBeginnerPrefs", preserveBeginnerPreferences)
        let fast = flag("FastUnitAnim", animation == .fast)
        let smooth = flag("SmoothUnitAnim", animation == .smooth)
        result.animation = fast ? .fast : (smooth ? .smooth : .standard)
        if includeCompatibility
        {
            result.directDraw = flag("DirectDraw", directDraw)
            result.positionalAudio = flag("ds3d", positionalAudio)
            result.eaxAudio = flag("eax", eaxAudio)
            if let value = values["preferences/forceoldvoxelalgorithm"].flatMap(Int.init), (0...1).contains(value)
            {
                result.legacyVoxel = value == 1
            }
        }
        return result
    }
}
