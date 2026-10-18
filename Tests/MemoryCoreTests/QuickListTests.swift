import Foundation
import Testing
@testable import MemoryCore

/// Checks paths only: nothing here is ever moved to the Trash.
@Suite struct TrashPolicyTests {
    let home = URL(fileURLWithPath: "/Users/someone")
    let fresh = URL(fileURLWithPath: "/Applications/Fresh.app")

    func refusal(_ path: String) -> String? {
        TrashPolicy.refusal(for: URL(fileURLWithPath: path), home: home, ownBundle: fresh)
    }

    @Test func refusesSystemLocations() {
        #expect(refusal("/System/Applications/Safari.app") != nil)
        #expect(refusal("/Library/Application Support") != nil)
        #expect(refusal("/usr/local/bin") != nil)
        #expect(refusal("/private/etc") != nil)
        #expect(refusal("/private/tmp") != nil)
        // Resolved forms of the same places.
        #expect(refusal("/etc") != nil)
        #expect(refusal("/var/db") != nil)
        #expect(refusal("/tmp") != nil)
    }

    @Test func refusesContainersAndHome() {
        #expect(refusal("/") != nil)
        #expect(refusal("/Applications") != nil)
        #expect(refusal("/Users") != nil)
        #expect(refusal("/Users/someone") != nil)
        #expect(refusal("/Users/someone/Documents") != nil)
        #expect(refusal("/Users/someone/Library") != nil)
        #expect(refusal("/Volumes") != nil)
        #expect(refusal("/Volumes/Backup") != nil)
    }

    @Test func refusesFreshAndWhatHoldsIt() {
        #expect(refusal("/Applications/Fresh.app") != nil)
        let nested = TrashPolicy.refusal(
            for: URL(fileURLWithPath: "/Users/someone/Tools"), home: home,
            ownBundle: URL(fileURLWithPath: "/Users/someone/Tools/Fresh.app"))
        #expect(nested != nil)
    }

    @Test func allowsOrdinaryAppsAndFolders() {
        #expect(refusal("/Applications/Slack.app") == nil)
        #expect(refusal("/Applications/Utilities/Some Tool.app") == nil)
        #expect(refusal("/Users/someone/Projects/old") == nil)
        #expect(refusal("/Users/someone/Library/Application Support/Old App") == nil)
        #expect(refusal("/Users/someone/Documentsarchive") == nil)
        #expect(refusal("/Volumes/Backup/old") == nil)
        #expect(refusal("/private/tmp/scratch") == nil)
    }

    @Test func symlinkIntoSystemIsRefused() throws {
        let fixture = try CacheFixture()
        let link = fixture.home.appendingPathComponent("looks-harmless")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: URL(fileURLWithPath: "/System/Applications"))
        #expect(TrashPolicy.refusal(for: link, home: fixture.home, ownBundle: fresh) != nil)

        let folder = fixture.home.appendingPathComponent("Projects/old")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        #expect(TrashPolicy.refusal(for: folder, home: fixture.home, ownBundle: fresh) == nil)
    }
}

@Suite struct InstalledAppsTests {
    @Test func listsAppsSortedWithoutDuplicates() throws {
        let fixture = try CacheFixture()
        let apps = fixture.home.appendingPathComponent("Applications")
        for (name, id) in [("zeta", "com.example.zeta"), ("Alpha", "com.example.alpha"), ("beta", "com.example.beta")] {
            let contents = apps.appendingPathComponent("\(name).app/Contents")
            try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
            try (["CFBundleIdentifier": id] as NSDictionary).write(to: contents.appendingPathComponent("Info.plist"))
        }
        // Scanning the same folder twice must not list anything twice.
        let index = AppIndex(scanning: [apps, apps])
        #expect(index.apps.map(\.name) == ["Alpha", "beta", "zeta"])
        #expect(index.apps.first?.bundleID == "com.example.alpha")
    }
}

@Suite struct QuickItemTests {
    @Test func namesAndRoundTrip() throws {
        let app = QuickItem(kind: .app, path: "/Applications/Slack.app", bundleID: "com.tinyspeck.slackmacgap")
        let folder = QuickItem(kind: .folder, path: "/Users/someone/Projects")
        #expect(app.name == "Slack")
        #expect(folder.name == "Projects")
        let decoded = try JSONDecoder().decode([QuickItem].self, from: JSONEncoder().encode([app, folder]))
        #expect(decoded == [app, folder])
    }
}
