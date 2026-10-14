import Foundation
@testable import MemoryCore

/// A throwaway home folder for cache tests. Nothing here touches the real home folder.
final class CacheFixture: @unchecked Sendable {
    let home: URL
    private let lock = NSLock()
    private var accessed: [String] = []

    init() throws {
        // Under /var/folders, which is itself reached through the /var → /private/var symlink.
        home = FileManager.default.temporaryDirectory
            .appendingPathComponent("fresh-cache-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    }

    deinit {
        // Undo flags and permissions tests set, so cleanup can remove everything.
        _ = try? Process.run(URL(fileURLWithPath: "/usr/bin/chflags"), arguments: ["-R", "nouchg", home.path]).waitUntilExit()
        _ = try? Process.run(URL(fileURLWithPath: "/bin/chmod"), arguments: ["-R", "u+rwx", home.path]).waitUntilExit()
        try? FileManager.default.removeItem(at: home)
    }

    var environment: CacheEnvironment {
        CacheEnvironment(home: home, applicationDirectories: [home.appendingPathComponent("Applications")],
                         onAccess: { [weak self] url in self?.record(url) })
    }

    var accessedPaths: [String] { lock.withLock { accessed } }

    private func record(_ url: URL) {
        lock.withLock { accessed.append(url.path) }
    }

    func url(_ relative: String) -> URL { home.appendingPathComponent(relative) }

    @discardableResult
    func file(_ relative: String, bytes: Int = 1000) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x5a, count: bytes).write(to: url)
        return url
    }

    @discardableResult
    func dir(_ relative: String) throws -> URL {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func symlink(_ relative: String, to destination: URL) throws {
        let url = url(relative)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: destination)
    }

    /// A minimal app bundle, enough for AppIndex.
    func app(_ name: String, bundleID: String) throws {
        let contents = url("Applications/\(name).app/Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleName": name, "CFBundleExecutable": name]
        try plist.write(to: contents.appendingPathComponent("Info.plist"))
    }

    func exists(_ relative: String) -> Bool {
        var info = stat()
        return lstat(url(relative).path, &info) == 0
    }

    func target(_ base: CacheBase, _ path: String...) -> CacheTarget {
        CacheTarget(base: base, relativePath: path, home: home)
    }
}
