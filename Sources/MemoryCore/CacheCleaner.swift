import Darwin
import Foundation
import os

public enum CleanEvent: Sendable {
    case started(CacheItem.ID)
    case finished(ItemResult)
    case done(CleanReport)
}

/// Asks a running clean to stop after the file it's on. The clean still finishes its report.
public final class CleanControl: Sendable {
    private let stopped = OSAllocatedUnfairLock(initialState: false)

    public init() {}

    public func stop() { stopped.withLock { $0 = true } }
    public var isStopped: Bool { stopped.withLock { $0 } }
}

/// Removes the contents of cache folders, one item at a time. Every target is checked against
/// `CachePathPolicy` again, and the owning app's running state re-checked, right before it's touched.
public struct CacheCleaner: Sendable {
    /// Moves a file or folder to the Trash; returns where it ended up.
    public typealias Trasher = @Sendable (URL) throws -> URL?
    /// Whether an app or tool is running right now.
    public typealias InUseCheck = @Sendable (CacheOwner) async -> Bool

    public static let systemTrash: Trasher = { url in
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        return resulting as URL?
    }

    private let environment: CacheEnvironment
    private let policy: CachePathPolicy
    private let trash: Trasher
    private let isInUse: InUseCheck
    private let settleDelay: Duration

    public init(
        environment: CacheEnvironment, trash: @escaping Trasher = CacheCleaner.systemTrash,
        isInUse: @escaping InUseCheck, settleDelay: Duration = .seconds(1)
    ) {
        self.environment = environment
        self.policy = CachePathPolicy(environment: environment)
        self.trash = trash
        self.isInUse = isInUse
        self.settleDelay = settleDelay
    }

    /// What `clean` would remove, without removing anything. Refused targets are left out.
    public func plannedRemovals(_ items: [CacheItem]) -> [(id: CacheItem.ID, entries: [URL])] {
        items.map { item in
            (item.id, item.targets.flatMap { target -> [URL] in
                guard case .success = policy.validate(target) else { return [] }
                return target.removableEntries()
            })
        }
    }

