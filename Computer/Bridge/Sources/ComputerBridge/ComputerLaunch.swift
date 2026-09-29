import Foundation

public enum ComputerLaunch {
    /// Launch Services preserves URLs from sandboxed callers, unlike launch arguments.
    /// This URL starts the provider without opening the library.
    public static func backgroundURL(for build: ComputerBuildIdentity = .current) -> URL {
        URL(string: build.urlScheme + "://provider/start")!
    }
    /// Opens the library and has the app check for updates.
    public static func updateCheckURL(for build: ComputerBuildIdentity = .current) -> URL {
        URL(string: build.urlScheme + "://updates/check")!
    }
}
