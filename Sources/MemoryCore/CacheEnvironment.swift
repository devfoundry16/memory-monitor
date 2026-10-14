import Foundation

/// Where the cache cleaner looks. Tests point `home` at a temporary folder.
public struct CacheEnvironment: Sendable {
    public var home: URL
    /// Folders searched for installed apps, to name and identify cache owners.
    public var applicationDirectories: [URL]
    /// Fresh's own cache folder is never listed; it holds the Trash staging folder.
    public var ownBundleID: String
    /// Called with every path discovery looks at. Lets tests prove protected folders are never touched.
    public var onAccess: (@Sendable (URL) -> Void)?

    public init(
        home: URL, applicationDirectories: [URL] = [], ownBundleID: String = "com.devfoundry.fresh",
        onAccess: (@Sendable (URL) -> Void)? = nil
    ) {
        self.home = home
        self.applicationDirectories = applicationDirectories
        self.ownBundleID = ownBundleID
        self.onAccess = onAccess
    }

    public static var current: CacheEnvironment {
        let realHome = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        var home = realHome
        #if DEBUG
        // Debug builds only: run the cleaner against a fixture folder instead of the real caches.
        if let override = ProcessInfo.processInfo.environment["FRESH_CACHE_HOME"], !override.isEmpty {
            home = URL(fileURLWithPath: override, isDirectory: true)
        }
        #endif
        return CacheEnvironment(
            home: home,
            applicationDirectories: [
                URL(fileURLWithPath: "/Applications", isDirectory: true),
                URL(fileURLWithPath: "/Applications/Utilities", isDirectory: true),
                realHome.appendingPathComponent("Applications", isDirectory: true),
                URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            ],
            ownBundleID: Bundle.main.bundleIdentifier ?? "com.devfoundry.fresh")
    }

    /// Fresh's own cache folder, which holds the Trash staging area.
    var ownCacheFolder: URL {
        CacheBase.libraryCaches.url(in: home).appendingPathComponent(ownBundleID, isDirectory: true)
    }
}
