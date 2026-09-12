import XCTest
@testable import CentauriCore

final class ModTests: XCTestCase
{
    private var root: URL!

    override func setUpWithError() throws
    {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Files.makeDirectory(root)
    }

    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func executable(_ name: String, in directory: URL? = nil, pracx: Bool = false) throws -> URL
    {
        let file = (directory ?? root).appendingPathComponent(name)
        var data = Data(repeating: 0, count: 512)
        data[0] = 0x4d; data[1] = 0x5a; data[60] = 128
        data[128] = 0x50; data[129] = 0x45; data[132] = 0x4c; data[133] = 1
        data[152] = 0x0b; data[153] = 1
        if pracx { data.append(contentsOf: [0xe8, 5, 0, 0, 0, 0x70, 0x72, 0x61, 0x78, 0, 0xff, 0x15]) }
        try data.write(to: file)
        return file
    }

    private func service() throws -> CentauriService
    {
        let service = CentauriService(layout: Layout(root: root.appendingPathComponent("data")))
        let game = service.layout.installation.appendingPathComponent("game")
        try Files.makeDirectory(game)
        _ = try executable("terran.exe", in: game)
        _ = try executable("terranx.exe", in: game)
        try Data("original".utf8).write(to: game.appendingPathComponent("alphax.txt"))
        try Files.makeDirectory(game.appendingPathComponent("saves"))
        try Data("saved game".utf8).write(to: game.appendingPathComponent("saves/example.sav"))
        try Files.writeJSON(GameManifest(schema: 1, installedAt: Date(), runtimeID: RuntimeDescriptor.pinned.id,
            executableHashes: [:], recognizedLegacyBuild: false, skippedLinks: [], sourceKind: "test"),
            to: service.layout.installation.appendingPathComponent("manifest.json"))
        return service
    }

    func testUnknownAndModifiedExecutablesRunWithoutNativePatching() throws
    {
        let file = try executable("terran.exe")
        XCTAssertEqual(try LaunchPlan.resolve(directory: root, game: .alphaCentauri).integration, .custom)
        try (Data(contentsOf: file) + Data([1])).write(to: file)
        let plan = try LaunchPlan.resolve(directory: root, game: .alphaCentauri)
        XCTAssertEqual(plan.executable, file)
        XCTAssertFalse(plan.nativeMovies)
        XCTAssertFalse(plan.managesSettings)
        let profile = LaunchProfile(name: "Force native", game: .alphaCentauri, integration: .native)
        XCTAssertThrowsError(try LaunchPlan.resolve(directory: root, game: .alphaCentauri, profile: profile))
    }

    func testPRACXLoaderIsDetectedIndependentlyOfFilename() throws
    {
        _ = try executable("alternate.exe", pracx: true)
        let profile = LaunchProfile(name: "PRACX", game: .alienCrossfire, executable: "alternate.exe")
        let plan = try LaunchPlan.resolve(directory: root, game: .alienCrossfire, profile: profile)
        XCTAssertEqual(plan.integration, .pracx)
        XCTAssertTrue(plan.nativeMovies)
        XCTAssertFalse(plan.managesDisplay)
        XCTAssertFalse(plan.knownGame)
    }

    func testThinkerWithPRACXLeavesDisplayToPRACX() throws
    {
        _ = try executable("thinker.exe")
        _ = try executable("terranx.exe", pracx: true)
        let profile = LaunchProfile(name: "Thinker", game: .alienCrossfire, executable: "thinker.exe")
        let plan = try LaunchPlan.resolve(directory: root, game: .alienCrossfire, profile: profile)
        XCTAssertEqual(plan.integration, .thinker)
        XCTAssertTrue(plan.usesPRACX)
        XCTAssertFalse(plan.managesDisplay)
    }

    func testPRACXSegmentOverrideLoaderIsRecognized() throws
    {
        let file = try executable("terranx.exe")
        let loader = Data([0xe8, 5, 0, 0, 0, 0x70, 0x72, 0x61, 0x78, 0, 0x3e, 0xff, 0x15])
        try (Data(contentsOf: file) + loader).write(to: file)
        XCTAssertTrue(try LaunchPlan.hasPRACXLoader(file))
        XCTAssertEqual(try LaunchPlan.resolve(directory: root, game: .alienCrossfire).integration, .pracx)
    }

