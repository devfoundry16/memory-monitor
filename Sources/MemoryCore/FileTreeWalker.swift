import Darwin
import Foundation

/// Measures and removes file trees with fts(3). Never follows symlinks (a link is measured or
/// removed as the link itself), never crosses onto another volume, and never changes the
/// working directory (FTS_NOCHDIR), which would affect every thread in the process.
/// Anything named like user data (`CachePathPolicy.protectedNames`, e.g. a browser profile's
/// Cookies kept inside a tool's cache) is skipped at any depth, and left out of sizes too.
enum FileTreeWalker {
    private static let options = FTS_PHYSICAL | FTS_NOCHDIR | FTS_XDEV
    private static let maxFailures = 50

    private struct FileID: Hashable {
        let device: dev_t
        let inode: ino_t
    }

    /// Space the trees under `entries` take on disk, counting hard-linked files once.
    static func measure(_ entries: [URL], isCancelled: () -> Bool = { false }) -> CacheSize {
        var size = CacheSize()
        var seen = Set<FileID>()
        walk(entries, isCancelled: isCancelled) { fts, entry in
            let info = Int32(entry.pointee.fts_info)
            if isProtected(entry) {
                if info == FTS_D { fts_set(fts, entry, FTS_SKIP) }
                return true
            }
            switch info {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT, FTS_D, FTS_DNR:
                guard let stat = entry.pointee.fts_statp?.pointee else { break }
                if info == FTS_DNR { size.unreadable += 1 }
                if stat.st_nlink > 1, info != FTS_D, info != FTS_DNR,
                   !seen.insert(FileID(device: stat.st_dev, inode: stat.st_ino)).inserted {
                    break
                }
                size.bytes += UInt64(max(stat.st_blocks, 0)) * 512
                if info != FTS_D && info != FTS_DNR { size.files += 1 }
            case FTS_ERR, FTS_NS:
                if entry.pointee.fts_errno != ENOENT { size.unreadable += 1 }
            default:
                break
            }
            return true
        }
        return size
    }

    struct Removal {
        var removedBytes: UInt64 = 0
        var failures: [CleanFailure] = []
        var cancelled = false
    }

    /// Deletes each entry and everything below it, children first. Keeps going past files that
    /// can't be removed and reports them. Something already gone counts as removed.
    static func remove(_ entries: [URL], isCancelled: () -> Bool = { false }) -> Removal {
        var removal = Removal()
        var seen = Set<FileID>()
        func fail(_ path: String, _ code: Int32) {
            guard code != ENOENT, removal.failures.count < maxFailures else { return }
            removal.failures.append(CleanFailure(path: path, reason: String(cString: strerror(code))))
        }
        func freed(_ stat: stat?) -> UInt64 {
            guard let stat else { return 0 }
            if stat.st_nlink > 1, !seen.insert(FileID(device: stat.st_dev, inode: stat.st_ino)).inserted { return 0 }
            return UInt64(max(stat.st_blocks, 0)) * 512
        }

        let completed = walk(entries, isCancelled: isCancelled, onOpenFailure: { fail($0, $1) }) { fts, entry in
            let path = entry.pointee.fts_path!
            let info = Int32(entry.pointee.fts_info)
            let stat = entry.pointee.fts_statp?.pointee
            if isProtected(entry) {
                // Kept. Its parent folders then fail with ENOTEMPTY, which isn't reported.
                if info == FTS_D { fts_set(fts, entry, FTS_SKIP) }
                return true
            }
            switch info {
            case FTS_F, FTS_SL, FTS_SLNONE, FTS_DEFAULT:
                if unlink(path) == 0 { removal.removedBytes += freed(stat) } else { fail(String(cString: path), errno) }
            case FTS_DP, FTS_DNR:
                // After its children (FTS_DP), or a folder that couldn't be opened (FTS_DNR).
                if rmdir(path) == 0 {
                    removal.removedBytes += freed(stat)
                } else if errno != ENOTEMPTY || info == FTS_DNR {
                    // ENOTEMPTY just means something inside was kept or failed, already handled.
                    fail(String(cString: path), info == FTS_DNR ? entry.pointee.fts_errno : errno)
                }
            case FTS_ERR, FTS_NS:
                fail(String(cString: path), entry.pointee.fts_errno)
            default:
                break
            }
            return true
        }
        removal.cancelled = !completed
        return removal
    }

    private static func isProtected(_ entry: UnsafeMutablePointer<FTSENT>) -> Bool {
        let path = String(cString: entry.pointee.fts_path)
        let name = path[(path.lastIndex(of: "/").map { path.index(after: $0) } ?? path.startIndex)...]
        return CachePathPolicy.protectedNames.contains(String(name))
    }

    /// Visits every entry; `visit` returns false to stop. Returns false when cancelled.
    @discardableResult
    private static func walk(
        _ entries: [URL], isCancelled: () -> Bool, onOpenFailure: (String, Int32) -> Void = { _, _ in },
        _ visit: (UnsafeMutablePointer<FTS>, UnsafeMutablePointer<FTSENT>) -> Bool
    ) -> Bool {
        guard !entries.isEmpty else { return true }
        var paths: [UnsafeMutablePointer<CChar>?] = entries.map { strdup($0.path) } + [nil]
        defer { paths.forEach { free($0) } }
        guard let fts = fts_open(&paths, options, nil) else {
            onOpenFailure(entries[0].deletingLastPathComponent().path, errno)
            return true
        }
        defer { fts_close(fts) }
        var count = 0
        while let entry = fts_read(fts) {
            count += 1
            if count % 512 == 0, isCancelled() { return false }
            if !visit(fts, entry) { return false }
        }
        return true
    }
}
