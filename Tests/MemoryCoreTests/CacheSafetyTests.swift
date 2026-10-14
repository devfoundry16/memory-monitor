import Foundation
import Testing
@testable import MemoryCore

/// Edge cases from the safety review. All in throwaway fixture homes.
@Suite struct CacheSafetyTests {
    private func cleaner(_ fixture: CacheFixture, trash: CacheCleaner.Trasher? = nil) -> CacheCleaner {
        CacheCleaner(environment: fixture.environment, trash: trash ?? { _ in throw CocoaError(.featureUnsupported) },
                     isInUse: { _ in false }, settleDelay: .zero)
    }

    private func run(_ cleaner: CacheCleaner, _ items: [CacheItem], _ mode: CleanMode,
                     control: CleanControl = CleanControl()) async -> CleanReport? {
        for await event in cleaner.clean(items, mode: mode, control: control) {
            if case .done(let report) = event { return report }
        }
        return nil
    }

    private func item(_ id: String = "test", _ targets: CacheTarget...) -> CacheItem {
        CacheItem(id: id, name: id, category: .other, targets: targets)
    }

    @discardableResult
    private func hdiutil(_ arguments: [String]) throws -> Int32 {
        let process = try Process.run(URL(fileURLWithPath: "/usr/bin/hdiutil"), arguments: arguments)
        process.waitUntilExit()
        return process.terminationStatus
    }

    @Test func neverCrossesIntoAVolumeMountedInsideACache() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Tool/a", bytes: 10_000)
        let mountPoint = try fixture.dir("Library/Caches/Tool/mnt")
        let image = fixture.url("disk.dmg")
        try #require(try hdiutil(["create", "-quiet", "-size", "2m", "-fs", "HFS+", "-volname", "FreshTest", image.path]) == 0)
        try #require(try hdiutil(["attach", "-quiet", "-nobrowse", "-mountpoint", mountPoint.path, image.path]) == 0)
        defer { _ = try? hdiutil(["detach", "-quiet", "-force", mountPoint.path]) }
        try Data(repeating: 1, count: 1000).write(to: mountPoint.appendingPathComponent("remote.txt"))

        let target = fixture.target(.libraryCaches, "Tool")
        #expect(target.removableEntries().map(\.lastPathComponent) == ["a"])
        let mounted = fixture.target(.libraryCaches, "Tool", "mnt")
        if case .failure(let refusal) = CachePathPolicy(environment: fixture.environment).validate(mounted) {
            #expect(refusal == .otherVolume)
        } else {
            Issue.record("a mount point must not validate")
        }