    func testGenericLaunchAndInstallValidationAccepts64BitWindowsExecutables() throws
    {
        let file = try executable("installer.exe")
        var bytes = try Data(contentsOf: file)
        bytes[132] = 0x64; bytes[133] = 0x86; bytes[153] = 2
        try bytes.write(to: file)
        XCTAssertTrue(try GameSource.isWindowsExecutable(file))
        XCTAssertFalse(try GameSource.isWindowsX86(file))
        let profile = LaunchProfile(name: "Custom", game: .alphaCentauri, executable: "installer.exe")
        XCTAssertEqual(try LaunchPlan.resolve(directory: root, game: .alphaCentauri, profile: profile).integration, .custom)
    }

    func testCustomIntegrationDoesNotOverrideARecognizedMod() throws
    {
        _ = try executable("mod.exe", pracx: true)
        let profile = LaunchProfile(name: "Unmanaged", game: .alphaCentauri, executable: "mod.exe", integration: .custom)
        let plan = try LaunchPlan.resolve(directory: root, game: .alphaCentauri, profile: profile)
        XCTAssertEqual(plan.integration, .custom)
        XCTAssertFalse(plan.nativeMovies)
    }

    func testExecutableCannotEscapeConfigurationThroughPathsOrLinks() throws
    {
        for name in ["../outside.exe", "/outside.exe", "C:\\outside.exe", "folder/../outside.exe", "folder//game.exe"]
        {
            XCTAssertThrowsError(try LaunchPlan.validatePath(name))
        }
        let outside = root.appendingPathComponent("outside")
        let game = root.appendingPathComponent("game")
        try Files.makeDirectory(outside)
        try Files.makeDirectory(game)
        _ = try executable("test.exe", in: outside)
        try FileManager.default.createSymbolicLink(at: game.appendingPathComponent("link"), withDestinationURL: outside)
        let profile = LaunchProfile(name: "Link", game: .alphaCentauri, executable: "link/test.exe")
        XCTAssertThrowsError(try LaunchPlan.resolve(directory: game, game: .alphaCentauri, profile: profile))
    }

