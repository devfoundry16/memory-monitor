import Foundation
import Testing
@testable import MemoryCore

/// Every test cleans a throwaway fixture home; Trash mode uses a fake Trash inside the fixture.
@Suite struct CacheCleanerTests {
    private func item(_ fixture: CacheFixture, id: String = "test", owner: CacheOwner? = nil,
                      _ targets: CacheTarget...) -> CacheItem {
        CacheItem(id: id, name: "Test", category: .other, owner: owner, targets: targets)
    }

    private func cleaner(_ fixture: CacheFixture, inUse: Bool = false,
                         trash: CacheCleaner.Trasher? = nil) -> CacheCleaner {
        CacheCleaner(
            environment: fixture.environment,
            trash: trash ?? { _ in throw CocoaError(.featureUnsupported) },
            isInUse: { _ in inUse }, settleDelay: .zero)
    }

    private func run(_ cleaner: CacheCleaner, _ items: [CacheItem], _ mode: CleanMode) async -> CleanReport? {
        for await event in cleaner.clean(items, mode: mode) {
            if case .done(let report) = event { return report }
        }
        return nil
    }

    /// Moves into `<fixture>/FakeTrash` and records each call.
    private final class FakeTrash: @unchecked Sendable {
        let folder: URL
        var calls: [URL] = []
        var fails = false
        init(_ fixture: CacheFixture) throws { folder = try fixture.dir("FakeTrash") }
        func trash(_ url: URL) throws -> URL? {
            calls.append(url)
            if fails { throw CocoaError(.fileWriteNoPermission) }
            let destination = folder.appendingPathComponent(url.lastPathComponent)
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        }
    }

    @Test func emptiesTheFolderButKeepsItAndItsMarker() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Tool/a", bytes: 100_000)
        try fixture.file("Library/Caches/Tool/sub/b", bytes: 100_000)
        try fixture.file("Library/Caches/Tool/CACHEDIR.TAG", bytes: 43)
        let target = fixture.target(.libraryCaches, "Tool")
        let measured = FileTreeWalker.measure(target.removableEntries()).bytes
        let report = try #require(await run(cleaner(fixture), [item(fixture, target)], .deletePermanently))
        #expect(report.results.first?.status == .cleaned)
        #expect(report.removedBytes == measured)
        #expect(fixture.exists("Library/Caches/Tool"))
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.url.path) == ["CACHEDIR.TAG"])
        #expect(report.freeSpaceChange != nil)
    }

    @Test func removesSymlinksInsideButNotWhatTheyPointTo() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Documents/precious", bytes: 1000)
        try fixture.file("Library/Caches/Tool/a")
        try fixture.symlink("Library/Caches/Tool/docs", to: fixture.url("Documents"))
        _ = await run(cleaner(fixture), [item(fixture, fixture.target(.libraryCaches, "Tool"))], .deletePermanently)
        #expect(!fixture.exists("Library/Caches/Tool/docs"))
        #expect(fixture.exists("Documents/precious"))
    }

    @Test func refusesASymlinkedCacheFolder() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Documents/precious")
        try fixture.symlink("Library/Caches/Tool", to: fixture.url("Documents"))
        let report = try #require(await run(
            cleaner(fixture), [item(fixture, fixture.target(.libraryCaches, "Tool"))], .deletePermanently))
        #expect(report.results.first?.status == .refused(.symlinkInPath))
        #expect(fixture.exists("Documents/precious"))
    }

    @Test func refusesUserDataEvenIfAskedDirectly() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Application Support/Notion/IndexedDB/db")
        let target = fixture.target(.applicationSupport, "Notion", "IndexedDB")
        let report = try #require(await run(cleaner(fixture), [item(fixture, target)], .deletePermanently))
        #expect(report.results.first?.status == .refused(.protectedName("IndexedDB")))
        #expect(fixture.exists("Library/Application Support/Notion/IndexedDB/db"))
    }

    @Test func reportsFilesItCannotRemove() async throws {
        let fixture = try CacheFixture()
        let stuck = try fixture.file("Library/Caches/Tool/stuck")
        try fixture.file("Library/Caches/Tool/fine")
        chflags(stuck.path, UInt32(UF_IMMUTABLE))
        let report = try #require(await run(
            cleaner(fixture), [item(fixture, fixture.target(.libraryCaches, "Tool"))], .deletePermanently))
        let result = try #require(report.results.first)
        #expect(result.status == .partial)
        #expect(result.failures.count == 1)
        #expect(fixture.exists("Library/Caches/Tool/stuck"))
        #expect(!fixture.exists("Library/Caches/Tool/fine"))
    }

    @Test func skipsCachesOfRunningApps() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Tool/a")
        let owned = item(fixture, owner: CacheOwner(name: "Tool", bundleIDs: ["com.tool"]),
                         fixture.target(.libraryCaches, "Tool"))
        let report = try #require(await run(cleaner(fixture, inUse: true), [owned], .deletePermanently))
        #expect(report.results.first?.status == .skippedInUse)
        #expect(fixture.exists("Library/Caches/Tool/a"))
    }

    @Test func leavesOtherItemsFoldersAlone() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Google/Chrome/Default/Cache/data")
        try fixture.file("Library/Caches/Google/Chrome-headless/blob")
        let generic = CacheTarget(base: .libraryCaches, relativePath: ["Google"], home: fixture.home,
                                  excluding: [fixture.url("Library/Caches/Google/Chrome")])
        _ = await run(cleaner(fixture), [item(fixture, generic)], .deletePermanently)
        #expect(fixture.exists("Library/Caches/Google/Chrome/Default/Cache/data"))
        #expect(!fixture.exists("Library/Caches/Google/Chrome-headless"))
    }

    @Test func trashModeMovesEverythingIntoOneFolder() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Tool/a", bytes: 10_000)
        try fixture.file("Library/Caches/Tool/sub/b", bytes: 10_000)
        try fixture.file(".cache/other/c", bytes: 10_000)
        let fake = try FakeTrash(fixture)
        let items = [item(fixture, id: "one", fixture.target(.libraryCaches, "Tool")),
                     item(fixture, id: "two", fixture.target(.dotCache, "other"))]
        let report = try #require(await run(cleaner(fixture, trash: fake.trash), items, .moveToTrash))
        #expect(fake.calls.count == 1)
        #expect(fake.calls.first?.lastPathComponent.hasPrefix("Fresh Cleanup ") == true)
        #expect(report.results.allSatisfy { $0.status == .cleaned })
        #expect(report.removedBytes >= 30_000)
        #expect(report.trashedFolder != nil)
        #expect(report.freeSpaceChange == nil)
        // The cache folders stay, empty; their contents are in the (fake) Trash with their original paths.
        #expect(fixture.exists("Library/Caches/Tool"))
        #expect(!fixture.exists("Library/Caches/Tool/a"))
        let trashed = try #require(report.trashedFolder)
        let names = try FileManager.default.subpathsOfDirectory(atPath: trashed.path)
        #expect(names.contains { $0.hasSuffix("Library/Caches/Tool/sub/b") })
        #expect(names.contains { $0.hasSuffix(".cache/other/c") })
    }

    @Test func trashFailurePutsEverythingBack() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Tool/a", bytes: 10_000)
        let fake = try FakeTrash(fixture)
        fake.fails = true
        let report = try #require(await run(
            cleaner(fixture, trash: fake.trash), [item(fixture, fixture.target(.libraryCaches, "Tool"))], .moveToTrash))
        #expect(fixture.exists("Library/Caches/Tool/a"))
        #expect(report.trashedFolder == nil)
        #expect(report.removedBytes == 0)
        #expect(report.results.first?.status == .partial)
        // The staging folder is gone, and nothing else was deleted.
        let own = fixture.url("Library/Caches/com.devfoundry.fresh")
        #expect(((try? FileManager.default.contentsOfDirectory(atPath: own.path)) ?? []).isEmpty)
    }

    @Test func plannedRemovalsListsWithoutDeleting() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Tool/a")
        try fixture.file("Library/Application Support/Notion/IndexedDB/db")
        let planned = cleaner(fixture).plannedRemovals([
            item(fixture, id: "tool", fixture.target(.libraryCaches, "Tool")),
            item(fixture, id: "bad", fixture.target(.applicationSupport, "Notion", "IndexedDB")),
        ])
        #expect(planned.first { $0.id == "tool" }?.entries.map(\.lastPathComponent) == ["a"])
        #expect(planned.first { $0.id == "bad" }?.entries.isEmpty == true)
        #expect(fixture.exists("Library/Caches/Tool/a"))
    }
}