        _ = await run(cleaner(fixture), [item("tool", target)], .deletePermanently)
        #expect(!fixture.exists("Library/Caches/Tool/a"))
        #expect(FileManager.default.fileExists(atPath: mountPoint.appendingPathComponent("remote.txt").path))
    }

    @Test func keepsUserDataFoundDeepInsideAGenericCache() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/SomeTool/profile/Default/Cookies", bytes: 5000)
        try fixture.file("Library/Caches/SomeTool/profile/Default/IndexedDB/db", bytes: 5000)
        try fixture.file("Library/Caches/SomeTool/profile/Default/Cache/blob", bytes: 50_000)
        try fixture.file("Library/Caches/SomeTool/other", bytes: 50_000)
        let target = fixture.target(.libraryCaches, "SomeTool")

        let measured = FileTreeWalker.measure(target.removableEntries()).bytes
        let report = try #require(await run(cleaner(fixture), [item("tool", target)], .deletePermanently))
        #expect(fixture.exists("Library/Caches/SomeTool/profile/Default/Cookies"))
        #expect(fixture.exists("Library/Caches/SomeTool/profile/Default/IndexedDB/db"))
        #expect(!fixture.exists("Library/Caches/SomeTool/profile/Default/Cache"))
        #expect(!fixture.exists("Library/Caches/SomeTool/other"))
        // Kept data isn't counted as cache, and keeping it isn't a failure.
        #expect(report.results.first?.status == .cleaned)
        #expect(report.removedBytes == measured)
        #expect(measured < 120_000)
    }

    @Test func somethingAlreadyGoneIsNotAFailure() {
        let removal = FileTreeWalker.remove([URL(fileURLWithPath: "/nonexistent-\(UUID().uuidString)")])
        #expect(removal.failures.isEmpty)
    }

    @Test func unreadableFolderIsReportedNotCleaned() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/Locked/x")
        chmod(fixture.url("Library/Caches/Locked").path, 0)
        let report = try #require(await run(
            cleaner(fixture), [item("locked", fixture.target(.libraryCaches, "Locked"))], .deletePermanently))
        #expect(report.results.first?.status == .partial)
        #expect(report.results.first?.failures.first?.reason == "Couldn't read this folder")
    }

    @Test func stoppingStillProducesAReport() async throws {
        let fixture = try CacheFixture()
        try fixture.file("Library/Caches/One/a")
        try fixture.file("Library/Caches/Two/b")
        let control = CleanControl()
        control.stop()
        let report = try #require(await run(cleaner(fixture), [
            item("one", fixture.target(.libraryCaches, "One")), item("two", fixture.target(.libraryCaches, "Two")),
        ], .deletePermanently, control: control))
        #expect(report.results.map(\.status) == [.cancelled, .cancelled])
        #expect(fixture.exists("Library/Caches/One/a"))
    }

    @Test func eachTrashRunGetsItsOwnStagingFolder() async throws {
        let fixture = try CacheFixture()
        final class Calls: @unchecked Sendable { var urls: [URL] = [] }
        let calls = Calls()
        // A Trash that records the folder but leaves it in place, so a second run sees it.
        let keep: CacheCleaner.Trasher = { url in
            calls.urls.append(url)
            return url
        }
        for name in ["One", "Two"] {
            try fixture.file("Library/Caches/\(name)/a")
            _ = await run(cleaner(fixture, trash: keep), [item(name, fixture.target(.libraryCaches, name))], .moveToTrash)
        }
        #expect(calls.urls.count == 2)
        #expect(Set(calls.urls.map(\.path)).count == 2)
    }

    @Test func unknownDotCacheFoldersAreNotPreselected() throws {
        let fixture = try CacheFixture()
        try fixture.file(".cache/huggingface/token")
        let result = CacheDiscovery(environment: fixture.environment, appIndex: AppIndex(scanning: [])).discover()
        let item = try #require(result.items.first { $0.id == "dotCache/huggingface" })
        #expect(item.advisory?.isCaution == true)
        #expect(!item.isRecommended)
    }

    @Test func findsToolsRunByInterpreters() {
        #expect(RunningProbe.toolNames(fromArguments: ["node", "/opt/homebrew/bin/npm", "install"]).contains("npm"))
        #expect(RunningProbe.toolNames(
            fromArguments: ["node", "/opt/homebrew/lib/node_modules/npm/bin/npm-cli.js"]).contains("npm"))
        #expect(RunningProbe.toolNames(fromArguments: ["python3", "-m", "pip", "install", "x"]).contains("pip"))
        #expect(RunningProbe.toolNames(
            fromArguments: ["ruby", "/opt/homebrew/Library/Homebrew/brew.rb", "upgrade"]).contains("brew"))
        #expect(RunningProbe.toolNames(
            fromArguments: ["node", "/Users/x/.npm/_npx/abc/node_modules/.bin/mcp-server"])
                .contains(RunningProbe.npxPackageRunning))
        // A server running from _npx doesn't make npm's download cache busy.
        #expect(!RunningProbe.toolNames(
            fromArguments: ["node", "/Users/x/.npm/_npx/abc/node_modules/.bin/mcp-server"]).contains("npx"))
        #expect(RunningProbe.toolNames(fromArguments: ["node", "/opt/homebrew/bin/npx", "create-app"]).contains("npx"))
        #expect(RunningProbe.toolNames(
            fromArguments: ["java", "-cp", "x.jar", "org.gradle.launcher.daemon.bootstrap.GradleDaemon"]).contains("gradle"))
    }

    @Test func readsOwnCommandLine() throws {
        let arguments = try #require(RunningProbe.arguments(of: getpid()))
        #expect(arguments.first.map { CommandLine.arguments.first?.hasSuffix(($0 as NSString).lastPathComponent) ?? false }
            == true)
    }
}
