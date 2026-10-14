import Foundation
import Testing
@testable import MemoryCore

@Suite struct AppIndexTests {
    private func index(_ fixture: CacheFixture) throws -> AppIndex {
        try fixture.app("Linear", bundleID: "com.linear")
        try fixture.app("Notion", bundleID: "notion.id")
        try fixture.app("ChatGPT", bundleID: "com.openai.codex")
        try fixture.app("Discord", bundleID: "com.hnc.Discord")
        try fixture.app("iTerm", bundleID: "com.googlecode.iterm2")
        return AppIndex(scanning: [fixture.url("Applications")])
    }

    @Test func resolvesByBundleIDFirst() throws {
        let index = try index(CacheFixture())
        // Named after the app, not the folder: ChatGPT's bundle ID is com.openai.codex.
        #expect(index.owner(forFolderName: "com.openai.codex")?.name == "ChatGPT")
        #expect(index.owner(forFolderName: "com.googlecode.iterm2")?.bundleIDs == ["com.googlecode.iterm2"])
    }

    @Test func stripsKnownSuffixes() throws {
        let index = try index(CacheFixture())
        #expect(index.owner(forFolderName: "com.linear.ShipIt")?.name == "Linear")
        #expect(index.owner(forFolderName: "notion-updater")?.bundleIDs == ["notion.id"])
    }

    @Test func usesTheCatalogForMismatchedNames() throws {
        let index = try index(CacheFixture())
        let code = try #require(index.owner(forFolderName: "Code"))
        #expect(code.bundleIDs == ["com.microsoft.VSCode"])
        #expect(code.name == "Visual Studio Code") // not installed in the fixture: catalog name
        #expect(index.owner(forFolderName: "discord")?.name == "Discord")
    }

    @Test func matchesNamesLoosely() throws {
        let index = try index(CacheFixture())
        #expect(index.owner(forFolderName: "linear")?.bundleIDs == ["com.linear"])
        #expect(index.owner(forFolderName: "unknown-thing") == nil)
    }
}

@Suite struct RunningProbeTests {
    @Test func matchesBundleIDsAndProcessNames() {
        let app = CacheOwner(name: "Linear", bundleIDs: ["com.linear"])
        let tool = CacheOwner(name: "uv", processNames: ["uv"])
        #expect(RunningProbe.isRunning(app, runningBundleIDs: ["com.linear"], processNames: []))
        #expect(!RunningProbe.isRunning(app, runningBundleIDs: ["com.other"], processNames: ["Linear"]))
        #expect(RunningProbe.isRunning(tool, runningBundleIDs: [], processNames: ["uv"]))
        #expect(!RunningProbe.isRunning(tool, runningBundleIDs: [], processNames: []))
    }

    @Test func readsChromiumSingletonLock() throws {
        let fixture = try CacheFixture()
        let live = fixture.url("live/SingletonLock")
        let dead = fixture.url("dead/SingletonLock")
        try fixture.dir("live")
        try fixture.dir("dead")
        try FileManager.default.createSymbolicLink(atPath: live.path, withDestinationPath: "my-mac.local-\(getpid())")
        try FileManager.default.createSymbolicLink(atPath: dead.path, withDestinationPath: "my-mac.local-99999999")
        #expect(RunningProbe.lockHolderPID(live) == getpid())
        #expect(RunningProbe.isRunning(CacheOwner(name: "A", singletonLocks: [live]), runningBundleIDs: [], processNames: []))
        #expect(!RunningProbe.isRunning(CacheOwner(name: "B", singletonLocks: [dead]), runningBundleIDs: [], processNames: []))
        #expect(!RunningProbe.isRunning(
            CacheOwner(name: "C", singletonLocks: [fixture.url("none/SingletonLock")]), runningBundleIDs: [], processNames: []))
    }
}
