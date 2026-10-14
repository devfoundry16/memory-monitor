import Foundation

/// Groups in the Clean tab, in display order.
public enum CacheCategory: String, CaseIterable, Sendable {
    case browsers, apps, developer, logs, other, system
}

/// The folders caches are found under. Nothing outside these is ever scanned or removed.
public enum CacheBase: String, CaseIterable, Sendable {
    /// ~/Library/Caches
    case libraryCaches
    /// ~/.cache
    case dotCache
    /// ~/Library/Logs
    case libraryLogs
    /// ~/Library/Application Support, for Chromium and Electron cache folders only.
    case applicationSupport
    /// Exact paths in the home folder, such as ~/.npm/_cacache.
    case home

    var components: [String] {
        switch self {
        case .libraryCaches: ["Library", "Caches"]
        case .dotCache: [".cache"]
        case .libraryLogs: ["Library", "Logs"]
        case .applicationSupport: ["Library", "Application Support"]
        case .home: []
        }
    }

    public func url(in home: URL) -> URL {
        components.reduce(home) { $0.appendingPathComponent($1, isDirectory: true) }
    }
}

/// A note shown with a cache. Caution items are not pre-selected.
public enum Advisory: Sendable, Hashable {
    case info(String)
    case caution(String)

    public var text: String {
        switch self {
        case .info(let text), .caution(let text): text
        }
    }

    public var isCaution: Bool {
        if case .caution = self { return true }
        return false
    }
}

/// The app or tool a cache belongs to, and how to tell whether it's running.
public struct CacheOwner: Sendable, Hashable {
    public var name: String
    public var bundleIDs: [String]
    /// Command-line tools without a bundle, matched against running process names.
    public var processNames: [String]
    /// Chromium's `SingletonLock` links ("host-1234"), which name the running instance's PID.
    public var singletonLocks: [URL]

    public init(name: String, bundleIDs: [String] = [], processNames: [String] = [], singletonLocks: [URL] = []) {
        self.name = name
        self.bundleIDs = bundleIDs
        self.processNames = processNames
        self.singletonLocks = singletonLocks
    }

    /// Groups items that belong to the same app.
    public var key: String { bundleIDs.first ?? "name:" + name.lowercased() }
}

/// One cache folder. Only its contents are ever removed; the folder itself stays.
public struct CacheTarget: Sendable, Hashable {
    public var base: CacheBase
    /// Path components under `base`.
    public var relativePath: [String]
    public var url: URL
    /// Folders inside this one that belong to another item, so they're skipped here.
    public var excluding: [URL]

    public init(base: CacheBase, relativePath: [String], home: URL, excluding: [URL] = []) {
        self.base = base
        self.relativePath = relativePath
        self.url = relativePath.reduce(base.url(in: home)) { $0.appendingPathComponent($1, isDirectory: true) }
        self.excluding = excluding
    }
}

public struct CacheItem: Identifiable, Sendable, Hashable {
    /// Stable and path-derived, e.g. "caches/Homebrew" or "appsupport/Notion".
    public var id: String
    public var name: String
    /// A short description, e.g. "Web cache".
    public var detail: String?
    public var category: CacheCategory
    public var owner: CacheOwner?
    public var targets: [CacheTarget]
    public var advisory: Advisory?

    public init(
        id: String, name: String, detail: String? = nil, category: CacheCategory,
        owner: CacheOwner? = nil, targets: [CacheTarget], advisory: Advisory? = nil
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.category = category
        self.owner = owner
        self.targets = targets
        self.advisory = advisory
    }

    /// Pre-selected after a scan (unless its app is running).
    public var isRecommended: Bool { category != .system && !(advisory?.isCaution ?? false) }
}

public struct CacheSize: Sendable, Equatable {
    /// Space on disk, with hard-linked files counted once.
    public var bytes: UInt64 = 0
    public var files = 0
    /// Folders that couldn't be read, so `bytes` may be low.
    public var unreadable = 0

    public init(bytes: UInt64 = 0, files: Int = 0, unreadable: Int = 0) {
        self.bytes = bytes
        self.files = files
        self.unreadable = unreadable
    }
}

public enum CleanMode: Sendable {
    case deletePermanently
    case moveToTrash
}

/// Why a cache folder was refused for cleaning.
public enum CleanRefusal: Error, Sendable, Equatable {
    case invalidPath
    case outsideAllowedFolders
    case protectedName(String)
    case symlinkInPath
    case notADirectory
    case isBaseFolder
    case missing
    /// On a different volume from its base folder, e.g. a disk mounted inside a cache folder.
    case otherVolume
}

public struct CleanFailure: Sendable, Hashable {
    public var path: String
    public var reason: String
}

public struct ItemResult: Sendable, Equatable {
    public enum Status: Sendable, Equatable {
        case cleaned
        /// Some files couldn't be removed; see `failures`.
        case partial
        case skippedInUse
        case refused(CleanRefusal)
        case cancelled
    }

    public var id: CacheItem.ID
    public var status: Status
    public var removedBytes: UInt64
    public var failures: [CleanFailure]
}

public struct CleanReport: Sendable {
    public var mode: CleanMode
    public var results: [ItemResult]
    /// Bytes removed (or moved to the Trash), counted file by file.
    public var removedBytes: UInt64 { results.reduce(0) { $0 + $1.removedBytes } }
    /// Change in free space on the volume, for permanent deletes. Can be less than
    /// `removedBytes` when files are shared as APFS clones or held by local snapshots.
    public var freeSpaceChange: Int64?
    /// The single folder sent to the Trash, in Trash mode.
    public var trashedFolder: URL?
}