    /// Cleans `items`, streaming progress and ending with `.done(report)`, also when stopped
    /// through `control`. Cancelling the reading task stops it too, but loses the report.
    public func clean(_ items: [CacheItem], mode: CleanMode, control: CleanControl = CleanControl()) -> AsyncStream<CleanEvent> {
        AsyncStream { continuation in
            let task = Task.detached(priority: .userInitiated) {
                let report = await run(items, mode: mode, control: control) { continuation.yield($0) }
                continuation.yield(.done(report))
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    private func run(_ items: [CacheItem], mode: CleanMode, control: CleanControl,
                     emit: (CleanEvent) -> Void) async -> CleanReport {
        let shouldStop = { Task.isCancelled || control.isStopped }
        let freeBefore = mode == .deletePermanently ? freeSpace() : nil
        let staging = mode == .moveToTrash ? Staging(root: stagingRoot()) : nil
        var results: [ItemResult] = []

        for item in items {
            guard !shouldStop() else {
                results.append(ItemResult(id: item.id, status: .cancelled, removedBytes: 0, failures: []))
                continue
            }
            emit(.started(item.id))
            let result = await clean(item, staging: staging, shouldStop: shouldStop)
            results.append(result)
            emit(.finished(result))
        }

        var report = CleanReport(mode: mode, results: results)
        if let staging {
            report.trashedFolder = staging.finish(trash: trash, results: &report.results)
        } else if let freeBefore {
            try? await Task.sleep(for: settleDelay) // let the file system catch up before measuring
            report.freeSpaceChange = freeSpace().map { $0 - freeBefore }
        }
        return report
    }

    private func clean(_ item: CacheItem, staging: Staging?, shouldStop: @escaping () -> Bool) async -> ItemResult {
        var result = ItemResult(id: item.id, status: .cleaned, removedBytes: 0, failures: [])
        if let owner = item.owner, await isInUse(owner) {
            result.status = .skippedInUse
            return result
        }

        for target in item.targets {
            if case .failure(let refusal) = policy.validate(target) {
                result.status = .refused(refusal)
                return result
            }
            guard let entries = target.removableEntriesIfReadable() else {
                result.failures.append(CleanFailure(path: target.url.path, reason: "Couldn't read this folder"))
                continue
            }
            for entry in entries {
                if shouldStop() {
                    result.status = .cancelled
                    return result
                }
                // Checked again before every entry, so a folder swapped for a symlink meanwhile is caught.
                if case .failure(let refusal) = policy.validate(target) {
                    result.status = .refused(refusal)
                    return result
                }
                if let staging {
                    let moved = staging.move(entry, for: item, home: environment.home, trash: trash)
                    result.removedBytes += moved.bytes
                    result.failures += moved.failures
                } else {
                    let removal = FileTreeWalker.remove([entry], isCancelled: shouldStop)
                    result.removedBytes += removal.removedBytes
                    result.failures += removal.failures
                    if removal.cancelled {
                        result.status = .cancelled
                        return result
                    }
                }
            }
        }
        if !result.failures.isEmpty { result.status = .partial }
        return result
    }

    private func stagingRoot() -> URL {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH.mm.ss"
        let name = "Fresh Cleanup \(formatter.string(from: Date()))"
        var root = environment.ownCacheFolder.appendingPathComponent(name)
        var number = 2
        while FileManager.default.fileExists(atPath: root.path) {
            root = environment.ownCacheFolder.appendingPathComponent("\(name) \(number)")
            number += 1
        }
        return root
    }

    private func freeSpace() -> Int64? {
        var url = environment.home
        url.removeAllCachedResourceValues()
        return (try? url.resourceValues(forKeys: [.volumeAvailableCapacityKey]))?.volumeAvailableCapacity.map(Int64.init)
    }
}

/// Trash mode: moves everything into one folder first, then trashes that folder once, so the
/// Trash gets a single "Fresh Cleanup …" folder instead of hundreds of folders named "Cache".
/// Never deletes anything: moves are exclusive renames, and a failed trash puts things back.
private final class Staging: @unchecked Sendable {
    let root: URL
    /// (original, staged) pairs, in the order they were moved.
    private var moves: [(from: URL, to: URL, item: CacheItem.ID, bytes: UInt64)] = []

    init(root: URL) {
        self.root = root
    }

    func move(_ entry: URL, for item: CacheItem, home: URL,
              trash: CacheCleaner.Trasher) -> (bytes: UInt64, failures: [CleanFailure]) {
        let folder = root.appendingPathComponent(
            item.name.replacingOccurrences(of: "/", with: "-") + " (" + item.id.replacingOccurrences(of: "/", with: "-") + ")")
        let homePath = home.path + "/"
        let size = FileTreeWalker.measure([entry]).bytes
        // Keep the original path inside the staging folder, so it's clear where things came from.
        let relative = entry.path.hasPrefix(homePath) ? String(entry.path.dropFirst(homePath.count)) : entry.lastPathComponent
        let destination = folder.appendingPathComponent(relative)
        do {
            try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        } catch {
            return (0, [CleanFailure(path: entry.path, reason: error.localizedDescription)])
        }
        if renamex_np(entry.path, destination.path, UInt32(RENAME_EXCL)) == 0 {
            moves.append((entry, destination, item.id, size))
            return (size, [])
        }
        if errno == EXDEV {
            // On another volume: trash it directly.
            do {
                _ = try trash(entry)
                return (size, [])
            } catch {
                return (0, [CleanFailure(path: entry.path, reason: error.localizedDescription)])
            }
        }
        if errno == ENOENT { return (0, []) } // already gone
        return (0, [CleanFailure(path: entry.path, reason: String(cString: strerror(errno)))])
    }

    /// Trashes the staging folder. If that fails, puts everything back where it was.
    func finish(trash: CacheCleaner.Trasher, results: inout [ItemResult]) -> URL? {
        guard !moves.isEmpty else {
            Self.removeEmptyFolders(root)
            return nil
        }
        do {
            return try trash(root) ?? root
        } catch {
            var allRestored = true
            for move in moves.reversed() {
                // Exclusive: never replaces a file an app has written there since.
                if renamex_np(move.to.path, move.from.path, UInt32(RENAME_EXCL)) != 0 {
                    allRestored = false
                    if let index = results.firstIndex(where: { $0.id == move.item }) {
                        results[index].failures.append(CleanFailure(
                            path: move.from.path, reason: "Couldn't put back; it's still in \(move.to.path)"))
                    }
                }
            }
            for move in moves {
                guard let index = results.firstIndex(where: { $0.id == move.item }) else { continue }
                results[index].removedBytes -= min(move.bytes, results[index].removedBytes)
                results[index].status = .partial
                if results[index].failures.isEmpty {
                    results[index].failures.append(CleanFailure(
                        path: root.path, reason: "Couldn't move to the Trash: \(error.localizedDescription)"))
                }
            }
            // With everything back in place only empty folders remain. Otherwise keep the staging
            // folder: Trash mode must never delete anything for good.
            if allRestored { Self.removeEmptyFolders(root) }
            return nil
        }
    }

    /// Removes `folder` and empty folders below it. Never removes a file: rmdir fails on anything non-empty.
    private static func removeEmptyFolders(_ folder: URL) {
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] {
            let child = folder.appendingPathComponent(name)
            var info = stat()
            if lstat(child.path, &info) == 0, info.st_mode & S_IFMT == S_IFDIR { removeEmptyFolders(child) }
        }
        rmdir(folder.path)
    }
}
