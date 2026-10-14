import Darwin
import Foundation

/// Finds cache folders without measuring them. Only looks inside the cache bases, and in
/// Application Support only at Chromium cache folders. Containers, Mail, Messages, Safari and
/// other folders macOS guards with privacy prompts are never touched.
public struct CacheDiscovery: Sendable {
    public struct Result: Sendable {
        public var items: [CacheItem]
        /// Cache folders macOS doesn't let Fresh read.
        public var noAccess: [URL]
    }

    let environment: CacheEnvironment
    let appIndex: AppIndex
    let policy: CachePathPolicy

    public init(environment: CacheEnvironment, appIndex: AppIndex) {
        self.environment = environment
        self.appIndex = appIndex
        self.policy = CachePathPolicy(environment: environment)
    }

    public func discover() -> Result {
        var state = State()
        discoverCatalog(&state)
        discoverChromiumApps(&state)
        discoverGeneric(&state)
        return Result(items: state.items, noAccess: state.noAccess)
    }

    private struct State {
        var items: [CacheItem] = []
        var noAccess: [URL] = []
        /// Paths already owned by an item; later passes skip them and folders above them exclude them.
        var claims: [String] = []

        func isClaimed(_ url: URL) -> Bool {
            let path = url.path
            return claims.contains { path == $0 || path.hasPrefix($0 + "/") }
        }

        func claims(inside url: URL) -> [URL] {
            let prefix = url.path + "/"
            return claims.filter { $0.hasPrefix(prefix) }.map { URL(fileURLWithPath: $0, isDirectory: true) }
        }

        mutating func add(_ item: CacheItem) {
            items.append(item)
            claims += item.targets.map(\.url.path)
        }
    }

    // MARK: Catalog

    private func discoverCatalog(_ state: inout State) {
        for entry in CacheCatalog.entries {
            let targets = entry.patterns.flatMap(expand).filter { !state.isClaimed($0.url) && isAllowed($0) }
            guard !targets.isEmpty else { continue }
            var owner = entry.owner
            if let lock = entry.lock {
                owner?.singletonLocks = [lock.components.reduce(lock.base.url(in: environment.home)) {
                    $0.appendingPathComponent($1)
                }]
            }
            state.add(CacheItem(
                id: "known/" + entry.id, name: entry.name, detail: entry.detail, category: entry.category,
                owner: owner, targets: Self.unique(targets), advisory: entry.advisory))
        }
    }

    /// The existing folders a pattern matches.
    private func expand(_ pattern: PathPattern) -> [CacheTarget] {
        var matches: [[String]] = [[]]
        let base = pattern.base.url(in: environment.home)
        for component in pattern.components {
            matches = matches.flatMap { prefix -> [[String]] in
                let folder = prefix.reduce(base) { $0.appendingPathComponent($1) }
                guard component == "*" else { return isDirectory(folder.appendingPathComponent(component)) ? [prefix + [component]] : [] }
                return (list(folder) ?? [])
                    .filter { !$0.hasPrefix(".") && isDirectory(folder.appendingPathComponent($0)) }
                    .map { prefix + [$0] }
            }
        }
        return matches.map { CacheTarget(base: pattern.base, relativePath: $0, home: environment.home) }
    }

    // MARK: Chromium and Electron apps

    private func discoverChromiumApps(_ state: inout State) {
        let base = CacheBase.applicationSupport.url(in: environment.home)
        for name in (list(base) ?? []).sorted() {
            guard !name.hasPrefix("."), !name.hasPrefix("com.apple."),
                  !CachePathPolicy.appSupportDenylist.contains(name) else { continue }
            let folder = base.appendingPathComponent(name)
            guard !state.isClaimed(folder), isDirectory(folder),
                  // Only Chromium makes these, so only then look further inside.
                  CachePathPolicy.chromiumMarkers.contains(where: { isDirectory(folder.appendingPathComponent($0)) })
            else { continue }

            var roots = [[name]]
            if isDirectory(folder.appendingPathComponent("Partitions")) {
                roots += (list(folder.appendingPathComponent("Partitions")) ?? []).sorted()
                    .filter { !$0.hasPrefix(".") }
                    .map { [name, "Partitions", $0] }
            }
            func targets(_ leaves: [[String]]) -> [CacheTarget] {
                roots.flatMap { root in
                    leaves.map { CacheTarget(base: .applicationSupport, relativePath: root + $0, home: environment.home) }
                }
                .filter { isDirectory($0.url) && !state.isClaimed($0.url) && isAllowed($0) }
            }

            var owner = appIndex.owner(forFolderName: name) ?? CacheOwner(name: name)
            owner.singletonLocks = [folder.appendingPathComponent("SingletonLock")]
            let web = targets(CachePathPolicy.chromiumCacheLeaves)
            if !web.isEmpty {
                state.add(CacheItem(
                    id: "appsupport/" + name, name: owner.name, detail: "App cache", category: .apps,
                    owner: owner, targets: web))
            }
            let offline = targets(CachePathPolicy.chromiumOfflineLeaves)
            if !offline.isEmpty {
                state.add(CacheItem(
                    id: "appsupport/" + name + "#offline", name: owner.name, detail: "Offline web data",
                    category: .apps, owner: owner, targets: offline,
                    advisory: .caution("Pages and files the app saved for offline use. Your account data stays.")))
            }
        }
    }

