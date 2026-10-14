import Foundation
import Testing
@testable import MemoryCore

@Suite struct CacheDiscoveryTests {
    private func discover(_ fixture: CacheFixture) -> CacheDiscovery.Result {
        CacheDiscovery(environment: fixture.environment, appIndex: AppIndex(scanning: [fixture.url("Applications")]))
            .discover()
    }

    private func item(_ result: CacheDiscovery.Result, _ id: String) -> CacheItem? {
        result.items.first { $0.id == id }
    }

    private func paths(_ item: CacheItem?, relativeTo fixture: CacheFixture) -> Set<String> {
        Set((item?.targets ?? []).map { String($0.url.path.dropFirst(fixture.home.path.count + 1)) })
    }

    @Test func listsEachCacheFolderAndIgnoresFiles() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/SomeApp/data")
        try fixture.file("Library/Caches/stray.lock")
        try fixture.file(".cache/tool/blob")
        try fixture.file("Library/Logs/SomeApp/log.txt")
        let result = discover(fixture)
        #expect(item(result, "libraryCaches/SomeApp")?.category == .other)
        #expect(item(result, "dotCache/tool")?.category == .developer)
        #expect(item(result, "libraryLogs/SomeApp")?.category == .logs)
        #expect(!result.items.contains { $0.id.contains("stray") })
    }

    @Test func appleCachesAreSystemAndDaemonCachesHidden() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/com.apple.helpd/x")
        try fixture.file("Library/Caches/com.apple.bird/x")
        try fixture.file("Library/Caches/com.devfoundry.fresh/x")
        let result = discover(fixture)
        let helpd = try #require(item(result, "libraryCaches/com.apple.helpd"))
        #expect(helpd.category == .system)
        #expect(!helpd.isRecommended)
        #expect(item(result, "libraryCaches/com.apple.bird") == nil)
        #expect(item(result, "libraryCaches/com.devfoundry.fresh") == nil)
    }

    @Test func electronAppsOnlyGiveUpTheirCacheFolders() throws {
        let fixture = try CacheFixture()
        let app = "Library/Application Support/Notion"
        for folder in ["Cache", "Code Cache", "GPUCache", "IndexedDB", "Local Storage", "blob_storage",
                       "Service Worker/CacheStorage", "Service Worker/Database", "Service Worker/ScriptCache",
                       "Partitions/notion/Cache", "Partitions/notion/IndexedDB", "Partitions/notion/Local Storage"] {
            try fixture.file("\(app)/\(folder)/data")
        }
        let result = discover(fixture)
        let web = item(result, "appsupport/Notion")
        #expect(paths(web, relativeTo: fixture) == [
            "\(app)/Cache", "\(app)/Code Cache", "\(app)/GPUCache", "\(app)/Partitions/notion/Cache",
        ])
        #expect(web?.isRecommended == true)
        #expect(web?.owner?.bundleIDs == ["notion.id"])
        #expect(web?.owner?.singletonLocks.first?.lastPathComponent == "SingletonLock")

        let offline = item(result, "appsupport/Notion#offline")
        #expect(paths(offline, relativeTo: fixture) == [
            "\(app)/Service Worker/CacheStorage", "\(app)/Service Worker/ScriptCache",
        ])
        #expect(offline?.isRecommended == false)

        let everything = result.items.flatMap(\.targets).map(\.url.path)
        for data in ["IndexedDB", "Local Storage", "blob_storage", "Database"] {
            #expect(!everything.contains { $0.contains("/\(data)") }, "never targets \(data)")
        }
    }

    @Test func foldersWithoutChromiumMarkersAreLeftAlone() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Application Support/SomeApp/Cache/data")
        try fixture.file("Library/Application Support/SomeApp/Documents/important")
        #expect(discover(fixture).items.isEmpty)
    }

    @Test func neverLooksIntoPrivacyProtectedFolders() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Containers/com.example/Data/Library/Caches/x")
        try fixture.file("Library/Group Containers/group.example/Library/Caches/x")
        try fixture.file("Library/Application Support/AddressBook/Code Cache/x")
        try fixture.file("Library/Application Support/com.apple.foo/GPUCache/x")
        try fixture.file("Library/Caches/SomeApp/x")
        _ = discover(fixture)
        let touched = fixture.accessedPaths
        #expect(!touched.isEmpty)
        for forbidden in ["/Library/Containers", "/Library/Group Containers", "/AddressBook", "/com.apple.foo"] {
            #expect(!touched.contains { $0.contains(forbidden) }, "touched \(forbidden)")
        }
    }

    @Test func knownCachesClaimTheirFoldersFirst() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Google/Chrome/Default/Cache/data", bytes: 50_000)
        try fixture.file("Library/Caches/Google/Chrome-headless/blob", bytes: 20_000)
        try fixture.file("Library/Application Support/Google/Chrome/Default/Code Cache/js", bytes: 1000)
        try fixture.file("Library/Application Support/Google/Chrome/Default/IndexedDB/db", bytes: 1000)
        let result = discover(fixture)
        let chrome = try #require(item(result, "known/chrome"))
        #expect(paths(chrome, relativeTo: fixture) == [
            "Library/Caches/Google/Chrome", "Library/Application Support/Google/Chrome/Default/Code Cache",
        ])
        #expect(chrome.category == .browsers)
        let google = try #require(item(result, "libraryCaches/Google"))
        #expect(google.targets[0].removableEntries().map(\.lastPathComponent) == ["Chrome-headless"])
    }

    @Test func folderHoldingOnlyAKnownCacheIsNotListed() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Google/Chrome/Default/Cache/data")
        #expect(item(discover(fixture), "libraryCaches/Google") == nil)
    }

    @Test func sizesAddUpWithoutDoubleCounting() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Google/Chrome/Default/Cache/a", bytes: 300_000)
        try fixture.file("Library/Caches/Google/Chrome-headless/b", bytes: 200_000)
        try fixture.file("Library/Caches/Homebrew/c", bytes: 100_000)
        try fixture.file("Library/Caches/Other/d", bytes: 50_000)
        let result = discover(fixture)
        let itemTotal = result.items.reduce(UInt64(0)) { $0 + CacheScanner.size(of: $1).bytes }
        let caches = fixture.url("Library/Caches")
        let children = try FileManager.default.contentsOfDirectory(atPath: caches.path).map { caches.appendingPathComponent($0) }
        // Items cover each folder's contents (not the folders themselves), so allow for folder entries.
        let whole = FileTreeWalker.measure(children).bytes
        #expect(itemTotal <= whole)
        #expect(whole - itemTotal < 64 * 1024)
        #expect(itemTotal >= 650_000)
    }

    @Test func catalogAdvisoriesAndOwners() throws {
        let fixture = try CacheFixture()
        try fixture.file(".npm/_cacache/index", bytes: 1000)
        try fixture.file(".npm/_npx/abc/pkg", bytes: 1000)
        try fixture.file("Library/Caches/ms-playwright-mcp/mcp-chrome/Default/Cookies", bytes: 1000)
        try fixture.file(".cache/uv/wheels", bytes: 1000)
        let result = discover(fixture)
        #expect(item(result, "known/npm")?.isRecommended == true)
        #expect(item(result, "known/npx")?.isRecommended == false)
        #expect(item(result, "known/playwright-mcp")?.isRecommended == false)
        #expect(item(result, "known/uv")?.isRecommended == true)
        #expect(item(result, "known/uv")?.owner?.processNames == ["uv"])
        // Claimed by the catalog, so not listed again generically.
        #expect(item(result, "dotCache/uv") == nil)
    }

    @Test func reportsUnreadableFolders() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Locked/x")
        chmod(fixture.url("Library/Caches/Locked").path, 0)
        let result = discover(fixture)
        #expect(item(result, "libraryCaches/Locked") == nil)
        #expect(result.noAccess.map(\.lastPathComponent) == ["Locked"])
    }

    @Test func ignoresSymlinkedCacheFolders() throws {
        let fixture = try CacheFixture()
        try fixture.file("Documents/important")
        try fixture.symlink("Library/Caches/Sneaky", to: fixture.url("Documents"))
        #expect(discover(fixture).items.isEmpty)
    }
}
