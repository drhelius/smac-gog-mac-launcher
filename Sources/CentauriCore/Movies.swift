import Foundation

public struct MovieTools
{
    public let converter: URL
    public let player: URL
    public let hook: URL

    public init(directory: URL)
    {
        converter = directory.appendingPathComponent("centauri-convert")
        player = directory.appendingPathComponent("centauri-movie-player")
        hook = directory.appendingPathComponent("centauri_movies.dll")
    }

    public static func discover() -> MovieTools?
    {
        var candidates: [URL] = []
        if let resources = Bundle.main.resourceURL { candidates.append(resources.appendingPathComponent("MovieTools")) }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0]).standardizedFileURL
        candidates.append(executable.deletingLastPathComponent().appendingPathComponent("MovieTools"))
        for directory in candidates
        {
            let tools = MovieTools(directory: directory)
            if [tools.converter, tools.player, tools.hook].allSatisfy(Files.isRegular) { return tools }
        }
        return nil
    }
}

public final class MovieBridge
{
    private let game: URL
    private let cache: URL
    private let tools: MovieTools
    private let log: URL
    private let token: Cancellation
    private let progress: ProgressHandler
    private let enabled: Bool
    private let volume: Int
    private var request: URL { game.appendingPathComponent("centauri-movie.request") }
    private var done: URL { game.appendingPathComponent("centauri-movie.done") }

    public init(game: URL, cache: URL, tools: MovieTools, log: URL, token: Cancellation,
                enabled: Bool = true, volume: Int = 100, progress: @escaping ProgressHandler) throws
    {
        self.game = game
        self.cache = cache
        self.tools = tools
        self.log = log
        self.token = token
        self.progress = progress
        self.enabled = enabled
        self.volume = volume
        try Files.makeDirectory(cache)
        for file in [request, done, game.appendingPathComponent("centauri-movie.tmp")]
        {
            if FileManager.default.fileExists(atPath: file.path) || Files.isLink(file)
            {
                try FileManager.default.removeItem(at: file)
            }
        }
    }

    public static func safeName(_ input: String) -> Bool
    {
        guard !input.isEmpty, input.utf8.count < 128, !input.contains(".."),
              input.lowercased().hasSuffix(".wve") else { return false }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789 _-.")
        return input.unicodeScalars.allSatisfy { allowed.contains($0) }
    }

    public func tick() throws
    {
        guard Files.isRegular(request) else { return }
        let handle = try FileHandle(forReadingFrom: request)
        let bytes = try handle.read(upToCount: 129) ?? Data()
        try handle.close()
        try FileManager.default.removeItem(at: request)
        defer { try? Data("done".utf8).write(to: done, options: .atomic) }
        if !enabled { return }
        do
        {
            guard let name = String(data: bytes, encoding: .ascii), Self.safeName(name) else
            {
                throw CentauriError.message("Rejected an invalid movie request.")
            }
            let directory = game.appendingPathComponent("movies")
            try Files.requireRealDirectory(directory)
            let matches = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
                .filter { $0.lastPathComponent.lowercased() == name.lowercased() }
            guard matches.count == 1, let input = matches.first, Files.isRegular(input) else
            {
                throw CentauriError.message("The movie \(name) is missing.")
            }
            let hash = try Files.sha256(input, cancellation: token)
            let output = cache.appendingPathComponent("ffmpeg8-v1-" + hash + ".mp4")
            if !Files.isRegular(output)
            {
                progress("Preparing cutscene…")
                try Files.requireSpace(at: cache, bytes: 500_000_000)
                let temporary = cache.appendingPathComponent(UUID().uuidString + ".mp4")
                defer { try? FileManager.default.removeItem(at: temporary) }
                let status = try Commands.run(tools.converter,
                    ["-nostdin", "-y", "-i", input.path, "-c:v", "h264_videotoolbox", "-b:v", "2M",
                     "-pix_fmt", "yuv420p", "-c:a", "aac", "-b:a", "128k", "-movflags", "+faststart", temporary.path],
                    log: log, cancellation: token, timeout: 180)
                guard status == 0, Files.isRegular(temporary),
                      (try temporary.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0) > 0 else
                {
                    throw CentauriError.message("Could not decode \(name).")
                }
                if Files.isLink(output) { try FileManager.default.removeItem(at: output) }
                try FileManager.default.moveItem(at: temporary, to: output)
            }
            progress("Playing cutscene")
            let status = try Commands.run(tools.player, [output.path, "--volume", String(volume)], log: log, cancellation: token, timeout: 900)
            guard status == 0 else
            {
                try? FileManager.default.removeItem(at: output)
                throw CentauriError.message("Native movie playback failed. The cached conversion was removed so it can be retried.")
            }
            progress("Running")
        }
        catch
        {
            try token.check()
            // A failed optional movie must resume the game rather than strand it behind a hidden window.
            progress("Movie skipped: \(error.localizedDescription)")
            let message = Data("Movie bridge: \(error.localizedDescription)\n".utf8)
            if let file = try? FileHandle(forWritingTo: log)
            {
                _ = try? file.seekToEnd()
                try? file.write(contentsOf: message)
                try? file.close()
            }
        }
    }
}
