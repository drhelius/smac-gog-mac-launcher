import Foundation

public enum GameExit
{
    public static func isNormal(_ status: Int32, knownGame: Bool, log: String) -> Bool
    {
        let text = log.lowercased()
        let failures = ["unhandled page fault", "unhandled exception", "exception frame is not in stack",
                        "shellexecuteex failed", "application could not be started", "failed to initialize",
                        "could not load kernel32", "import_dll library", "module not found"]
        guard !failures.contains(where: text.contains) else { return false }
        // These legacy executables return 1 on an ordinary user-requested exit.
        return status == 0 || (knownGame && status == 1)
    }
}
