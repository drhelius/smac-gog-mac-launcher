import XCTest
@testable import CentauriCore

final class OptionsTests: XCTestCase
{
    func testOldSettingsKeepDisplayChoiceAndReceiveSafeNewDefaults() throws
    {
        let old = Data(#"{"windowed":true,"width":1280,"height":800,"skipIntro":true}"#.utf8)
        let options = try JSONDecoder().decode(PlayOptions.self, from: old)
        XCTAssertTrue(options.windowed)
        XCTAssertEqual(options.width, 1280)
        XCTAssertTrue(options.skipIntro)
        XCTAssertTrue(options.legacyVoxel)
        XCTAssertFalse(options.directDraw)
        XCTAssertFalse(options.positionalAudio)
        XCTAssertFalse(options.eaxAudio)
        XCTAssertTrue(options.moviesEnabled)
        XCTAssertEqual(options.movieVolume, 100)
    }

    func testOutOfRangeAdvancedSettingsAreRejected() throws
    {
        var options = PlayOptions()
        options.musicVolume = 128
        XCTAssertThrowsError(try options.validate())
        options.musicVolume = 127
        options.mainFontSize = 7
        XCTAssertThrowsError(try options.validate())
        options.mainFontSize = 16
        options.gamma = 201
        XCTAssertThrowsError(try options.validate())
        options.gamma = 100
        options.movieVolume = -1
        XCTAssertThrowsError(try options.validate())
    }

    func testAdvancedOptionsRoundTripAndINIOutput() throws
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Files.makeDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        var options = PlayOptions()
        options.musicVolume = 32
        options.effectsVolume = 70
        options.voiceVolume = 110
        options.mainFontSize = 20
        options.animation = .smooth
        options.systemFileDialogs = true
        options.moviesEnabled = false
        options.gamma = 110
        let decoded = try JSONDecoder().decode(PlayOptions.self, from: JSONEncoder().encode(options))
        XCTAssertEqual(decoded, options)
        try GameConfiguration.apply(options, gameDirectory: directory)
        let values = GameConfiguration.values(try String(contentsOf: directory.appendingPathComponent("Alpha Centauri.Ini"), encoding: .isoLatin1))
        XCTAssertEqual(values["alpha centauri/music volume"], "32")
        XCTAssertEqual(values["alpha centauri/mainfontsize"], "20")
        XCTAssertEqual(values["alpha centauri/fastunitanim"], "0")
        XCTAssertEqual(values["alpha centauri/smoothunitanim"], "1")
        XCTAssertEqual(values["alpha centauri/windowsfilebox"], "1")
        XCTAssertEqual(values["alpha centauri/disableopeningmovie"], "1")
        XCTAssertEqual(PlayOptions().readingGameSettings(directory).musicVolume, 32)
        XCTAssertEqual(PlayOptions().readingGameSettings(directory).animation, .smooth)
    }

    func testImportedSettingsCannotEnableUnsafeCompatibilityDefaults() throws
    {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Files.makeDirectory(directory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let text = "[Alpha Centauri]\r\nDirectDraw=1\r\nds3d=1\r\neax=1\r\nMusic Volume=45\r\n[PREFERENCES]\r\nForceOldVoxelAlgorithm=0\r\n"
        try text.write(to: directory.appendingPathComponent("Alpha Centauri.Ini"), atomically: true, encoding: .isoLatin1)
        let imported = PlayOptions().readingGameSettings(directory, includeCompatibility: false)
        XCTAssertEqual(imported.musicVolume, 45)
        XCTAssertFalse(imported.directDraw)
        XCTAssertFalse(imported.positionalAudio)
        XCTAssertFalse(imported.eaxAudio)
        XCTAssertTrue(imported.legacyVoxel)
    }

    func testSettingsPersistBeforeInstallation() throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = CentauriService(layout: Layout(root: root))
        var options = PlayOptions()
        options.movieVolume = 60
        options.width = 1440
        options.height = 900
        try service.saveOptions(options)
        XCTAssertEqual(service.options(), options)
        XCTAssertNil(service.manifest)
    }
}