    func testArgumentsPreserveQuotesPathsAndLiteralShellCharacters() throws
    {
        XCTAssertEqual(try LaunchPlan.arguments(#"-smac "a b" 'c d' C:\folder\file $HOME ; echo"#),
            ["-smac", "a b", "c d", "C:\\folder\\file", "$HOME", ";", "echo"])
        XCTAssertEqual(try LaunchPlan.arguments(#""""#), [""])
        XCTAssertThrowsError(try LaunchPlan.arguments("\"unfinished"))
        XCTAssertThrowsError(try LaunchPlan.arguments("a\nb"))
    }

    func testCustomWorkingDirectoryIsIsolatedAndOldProfilesStillDecode() throws
    {
        _ = try executable("mod.exe")
        try Files.makeDirectory(root.appendingPathComponent("content"))
        let profile = LaunchProfile(name: "Nested", game: .alphaCentauri, executable: "mod.exe", workingDirectory: "content")
        let plan = try LaunchPlan.resolve(directory: root, game: .alphaCentauri, profile: profile)
        XCTAssertEqual(plan.workingDirectory.path, root.appendingPathComponent("content").path)
        for path in ["..", "../outside", "/tmp", "C:\\game", "folder//child"]
        {
            XCTAssertThrowsError(try LaunchPlan.directory(in: root, relative: path))
        }
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(profile)) as? [String: Any])
        object.removeValue(forKey: "workingDirectory")
        let old = try JSONDecoder().decode(LaunchProfile.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(old.workingDirectory)
        XCTAssertEqual(try LaunchPlan.resolve(directory: root, game: .alphaCentauri, profile: old).workingDirectory.path, root.path)
    }

    func testInterruptedOverlayIsRecoveredUnderTheOperationLock() throws
    {
        let service = try service()
        let profile = try service.createProfile(name: "Recovery", game: .alphaCentauri, cancellation: Cancellation(), progress: { _ in })
        let directory = try service.profileDirectory(profile)
        try FileManager.default.moveItem(at: directory.appendingPathComponent("game"), to: directory.appendingPathComponent("previous-game"))
        XCTAssertThrowsError(try service.gameDirectory(profile: profile))
        let lock = try InstallationLock(root: service.layout.root)
        defer { withExtendedLifetime(lock) {} }
        try service.recoverProfileGame(profile)
        XCTAssertEqual(try String(contentsOf: service.gameDirectory(profile: profile).appendingPathComponent("alphax.txt")), "original")
    }

    func testFailedNativeMP4PlaybackPreservesTheUsersMovie() throws
    {
        let movies = root.appendingPathComponent("movies")
        try Files.makeDirectory(movies)
        let movie = movies.appendingPathComponent("test.mp4")
        try Data("user movie".utf8).write(to: movie)
        let player = root.appendingPathComponent("centauri-movie-player")
        try "#!/bin/sh\nexit 1\n".write(to: player, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: player.path)
        let bridge = try MovieBridge(game: root, cache: root.appendingPathComponent("cache"), tools: MovieTools(directory: root),
            log: root.appendingPathComponent("movie.log"), token: Cancellation(), progress: { _ in })
        try Data("test.mp4".utf8).write(to: root.appendingPathComponent("centauri-movie.request"))
        try bridge.tick()
        XCTAssertEqual(try String(contentsOf: movie), "user movie")
        XCTAssertTrue(Files.isRegular(root.appendingPathComponent("centauri-movie.done")))
    }

    func testProfilesPreserveOriginalFilesSavesAndSettings() throws
    {
        let service = try service()
        let profile = try service.createProfile(name: "My mod", game: .alienCrossfire, cancellation: Cancellation(), progress: { _ in })
        let original = try service.gameDirectory()
        let mod = try service.gameDirectory(profile: profile)
        XCTAssertNotEqual(original, mod)
        XCTAssertEqual(try Data(contentsOf: original.appendingPathComponent("saves/example.sav")),
                       try Data(contentsOf: mod.appendingPathComponent("saves/example.sav")))
        let files = root.appendingPathComponent("mod-files")
        try Files.makeDirectory(files)
        try Data("modded".utf8).write(to: files.appendingPathComponent("alphax.txt"))
        try service.addModFiles(files, profile: profile, cancellation: Cancellation(), progress: { _ in })
        XCTAssertEqual(try String(contentsOf: original.appendingPathComponent("alphax.txt")), "original")
        XCTAssertEqual(try String(contentsOf: mod.appendingPathComponent("alphax.txt")), "modded")
        var settings = PlayOptions()
        settings.movieVolume = 15
        try service.saveOptions(settings, profile: profile)
        XCTAssertEqual(service.options(profile: profile).movieVolume, 15)
        XCTAssertEqual(service.options().movieVolume, 100)
        XCTAssertEqual(service.profiles(), [profile])
        XCTAssertNil(service.manifest?.executableHashes["not-a-game"])
    }

    func testFailedModOverlayLeavesConfigurationUnchanged() throws
    {
        let service = try service()
        let profile = try service.createProfile(name: "My mod", game: .alphaCentauri, cancellation: Cancellation(), progress: { _ in })
        let files = root.appendingPathComponent("mod-files")
        try Files.makeDirectory(files)
        try Data("modified".utf8).write(to: files.appendingPathComponent("alphax.txt"))
        try FileManager.default.createSymbolicLink(at: files.appendingPathComponent("escape"), withDestinationURL: root)
        XCTAssertThrowsError(try service.addModFiles(files, profile: profile, cancellation: Cancellation(), progress: { _ in }))
        XCTAssertEqual(try String(contentsOf: service.gameDirectory(profile: profile).appendingPathComponent("alphax.txt")), "original")
    }

    func testMovieOverridesRestorePreviousPlayerButKeepOtherEdits() throws
    {
        let file = root.appendingPathComponent("Alpha Centauri.Ini")
        let receipt = root.appendingPathComponent("receipt.json")
        try "[PRACX]\r\nMoviePlayerCommand=old-player.exe\r\nZoomLevels=20\r\n".write(to: file, atomically: true, encoding: .isoLatin1)
        try ModConfiguration.applyMovies(in: root, receipt: receipt, integration: .pracx)
        var text = try String(contentsOf: file, encoding: .isoLatin1)
        XCTAssertEqual(GameConfiguration.values(text)["pracx/movieplayercommand"], "centauri-movie-request.exe")
        text = GameConfiguration.setting(text, section: "PRACX", key: "ZoomLevels", value: "30")
        try text.write(to: file, atomically: true, encoding: .isoLatin1)
        try ModConfiguration.restoreMovies(in: root, receipt: receipt)
        let restored = GameConfiguration.values(try String(contentsOf: file, encoding: .isoLatin1))
        XCTAssertEqual(restored["pracx/movieplayercommand"], "old-player.exe")
        XCTAssertEqual(restored["pracx/zoomlevels"], "30")
        XCTAssertFalse(Files.isRegular(receipt))
    }

    func testMovieOverrideRecoveryRespectsAnEditedPlayerAndAbsentKeys() throws
    {
        let file = root.appendingPathComponent("Alpha Centauri.Ini")
        let receipt = root.appendingPathComponent("receipt.json")
        try "[Alpha Centauri]\r\nMovieExtension=mp4\r\n".write(to: file, atomically: true, encoding: .isoLatin1)
        try ModConfiguration.applyMovies(in: root, receipt: receipt, integration: .thinker)
        let changed = GameConfiguration.setting(try String(contentsOf: file, encoding: .isoLatin1),
            section: "Alpha Centauri", key: "MoviePlayerPath", value: "new-player.exe")
        try changed.write(to: file, atomically: true, encoding: .isoLatin1)
        try ModConfiguration.restoreMovies(in: root, receipt: receipt)
        let values = GameConfiguration.values(try String(contentsOf: file, encoding: .isoLatin1))
        XCTAssertEqual(values["alpha centauri/movieplayerpath"], "new-player.exe")
        XCTAssertEqual(values["alpha centauri/movieextension"], "mp4")
        XCTAssertNil(values["alpha centauri/movieplayerargs"])
    }

    func testThinkerUsesItsActualDisplayAndIntroSettings() throws
    {
        _ = try executable("thinker.exe")
        _ = try executable("terranx.exe")
        let ini = root.appendingPathComponent("thinker.ini")
        try "[thinker]\nwindow_width=1024\nwindow_height=768\n".write(to: ini, atomically: true, encoding: .isoLatin1)
        let profile = LaunchProfile(name: "Thinker", game: .alienCrossfire, executable: "thinker.exe")
        let plan = try LaunchPlan.resolve(directory: root, game: .alienCrossfire, profile: profile)
        var options = PlayOptions()
        options.windowed = true
        options.width = 1600
        options.height = 896
        options.skipIntro = true
        XCTAssertEqual(try ModConfiguration.applyDisplay(in: root, plan: plan, options: options), ["-windowed"])
        let values = GameConfiguration.values(try String(contentsOf: ini, encoding: .isoLatin1))
        XCTAssertEqual(values["thinker/window_width"], "1600")
        XCTAssertEqual(values["thinker/window_height"], "896")
        XCTAssertEqual(values["thinker/disableopeningmovie"], "1")
        options.windowed = false
        XCTAssertEqual(try ModConfiguration.applyDisplay(in: root, plan: plan, options: options), ["-native"])
        options.windowed = true
        options.height = 900
        XCTAssertThrowsError(try ModConfiguration.applyDisplay(in: root, plan: plan, options: options))
    }

    func testThinkerFullscreenUsesAlignedRenderingWithoutChangingDesktopResolution()
    {
        var options = PlayOptions()
        let display = ModConfiguration.presentationOptions(options, desktopWidth: 1512, desktopHeight: 982)
        XCTAssertTrue(display.windowed)
        XCTAssertEqual(display.width, 1512)
        XCTAssertEqual(display.height, 976)
        XCTAssertFalse(options.windowed)
        options.windowed = true
        options.width = 1024
        options.height = 768
        let window = ModConfiguration.presentationOptions(options, desktopWidth: 1512, desktopHeight: 982)
        XCTAssertEqual(window.width, 1024)
        XCTAssertEqual(window.height, 768)
    }
}
