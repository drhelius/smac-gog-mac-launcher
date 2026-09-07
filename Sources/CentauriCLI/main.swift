import Foundation
import CentauriCore
import Darwin

func main() throws
{
    var args = Array(CommandLine.arguments.dropFirst())
    func option(_ name: String) throws -> String?
    {
        guard let index = args.firstIndex(of: name) else { return nil }
        guard args.indices.contains(index + 1), !args[index + 1].hasPrefix("--") else
        {
            throw CentauriError.message("Missing value for \(name)")
        }
        let result = args[index + 1]
        args.removeSubrange(index...index + 1)
        return result
    }
    let root = try option("--data-dir").map { URL(fileURLWithPath: $0, isDirectory: true) }
    let archive = try option("--runtime-archive").map { URL(fileURLWithPath: $0) }
    let libraries = try option("--library-archive").map { URL(fileURLWithPath: $0) }
    let source = try option("--source").map { URL(fileURLWithPath: $0) }
    let saves = try option("--saves").map { URL(fileURLWithPath: $0, isDirectory: true) }
    let size = try option("--size") ?? "1024x768"
    let fullscreen = args.contains("--fullscreen")
    let movies = args.contains("--intro")
    args.removeAll { $0 == "--fullscreen" || $0 == "--intro" }
    let service = CentauriService(layout: Layout(root: root))
    let token = Cancellation()
    signal(SIGINT, SIG_IGN)
    signal(SIGTERM, SIG_IGN)
    let interrupt = DispatchSource.makeSignalSource(signal: SIGINT, queue: .global())
    let terminate = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .global())
    interrupt.setEventHandler { token.cancel() }
    terminate.setEventHandler { token.cancel() }
    interrupt.resume()
    terminate.resume()
    defer { interrupt.cancel(); terminate.cancel() }
    let progress: ProgressHandler = { print($0); fflush(stdout) }
    switch args.first ?? "help"
    {
    case "inspect":
        guard args.count == 1, let source = source else { throw CentauriError.message("inspect requires --source PATH") }
        let directory = try GameSource.discover(source)
        let hashes = try GameSource.validate(directory)
        print("Game folder: \(directory.path)")
        for name in hashes.keys.sorted() { print("\(name): \(hashes[name]!)") }
        print("Recognized legacy build: \(hashes == GameSource.legacyHashes)")
    case "install":
        guard args.count == 1, let source = source else { throw CentauriError.message("install requires --source PATH") }
        try service.install(source: source, runtimeArchive: archive, librariesArchive: libraries, saves: saves, cancellation: token, progress: progress)
    case "play":
        guard args.count == 2, let game = ["smac": Game.alphaCentauri, "smacx": Game.alienCrossfire][args[1]] else
        {
            throw CentauriError.message("Use play smac or play smacx")
        }
        var options = PlayOptions()
        options.windowed = !fullscreen
        options.skipIntro = !movies
        let parts = size.split(separator: "x")
        guard parts.count == 2, let width = Int(parts[0]), let height = Int(parts[1]) else
        {
            throw CentauriError.message("Resolution must be WIDTHxHEIGHT")
        }
        options.width = width
        options.height = height
        try service.play(game, options: options, cancellation: token, progress: progress)
    case "status":
        print("Data: \(service.layout.root.path)")
        print("Installed: \(service.manifest != nil)")
        print("Runtime: \(RuntimeInstaller.installed(layout: service.layout)?.descriptor.id ?? "not installed")")
    case "diagnostics":
        guard let source = source else { throw CentauriError.message("diagnostics requires --source OUTPUT_DIRECTORY") }
        try service.exportDiagnostics(to: source)
    case "help", "--help", "-h":
        print("""
        SMAC Launcher CLI
          inspect --source GAME_APP_OR_FOLDER
          install --source GAME_APP_FOLDER_OR_SETUP_EXE [--saves FOLDER]
                  [--runtime-archive FILE --library-archive FILE]
          play smac|smacx [--fullscreen] [--size 1024x768] [--intro]
          status
          diagnostics --source OUTPUT_DIRECTORY
        Every command accepts --data-dir PATH to isolate development data.
        Ctrl-C stops only this session. Game files are never redistributed.
        """)
    default: throw CentauriError.message("Unknown command. Use --help.")
    }
}

do { try main() }
catch
{
    fputs("SMAC Launcher: \(error.localizedDescription)\n", stderr)
    exit(1)
}
