import XCTest
@testable import CentauriCore

final class CoreTests: XCTestCase
{
    private var root: URL!

    override func setUpWithError() throws
    {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Centauri Tests " + UUID().uuidString)
        try Files.makeDirectory(root)
    }

    override func tearDownWithError() throws
    {
        try FileManager.default.removeItem(at: root)
    }

    private func fixture(at directory: URL) throws
    {
        try Files.makeDirectory(directory)
        var binary = Data(repeating: 0, count: 256)
        binary[0] = 0x4d
        binary[1] = 0x5a
        binary[60] = 128
        binary.replaceSubrange(128..<134, with: [0x50, 0x45, 0, 0, 0x4c, 0x01])
        binary[152] = 0x0b
        binary[153] = 0x01
        for game in Game.allCases { try binary.write(to: directory.appendingPathComponent(game.rawValue)) }
        for name in ["alpha.txt", "alphax.txt", "palette.pcx"]
        {
            try Data("fixture".utf8).write(to: directory.appendingPathComponent(name))
        }
        for name in ["fx", "movies"] { try Files.makeDirectory(directory.appendingPathComponent(name)) }
    }

    private func mockRuntime(layout: Layout) throws
    {
        let directory = layout.runtimes.appendingPathComponent(RuntimeDescriptor.pinned.id)
        let runtime = WineRuntime(directory: directory, descriptor: .pinned)
        try Files.makeDirectory(runtime.bin)
        let wine = """
        #!/bin/sh
        if [ "$1" = "wineboot" ]; then
          /bin/mkdir -p "$WINEPREFIX/dosdevices" "$WINEPREFIX/drive_c/users/test"
        fi
        exit 0
        """
        for (file, script) in [(runtime.wine, wine), (runtime.server, "#!/bin/sh\nexit 0\n")]
        {
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        try Files.writeJSON(RuntimeDescriptor.pinned, to: directory.appendingPathComponent("receipt.json"))
        for name in ["libinotify.0.dylib", "libfreetype.6.dylib"]
        {
            try Data().write(to: directory.appendingPathComponent(name))
        }
    }

    func testValidatePayloadAndIdentifyUnknownVersion() throws
    {
        let source = root.appendingPathComponent("game")
        try fixture(at: source)
        let hashes = try GameSource.validate(source)
        XCTAssertEqual(hashes.count, 2)
        XCTAssertNotEqual(hashes, GameSource.legacyHashes)
        try FileManager.default.removeItem(at: source.appendingPathComponent("alphax.txt"))
        XCTAssertThrowsError(try GameSource.validate(source))
    }

    func testRejectMalformedPEOffsetAndWrongArchitecture() throws
    {
        let source = root.appendingPathComponent("game")
        try fixture(at: source)
        let file = source.appendingPathComponent("terran.exe")
        var data = try Data(contentsOf: file)
        data[132] = 0x64
        try data.write(to: file)
        XCTAssertFalse(try GameSource.isWindowsX86(file))
        data[63] = 0xff
        try data.write(to: file)
        XCTAssertFalse(try GameSource.isWindowsX86(file))
    }

    func testDiscoverLegacyWrapperWithoutFollowingDriveAlias() throws
    {
        let wrapper = root.appendingPathComponent("GOG.app")
        let directory = wrapper.appendingPathComponent("Contents/Resources/drive_c/Program Files/GOG Games/Alpha Centauri")
        try fixture(at: directory)
        try FileManager.default.createSymbolicLink(at: wrapper.appendingPathComponent("drive_c"), withDestinationURL: URL(fileURLWithPath: "/"))
        XCTAssertEqual(try GameSource.discover(wrapper).resolvingSymlinksInPath().path, directory.resolvingSymlinksInPath().path)
    }

    func testCopyRejectsExternalAndDanglingLinks() throws
    {
        let source = root.appendingPathComponent("source")
        let destination = root.appendingPathComponent("destination")
        try Files.makeDirectory(source)
        try Data("keep".utf8).write(to: source.appendingPathComponent("normal"))
        try FileManager.default.createSymbolicLink(at: source.appendingPathComponent("loop"), withDestinationURL: source)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("missing").path,
                                                   withDestinationPath: "/nonexistent/private-file")
        var skipped: [String] = []
        try Files.copyTree(source, to: destination, cancellation: Cancellation(), skipped: &skipped)
        XCTAssertEqual(Set(skipped), Set(["loop", "missing"]))
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("normal")), Data("keep".utf8))
        XCTAssertFalse(Files.isLink(destination.appendingPathComponent("loop")))
    }

    func testRequiredExecutableCannotBeASymlink() throws
    {
        let source = root.appendingPathComponent("game")
        try fixture(at: source)
        let executable = source.appendingPathComponent("terran.exe")
        try FileManager.default.moveItem(at: executable, to: root.appendingPathComponent("outside.exe"))
        try FileManager.default.createSymbolicLink(at: executable, withDestinationURL: root.appendingPathComponent("outside.exe"))
        XCTAssertThrowsError(try GameSource.validate(source))
    }

    func testCopyCancellationPreservesSource() throws
    {
        let source = root.appendingPathComponent("game")
        try fixture(at: source)
        let cancellation = Cancellation()
        cancellation.cancel()
        var skipped: [String] = []
        XCTAssertThrowsError(try Files.copyTree(source, to: root.appendingPathComponent("copy"),
            cancellation: cancellation, skipped: &skipped))
        XCTAssertEqual(try GameSource.validate(source).count, 2)
    }

    func testCopyCannotRecurseIntoItsOwnDestination() throws
    {
        let source = root.appendingPathComponent("game")
        try fixture(at: source)
        var skipped: [String] = []
        XCTAssertThrowsError(try Files.copyTree(source, to: source.appendingPathComponent("nested/copy"),
            cancellation: Cancellation(), skipped: &skipped))
        XCTAssertFalse(FileManager.default.fileExists(atPath: source.appendingPathComponent("nested").path))
    }

    func testDataRootInsideSourceRejectedBeforeRuntimeDownload() throws
    {
        let source = root.appendingPathComponent("game")
        try fixture(at: source)
        let layout = Layout(root: source.appendingPathComponent("data"))
        XCTAssertThrowsError(try CentauriService(layout: layout).install(source: source,
            cancellation: Cancellation(), progress: { _ in }))
        XCTAssertNil(RuntimeInstaller.installed(layout: layout))
        XCTAssertEqual(try GameSource.validate(source).count, 2)
    }

    func testSHA256KnownVector() throws
    {
        let file = root.appendingPathComponent("hash")
        try Data("abc".utf8).write(to: file)
        XCTAssertEqual(try Files.sha256(file), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testINIEditPreservesUnrelatedSectionsAndRemovesDuplicateKey() throws
    {
        let text = "; personal settings\r\n[Alpha Centauri]\r\nDirectDraw=1\r\nVoice Volume=94\r\ndirectdraw=2\r\n[Other]\r\nDirectDraw=9\r\n"
        let result = GameConfiguration.setting(text, section: "Alpha Centauri", key: "DirectDraw", value: "0")
        XCTAssertEqual(result, "; personal settings\r\n[Alpha Centauri]\r\nDirectDraw=0\r\nVoice Volume=94\r\n[Other]\r\nDirectDraw=9\r\n")
        XCTAssertEqual(GameConfiguration.setting(result, section: "Alpha Centauri", key: "DirectDraw", value: "0"), result)
    }

    func testINIMissingSectionAndKey() throws
    {
        XCTAssertEqual(GameConfiguration.setting("", section: "Alpha Centauri", key: "DirectDraw", value: "0"),
                       "[Alpha Centauri]\r\nDirectDraw=0\r\n")
        XCTAssertEqual(GameConfiguration.setting("[Alpha Centauri]\nFoo=1\n[Next]\nBar=2\n", section: "Alpha Centauri", key: "DirectDraw", value: "0"),
                       "[Alpha Centauri]\r\nFoo=1\r\nDirectDraw=0\r\n[Next]\r\nBar=2\r\n")
    }

    func testINIPreservesLatin1AndBacksUpOriginal() throws
    {
        let file = root.appendingPathComponent("Alpha Centauri.Ini")
        let data = "[Personal]\r\nName=José\r\n".data(using: .isoLatin1)!
        try data.write(to: file)
        try GameConfiguration.apply(PlayOptions(), gameDirectory: root)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("Alpha Centauri.Ini.centauri-backup")), data)
        let text = try String(contentsOf: file, encoding: .isoLatin1)
        XCTAssertTrue(text.contains("Name=José"))
        XCTAssertTrue(text.contains("DisableOpeningMovie=1"))
        XCTAssertTrue(text.contains("DirectDraw=0"))
    }

    func testLockExcludesOtherOperationAndReleases() throws
    {
        var first: InstallationLock? = try InstallationLock(root: root)
        XCTAssertThrowsError(try InstallationLock(root: root))
        withExtendedLifetime(first) {}
        first = nil
        XCTAssertNoThrow(try InstallationLock(root: root))
    }

    func testArchiveTraversalRejected() throws
    {
        for name in ["/etc/passwd", "Wine Stable.app/../../escape", "Other.app/file", "../Wine Stable.app/file"]
        {
            XCTAssertThrowsError(try RuntimeInstaller.validateArchiveEntry(name, bundle: "Wine Stable.app"))
        }
        XCTAssertNoThrow(try RuntimeInstaller.validateArchiveEntry("Wine Stable.app/Contents/Resources/wine/bin/wine", bundle: "Wine Stable.app"))
    }

    func testRuntimeChecksumFailureCannotInstall() throws
    {
        let layout = Layout(root: root.appendingPathComponent("data"))
        try layout.prepare()
        let bad = root.appendingPathComponent("bad.tar.xz")
        try Data("not a runtime".utf8).write(to: bad)
        XCTAssertThrowsError(try RuntimeInstaller.ensure(layout: layout, archive: bad,
            cancellation: Cancellation(), progress: { _ in }))
        XCTAssertNil(RuntimeInstaller.installed(layout: layout))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: layout.runtimes.path).isEmpty)
    }

    func testRuntimeEnvironmentIsPrefixScoped() throws
    {
        let runtime = WineRuntime(directory: root, descriptor: .pinned)
        let prefix = root.appendingPathComponent("prefix")
        let env = runtime.environment(prefix: prefix)
        XCTAssertEqual(env["WINEPREFIX"], prefix.path)
        XCTAssertNil(env["WINEARCH"])
        XCTAssertNil(env["WINEDLLOVERRIDES"])
        XCTAssertNil(env["DYLD_INSERT_LIBRARIES"])
    }

    func testInstallerTransactionRepairsLinksAndPreservesOriginal() throws
    {
        let source = root.appendingPathComponent("User's GOG app")
        try fixture(at: source)
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("saves").path, withDestinationPath: "/missing/saves")
        try FileManager.default.createSymbolicLink(atPath: source.appendingPathComponent("Alpha Centauri.Ini").path, withDestinationPath: "/missing/settings")
        let layout = Layout(root: root.appendingPathComponent("data"))
        try layout.prepare()
        try mockRuntime(layout: layout)
        let service = CentauriService(layout: layout)
        try service.install(source: source, cancellation: Cancellation(), progress: { _ in })
        XCTAssertNotNil(service.manifest)
        XCTAssertEqual(service.manifest?.skippedLinks.count, 2)
        XCTAssertTrue(Files.isLink(source.appendingPathComponent("saves")))
        XCTAssertFalse(Files.isLink(layout.saves))
        XCTAssertFalse(Files.isLink(layout.installation.appendingPathComponent("prefix/dosdevices/g:")))
        XCTAssertThrowsError(try service.install(source: source, cancellation: Cancellation(), progress: { _ in }))
        XCTAssertNotNil(service.manifest)
    }

    func testFailedImportCannotReplaceExistingInstallation() throws
    {
        let layout = Layout(root: root.appendingPathComponent("data"))
        try layout.prepare()
        try Files.makeDirectory(layout.installation)
        let save = layout.installation.appendingPathComponent("sentinel.sav")
        try Data("keep".utf8).write(to: save)
        let source = root.appendingPathComponent("incomplete")
        try Files.makeDirectory(source)
        XCTAssertThrowsError(try CentauriService(layout: layout).install(source: source, cancellation: Cancellation(), progress: { _ in }))
        XCTAssertEqual(try Data(contentsOf: save), Data("keep".utf8))
    }

    func testInterruptedCommitRestoresPreviousInstallation() throws
    {
        let layout = Layout(root: root.appendingPathComponent("data"))
        try layout.prepare()
        try Files.makeDirectory(layout.previous)
        try Data("saved".utf8).write(to: layout.previous.appendingPathComponent("sentinel"))
        try Files.writeJSON(".installation-test", to: layout.root.appendingPathComponent("commit.json"))
        try CentauriService(layout: layout).recoverInterruptedCommit()
        XCTAssertEqual(try Data(contentsOf: layout.installation.appendingPathComponent("sentinel")), Data("saved".utf8))
        XCTAssertFalse(FileManager.default.fileExists(atPath: layout.root.appendingPathComponent("commit.json").path))
    }

    func testCommandsPreserveLiteralArgumentsAndTimeout() throws
    {
        let log = root.appendingPathComponent("commands.log")
        let text = "a space ' quote $(not-a-command) `literal`"
        XCTAssertEqual(try Commands.run(URL(fileURLWithPath: "/usr/bin/printf"), ["%s", text], log: log), 0)
        XCTAssertEqual(try String(contentsOf: log), text)
        XCTAssertThrowsError(try Commands.run(URL(fileURLWithPath: "/bin/sleep"), ["10"], log: log, timeout: 0.1))
    }

    func testDiagnosticsExcludeGameDataAndRedactHome() throws
    {
        let layout = Layout(root: root.appendingPathComponent("data"))
        try layout.prepare()
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        try "error at \(home)/some-file".write(to: layout.logs.appendingPathComponent("game.log"), atomically: true, encoding: .utf8)
        try Files.makeDirectory(layout.saves)
        try Data("private save".utf8).write(to: layout.saves.appendingPathComponent("private.sav"))
        let output = root.appendingPathComponent("output")
        try Files.makeDirectory(output)
        try CentauriService(layout: layout).exportDiagnostics(to: output)
        let directory = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: output, includingPropertiesForKeys: nil).first)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: directory.path)), Set(["report.txt", "game.log"]))
        XCTAssertFalse(try String(contentsOf: directory.appendingPathComponent("game.log")).contains(home))
    }
}
