import XCTest
@testable import CentauriCore

final class MovieTests: XCTestCase
{
    private func integer(_ data: Data, _ offset: Int) -> Int
    {
        Int(data[offset]) | Int(data[offset + 1]) << 8 | Int(data[offset + 2]) << 16 | Int(data[offset + 3]) << 24
    }

    private func image() -> Data
    {
        var data = Data(repeating: 0, count: 1024)
        func put(_ offset: Int, _ value: Int, count: Int = 4)
        {
            for i in 0..<count { data[offset + i] = UInt8((value >> (8 * i)) & 255) }
        }
        put(0, 0x5a4d, count: 2)
        put(60, 128)
        put(128, 0x4550)
        put(132, 0x14c, count: 2)
        put(134, 1, count: 2)
        put(148, 224, count: 2)
        let optional = 152
        put(optional, 0x10b, count: 2)
        put(optional + 28, 0x400000)
        put(optional + 32, 4096)
        put(optional + 36, 512)
        put(optional + 56, 8192)
        put(optional + 60, 512)
        put(optional + 104, 4096)
        put(optional + 108, 40)
        let section = 376
        put(section + 8, 512)
        put(section + 12, 4096)
        put(section + 16, 512)
        put(section + 20, 512)
        put(512, 0x1080)
        put(524, 0x1050)
        put(528, 0x1090)
        return data
    }

    func testAddsSeparateImportWithoutChangingOriginalCodeOrEntryPoint() throws
    {
        let original = image()
        let patched = try MoviePatch.addImport(to: original)
        XCTAssertEqual(patched.count, 1536)
        XCTAssertEqual(patched[134], 2)
        XCTAssertEqual(patched[512..<1024], original[512..<1024])
        XCTAssertEqual(integer(patched, 152 + 16), integer(original, 152 + 16))
        XCTAssertEqual(integer(patched, 152 + 104), 8192)
        XCTAssertEqual(integer(patched, 152 + 56), 12288)
        XCTAssertEqual(patched[1024..<1044], original[512..<532])
        XCTAssertNotNil(patched.range(of: Data("centauri_movies.dll\0".utf8)))
        XCTAssertNotNil(patched.range(of: Data("Initialize\0".utf8)))
    }

    func testTruncatedPEAndInvalidAlignmentAreRejected() throws
    {
        let original = image()
        for length in [0, 10, 255, 400, 700]
        {
            XCTAssertThrowsError(try MoviePatch.addImport(to: Data(original.prefix(length))))
        }
        var malformed = original
        malformed[152 + 36] = 3
        XCTAssertThrowsError(try MoviePatch.addImport(to: malformed))
    }

    func testMissingRoomForSectionHeaderIsRejected() throws
    {
        var malformed = image()
        malformed[152 + 60] = 0x90
        malformed[152 + 61] = 1
        XCTAssertThrowsError(try MoviePatch.addImport(to: malformed))
    }

    func testMovieNamesCannotEscapeTheMovieDirectory() throws
    {
        for name in ["../opening.wve", "/opening.wve", "C:\\opening.wve", "opening.wve\n", "opening.exe", "", "a..wve"]
        {
            XCTAssertFalse(MovieBridge.safeName(name), name)
        }
        for name in ["opening.wve", "humanGenome.wve", "clinical_Immortality.WVE", "movie 2.wve", "opening.mp4"]
        {
            XCTAssertTrue(MovieBridge.safeName(name), name)
        }
    }

    func testInvalidMovieRequestIsAcknowledgedWithoutLaunchingAnything() throws
    {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Files.makeDirectory(root)
        defer { try? FileManager.default.removeItem(at: root) }
        let bridge = try MovieBridge(game: root, cache: root.appendingPathComponent("cache"),
            tools: MovieTools(directory: root.appendingPathComponent("nonexistent")), log: root.appendingPathComponent("movies.log"),
            token: Cancellation(), progress: { _ in })
        try Data("../private.wve".utf8).write(to: root.appendingPathComponent("centauri-movie.request"))
        XCTAssertNoThrow(try bridge.tick())
        XCTAssertTrue(Files.isRegular(root.appendingPathComponent("centauri-movie.done")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("centauri-movie.request").path))
    }
}