    // MARK: Everything else in the cache folders

    private func discoverGeneric(_ state: inout State) {
        for base in [CacheBase.libraryCaches, .dotCache, .libraryLogs] {
            let baseURL = base.url(in: environment.home)
            for name in (list(baseURL) ?? []).sorted() {
                guard !name.hasPrefix(".") else { continue }
                if base == .libraryCaches, name == environment.ownBundleID || CachePathPolicy.hiddenCacheNames.contains(name) {
                    continue
                }
                let url = baseURL.appendingPathComponent(name)
                guard isDirectory(url), !state.isClaimed(url) else { continue }
                guard canOpen(url) else {
                    state.noAccess.append(url)
                    continue
                }
                let target = CacheTarget(base: base, relativePath: [name], home: environment.home,
                                         excluding: state.claims(inside: url))
                // A folder whose only contents belong to other items (e.g. Google holding just Chrome) adds nothing.
                guard isAllowed(target), target.excluding.isEmpty || !target.removableEntries().isEmpty else { continue }

                let owner = appIndex.owner(forFolderName: name)
                let category: CacheCategory = switch base {
                case .libraryLogs: .logs
                case .dotCache: .developer
                default: CacheCatalog.isApple(name) ? .system : owner != nil ? .apps : .other
                }
                let display = owner?.name ?? name
                // ~/.cache is a convention, not a rule: tools sometimes keep sign-ins or settings there.
                let advisory: Advisory? = base == .dotCache
                    ? .caution("Not a cache Fresh knows. Tools sometimes keep sign-ins or settings here.") : nil
                state.add(CacheItem(
                    id: base.rawValue + "/" + name, name: display,
                    detail: base == .libraryLogs ? "Logs" : display == name ? nil : name,
                    category: category, owner: owner, targets: [target], advisory: advisory))
            }
        }
    }

    // MARK: File system access (every call is reported to `onAccess`)

    private func isAllowed(_ target: CacheTarget) -> Bool {
        if case .success = policy.validate(target) { return true }
        return false
    }

    /// A real folder, not a symlink to one.
    private func isDirectory(_ url: URL) -> Bool {
        environment.onAccess?(url)
        var info = stat()
        return lstat(url.path, &info) == 0 && info.st_mode & S_IFMT == S_IFDIR
    }

    private func canOpen(_ url: URL) -> Bool {
        environment.onAccess?(url)
        guard let dir = opendir(url.path) else { return false }
        closedir(dir)
        return true
    }

    private func list(_ url: URL) -> [String]? {
        environment.onAccess?(url)
        return try? FileManager.default.contentsOfDirectory(atPath: url.path)
    }

    private static func unique(_ targets: [CacheTarget]) -> [CacheTarget] {
        var seen = Set<String>()
        return targets.filter { seen.insert($0.url.path).inserted }
    }
}

extension CacheTarget {
    /// What cleaning this target removes: its children, except preserved marker files, folders
    /// that belong to other items, and anything on another volume (a disk mounted inside the
    /// folder). The target folder itself always stays.
    public func removableEntries() -> [URL] {
        removableEntriesIfReadable() ?? []
    }

    /// `nil` when the folder can't be read.
    func removableEntriesIfReadable() -> [URL]? {
        entries(in: url, isRoot: true)
    }

    private func entries(in folder: URL, isRoot: Bool) -> [URL]? {
        var folderInfo = stat()
        guard lstat(folder.path, &folderInfo) == 0,
              let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path) else { return nil }
        var result: [URL] = []
        for name in names.sorted() {
            if isRoot, CachePathPolicy.preservedNames.contains(name) { continue }
            let child = folder.appendingPathComponent(name)
            let path = child.path
            var info = stat()
            // Gone since listing, or a mount point: neither is ours to remove.
            guard lstat(path, &info) == 0, info.st_dev == folderInfo.st_dev else { continue }
            if excluding.contains(where: { $0.path == path }) { continue }
            if excluding.contains(where: { $0.path.hasPrefix(path + "/") }) {
                // Holds another item's folder: take this folder's other contents instead.
                if info.st_mode & S_IFMT == S_IFDIR { result += entries(in: child, isRoot: false) ?? [] }
                continue
            }
            result.append(child)
        }
        return result
    }
}
