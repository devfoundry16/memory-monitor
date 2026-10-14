import Foundation
import Testing
@testable import MemoryCore

@Suite struct CachePathPolicyTests {
    private func refusal(_ result: Result<URL, CleanRefusal>) -> CleanRefusal? {
        if case .failure(let refusal) = result { return refusal }
        return nil
    }

    @Test func acceptsARealCacheFolder() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Homebrew/bottle.tar.gz")
        let result = CachePathPolicy(environment: fixture.environment).validate(fixture.target(.libraryCaches, "Homebrew"))
        // The fixture lives under /var, a symlink to /private/var; resolving both sides still matches.
        #expect(try result.get().path.hasSuffix("/Library/Caches/Homebrew"))
    }

    @Test func refusesDotDotAndEmptyComponents() throws {
        let fixture = try CacheFixture()
        let policy = CachePathPolicy(environment: fixture.environment)
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, ".."))) == .invalidPath)
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, "a", "..", "b"))) == .invalidPath)
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, ""))) == .invalidPath)
        #expect(refusal(policy.validate(CacheTarget(base: .libraryCaches, relativePath: [], home: fixture.home))) == .invalidPath)
    }

    @Test func refusesATargetWhoseURLDoesNotMatchItsPath() throws {
        let fixture = try CacheFixture()
        try fixture.dir("Library/Caches/Homebrew")
        var target = fixture.target(.libraryCaches, "Homebrew")
        target.url = fixture.url("Documents")
        #expect(refusal(CachePathPolicy(environment: fixture.environment).validate(target)) == .invalidPath)
    }

    @Test func refusesSymlinkedRoot() throws {
        let fixture = try CacheFixture()
        let precious = try fixture.dir("Documents")
        try fixture.symlink("Library/Caches/Evil", to: precious)
        let result = CachePathPolicy(environment: fixture.environment).validate(fixture.target(.libraryCaches, "Evil"))
        #expect(refusal(result) == .symlinkInPath)
    }

    @Test func refusesSymlinkPartwayDown() throws {
        let fixture = try CacheFixture()
        try fixture.dir("Documents/Inner")
        try fixture.symlink("Library/Caches/Google", to: fixture.url("Documents"))
        let result = CachePathPolicy(environment: fixture.environment).validate(fixture.target(.libraryCaches, "Google", "Inner"))
        #expect(refusal(result) == .symlinkInPath)
    }

    @Test func allowsASymlinkedBase() throws {
        let fixture = try CacheFixture()
        let elsewhere = try fixture.dir("Volumes/Other/cache")
        try fixture.dir("Volumes/Other/cache/uv")
        try fixture.symlink(".cache", to: elsewhere)
        #expect(throws: Never.self) {
            try CachePathPolicy(environment: fixture.environment).validate(fixture.target(.dotCache, "uv")).get()
        }
    }

    @Test func refusesUserDataInsideAppSupport() throws {
        let fixture = try CacheFixture()
        try fixture.dir("Library/Application Support/Notion/IndexedDB")
        try fixture.dir("Library/Application Support/Notion/Service Worker/Database")
        try fixture.dir("Library/Application Support/Notion/IndexedDB/Cache")
        let policy = CachePathPolicy(environment: fixture.environment)
        #expect(refusal(policy.validate(fixture.target(.applicationSupport, "Notion", "IndexedDB"))) == .protectedName("IndexedDB"))
        #expect(refusal(policy.validate(fixture.target(.applicationSupport, "Notion", "Service Worker", "Database")))
            == .protectedName("Database"))
        // Even a cache-named folder inside user data is refused.
        #expect(refusal(policy.validate(fixture.target(.applicationSupport, "Notion", "IndexedDB", "Cache")))
            == .protectedName("IndexedDB"))
    }

    @Test func appSupportNeedsAKnownCacheLeaf() throws {
        let fixture = try CacheFixture()
        try fixture.dir("Library/Application Support/Notion/Cache")
        try fixture.dir("Library/Application Support/Notion/Partitions/notion/Code Cache")
        try fixture.dir("Library/Application Support/Notion/Service Worker/CacheStorage")
        try fixture.dir("Library/Application Support/Notion/notes")
        try fixture.dir("Library/Application Support/com.apple.foo/Cache")
        try fixture.dir("Library/Application Support/AddressBook/Cache")
        let policy = CachePathPolicy(environment: fixture.environment)
        #expect(throws: Never.self) { try policy.validate(fixture.target(.applicationSupport, "Notion", "Cache")).get() }
        #expect(throws: Never.self) {
            try policy.validate(fixture.target(.applicationSupport, "Notion", "Partitions", "notion", "Code Cache")).get()
        }
        #expect(throws: Never.self) {
            try policy.validate(fixture.target(.applicationSupport, "Notion", "Service Worker", "CacheStorage")).get()
        }
        #expect(refusal(policy.validate(fixture.target(.applicationSupport, "Notion", "notes"))) == .outsideAllowedFolders)
        #expect(refusal(policy.validate(fixture.target(.applicationSupport, "Notion"))) == .outsideAllowedFolders)
        #expect(refusal(policy.validate(fixture.target(.applicationSupport, "com.apple.foo", "Cache"))) == .outsideAllowedFolders)
        #expect(refusal(policy.validate(fixture.target(.applicationSupport, "AddressBook", "Cache"))) == .outsideAllowedFolders)
    }

    @Test func homeOnlyAllowsListedPaths() throws {
        let fixture = try CacheFixture()
        try fixture.dir(".npm/_cacache")
        try fixture.dir(".ssh")
        try fixture.dir("Documents")
        let policy = CachePathPolicy(environment: fixture.environment)
        #expect(throws: Never.self) { try policy.validate(fixture.target(.home, ".npm", "_cacache")).get() }
        #expect(refusal(policy.validate(fixture.target(.home, ".ssh"))) == .outsideAllowedFolders)
        #expect(refusal(policy.validate(fixture.target(.home, "Documents"))) == .outsideAllowedFolders)
    }

    @Test func refusesHiddenAndOwnCaches() throws {
        let fixture = try CacheFixture()
        try fixture.dir("Library/Caches/com.apple.bird")
        try fixture.dir("Library/Caches/com.devfoundry.fresh")
        try fixture.dir("Library/Caches/.hidden")
        let policy = CachePathPolicy(environment: fixture.environment)
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, "com.apple.bird"))) == .protectedName("com.apple.bird"))
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, "com.devfoundry.fresh"))) == .outsideAllowedFolders)
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, ".hidden"))) == .invalidPath)
    }

    @Test func refusesFilesAndMissingFolders() throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/loose-file")
        let policy = CachePathPolicy(environment: fixture.environment)
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, "loose-file"))) == .notADirectory)
        #expect(refusal(policy.validate(fixture.target(.libraryCaches, "nope"))) == .missing)
    }
}