@Suite struct CacheScannerTests {
    @Test func streamsDiscoveryThenSizes() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/One/a", bytes: 10_000)
        try fixture.file("Library/Caches/Two/b", bytes: 20_000)
        var discovered = 0
        var sized: [CacheItem.ID: CacheSize] = [:]
        var finished = false
        for await event in CacheScanner(environment: fixture.environment).scan() {
            switch event {
            case .discovered(let result): discovered = result.items.count
            case .sized(let id, let size): sized[id] = size
            case .finished: finished = true
            }
        }
        #expect(discovered == 2)
        #expect(finished)
        #expect((sized["libraryCaches/Two"]?.bytes ?? 0) >= 20_000)
    }

    @Test func stopsWhenTheReaderIsCancelled() async throws {
        let fixture = try CacheFixture()
        // Enough files that measuring takes milliseconds, so the cancel lands mid-scan.
        for folder in 0..<5 {
            let dir = try fixture.dir("Library/Caches/C\(folder)")
            for file in 0..<700 {
                FileManager.default.createFile(atPath: dir.appendingPathComponent("f\(file)").path, contents: Data([1]))
            }
        }
        let scanner = CacheScanner(environment: fixture.environment, concurrency: 1)
        let task = Task {
            var events: [String] = []
            for await event in scanner.scan() {
                switch event {
                case .discovered:
                    events.append("discovered")
                    withUnsafeCurrentTask { $0?.cancel() }
                case .sized: events.append("sized")
                case .finished: events.append("finished")
                }
            }
            return events
        }
        let events = await task.value
        #expect(events.first == "discovered")
        #expect(!events.contains("finished"))
        #expect(events.filter { $0 == "sized" }.count < 5)
    }
}
