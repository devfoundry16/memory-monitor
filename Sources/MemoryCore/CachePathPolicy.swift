import Darwin
import Foundation

/// Decides which folders may be cleaned. Discovery only creates targets this allows, and the
/// cleaner checks every target again immediately before touching it.
public struct CachePathPolicy: Sendable {
    let environment: CacheEnvironment

    public init(environment: CacheEnvironment) {
        self.environment = environment
    }

    /// Chromium and Electron cache folders, which apps rebuild on their own.
    public static let chromiumCacheLeaves: [[String]] = [
        ["Cache"], ["Code Cache"], ["GPUCache"], ["DawnGraphiteCache"], ["DawnWebGPUCache"],
        ["GraphiteDawnCache"], ["GPUPersistentCache"], ["GrShaderCache"], ["ShaderCache"],
        // VS Code and its forks.
        ["CachedData"], ["CachedExtensionVSIXs"],
    ]
    /// Pages and files a web app saved for offline use: cache, but removing it loses offline copies.
    public static let chromiumOfflineLeaves: [[String]] = [["Service Worker", "CacheStorage"], ["Service Worker", "ScriptCache"]]
    /// Only Chromium creates these, so they identify an Electron app's data folder.
    public static let chromiumMarkers = ["Code Cache", "GPUCache"]

    /// User data that sits next to caches. A target path may never contain these.
    public static let protectedNames: Set<String> = [
        "IndexedDB", "Local Storage", "Session Storage", "Cookies", "Cookies-journal", "File System",
        "WebStorage", "databases", "blob_storage", "Database", "Local State", "Preferences",
        "Network Persistent State", "shared_proto_db", "SharedStorage", "Trust Tokens", "Extensions",
        "Local Extension Settings", "Login Data", "History", "Web Data", "Bookmarks", "Sessions",
    ]

    /// The only paths allowed under the home base.
    public static let homeAllowlist: Set<[String]> = [
        [".npm", "_cacache"], [".npm", "_npx"], [".npm", "_logs"],
        [".cargo", "registry", "cache"], [".cargo", "registry", "src"],
        [".bun", "install", "cache"], [".yarn", "berry", "cache"], [".gradle", "caches"],
        ["Library", "Developer", "Xcode", "DerivedData"], ["Library", "Developer", "CoreSimulator", "Caches"],
    ]

    /// Application Support folders that hold personal data; never looked into.
    public static let appSupportDenylist: Set<String> = [
        "AddressBook", "CallHistoryDB", "CallHistoryTransactions", "CloudDocs", "Knowledge", "MobileSync",
        "FaceTime", "FileProvider", "DifferentialPrivacy", "iCloud", "Mail", "Messages", "Photos",
        "Safari", "SyncServices", "Dock", "Accounts", "Keychains",
    ]

    /// Caches that hold live state for macOS services, or that macOS protects. Never listed.
    public static let hiddenCacheNames: Set<String> = [
        "com.apple.bird", "com.apple.nsurlsessiond", "com.apple.containermanagerd", "com.apple.cache_delete",
        "com.apple.akd", "com.apple.accountsd", "com.apple.ap.adprivacyd", "com.apple.Safari",
        "com.apple.HomeKit", "com.apple.findmy.imagecache", "CloudKit", "FamilyCircle", "familycircled",
        "PassKit", "com.apple.passd",
    ]

    /// Kept when a cache folder is emptied (marks the folder as a cache for backup tools).
    public static let preservedNames: Set<String> = ["CACHEDIR.TAG"]

    /// Checks `target` against the rules and the disk. Returns its resolved path on success.
    public func validate(_ target: CacheTarget) -> Result<URL, CleanRefusal> {
        let path = target.relativePath
        guard !path.isEmpty, path.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." && !$0.contains("/") }) else {
            return .failure(.invalidPath)
        }
        let base = target.base.url(in: environment.home)
        guard target.url.standardizedFileURL.path
            == path.reduce(base, { $0.appendingPathComponent($1) }).standardizedFileURL.path
        else { return .failure(.invalidPath) }
        if let name = path.first(where: Self.protectedNames.contains) { return .failure(.protectedName(name)) }

        switch target.base {
        case .libraryCaches, .dotCache, .libraryLogs:
            let first = path[0]
            guard !first.hasPrefix(".") else { return .failure(.invalidPath) }
            if target.base == .libraryCaches {
                guard first != environment.ownBundleID else { return .failure(.outsideAllowedFolders) }
                if Self.hiddenCacheNames.contains(first) { return .failure(.protectedName(first)) }
            }
        case .applicationSupport:
            let first = path[0]
            guard path.count >= 2, !first.hasPrefix("."), !first.hasPrefix("com.apple."),
                  !Self.appSupportDenylist.contains(first),
                  (Self.chromiumCacheLeaves + Self.chromiumOfflineLeaves).contains(where: { path.ends(with: $0) })
            else { return .failure(.outsideAllowedFolders) }
        case .home:
            guard Self.homeAllowlist.contains(path) else { return .failure(.outsideAllowedFolders) }
        }

        // A real folder, reached without passing through any symlink.
        var info = stat()
        guard lstat(target.url.path, &info) == 0 else { return .failure(.missing) }
        if info.st_mode & S_IFMT == S_IFLNK { return .failure(.symlinkInPath) }
        guard info.st_mode & S_IFMT == S_IFDIR else { return .failure(.notADirectory) }
        guard let realBase = Self.realPath(base), let realTarget = Self.realPath(target.url) else {
            return .failure(.missing)
        }
        let expected = path.reduce(URL(fileURLWithPath: realBase, isDirectory: true)) { $0.appendingPathComponent($1) }
        guard realTarget == expected.path else { return .failure(.symlinkInPath) }
        guard realTarget != realBase else { return .failure(.isBaseFolder) }
        // A volume mounted at the target is not part of the cache, however it's reached.
        var baseInfo = stat()
        guard stat(realBase, &baseInfo) == 0 else { return .failure(.missing) }
        guard baseInfo.st_dev == info.st_dev else { return .failure(.otherVolume) }
        return .success(URL(fileURLWithPath: realTarget, isDirectory: true))
    }

    static func realPath(_ url: URL) -> String? {
        guard let resolved = realpath(url.path, nil) else { return nil }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}

extension Array where Element == String {
    func ends(with suffix: [String]) -> Bool {
        count >= suffix.count && Array(self[(count - suffix.count)...]) == suffix
    }
}
