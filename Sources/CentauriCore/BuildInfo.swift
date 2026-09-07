import Foundation

public enum BuildInfo
{
    public static let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "source build"
    public static let revision = Bundle.main.object(forInfoDictionaryKey: "SMACBuildCommit") as? String ?? "unknown"
}
