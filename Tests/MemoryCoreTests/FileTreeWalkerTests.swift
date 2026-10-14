import Foundation
import Testing
@testable import MemoryCore

@Suite struct FileTreeWalkerTests {
    @Test func countsAllocatedSpace() throws {
        let fixture = try CacheFixture()
        try fixture.file("tree/a", bytes: 10_000)
        try fixture.file("tree/sub/b", bytes: 5_000)
        let size = FileTreeWalker.measure([fixture.url("tree")])
        #expect(size.files == 2)
        #expect(size.bytes >= 15_000)
        #expect(size.bytes < 15_000 + 64 * 1024) // block rounding plus two folders
        #expect(size.unreadable == 0)
    }

    @Test func countsHardLinksOnce() throws {
        let fixture = try CacheFixture()
        let original = try fixture.file("tree/a", bytes: 100_000)
        try FileManager.default.linkItem(at: original, to: fixture.url("tree/b"))
        let size = FileTreeWalker.measure([fixture.url("tree")])
        #expect(size.files == 1)
        #expect(size.bytes < 200_000)
    }

    @Test func doesNotFollowSymlinks() throws {
        let fixture = try CacheFixture()
        try fixture.file("outside/big", bytes: 1_000_000)
        try fixture.dir("tree")
        try fixture.symlink("tree/link", to: fixture.url("outside"))
        let size = FileTreeWalker.measure([fixture.url("tree")])
        #expect(size.bytes < 100_000)
    }

    @Test func reportsUnreadableFolders() throws {
        let fixture = try CacheFixture()
        try fixture.file("tree/locked/secret", bytes: 1000)
        chmod(fixture.url("tree/locked").path, 0)
        let size = FileTreeWalker.measure([fixture.url("tree")])
        #expect(size.unreadable == 1)
    }

    @Test func removesTreesButNotSymlinkTargets() throws {
        let fixture = try CacheFixture()
        try fixture.file("outside/keep", bytes: 1000)
        try fixture.file("tree/a", bytes: 10_000)
        try fixture.file("tree/sub/deeper/b", bytes: 10_000)
        try fixture.symlink("tree/sub/link", to: fixture.url("outside"))
        let measured = FileTreeWalker.measure([fixture.url("tree/a"), fixture.url("tree/sub")])
        let removal = FileTreeWalker.remove([fixture.url("tree/a"), fixture.url("tree/sub")])
        #expect(removal.failures.isEmpty)
        #expect(!fixture.exists("tree/a"))
        #expect(!fixture.exists("tree/sub"))
        #expect(fixture.exists("tree"))
        #expect(fixture.exists("outside/keep"))
        #expect(removal.removedBytes == measured.bytes)
    }

    @Test func keepsGoingPastFilesItCannotRemove() throws {
        let fixture = try CacheFixture()
        let stuck = try fixture.file("tree/stuck", bytes: 1000)
        try fixture.file("tree/other", bytes: 1000)
        chflags(stuck.path, UInt32(UF_IMMUTABLE))
        let removal = FileTreeWalker.remove([fixture.url("tree")])
        #expect(fixture.exists("tree/stuck"))
        #expect(!fixture.exists("tree/other"))
        #expect(removal.failures.count == 1)
        #expect(removal.failures.first?.path.hasSuffix("tree/stuck") == true)
    }

    @Test func stopsWhenCancelled() throws {
        let fixture = try CacheFixture()
        for i in 0..<1200 { try fixture.file("tree/f\(i)", bytes: 10) }
        let removal = FileTreeWalker.remove([fixture.url("tree")], isCancelled: { true })
        #expect(removal.cancelled)
        #expect(fixture.exists("tree"))
    }
}
