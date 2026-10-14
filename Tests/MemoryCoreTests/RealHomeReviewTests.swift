import Foundation
import Testing
@testable import MemoryCore

/// Read-only review of what the cleaner would remove from the real home folder. Lists and
/// measures; never deletes. Runs only when FRESH_REVIEW_REAL_HOME=1, e.g.
/// `FRESH_REVIEW_REAL_HOME=1 scripts/test.sh --filter RealHomeReview`.
@Suite(.enabled(if: ProcessInfo.processInfo.environment["FRESH_REVIEW_REAL_HOME"] == "1"))
struct RealHomeReviewTests {
    @Test func reviewPlannedRemovals() throws {
        let environment = CacheEnvironment.current
        let result = CacheDiscovery(environment: environment,
                                    appIndex: AppIndex(scanning: environment.applicationDirectories)).discover()
        let cleaner = CacheCleaner(environment: environment, trash: { _ in nil }, isInUse: { _ in false })
        let planned = Dictionary(uniqueKeysWithValues: cleaner.plannedRemovals(result.items).map { ($0.id, $0.entries) })

        var lines: [String] = []
        var total: UInt64 = 0
        for item in result.items {
            let size = FileTreeWalker.measure(planned[item.id] ?? [])
            total += size.bytes
            lines.append(String(format: "%9.1f MB  %@  %@  %@%@", Double(size.bytes) / 1_048_576,
                                item.isRecommended ? "[x]" : "[ ]", item.category.rawValue, item.name,
                                item.detail.map { " (\($0))" } ?? ""))
            for target in item.targets {
                lines.append("              " + target.url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~"))
            }
        }
        lines.append(String(format: "TOTAL %.2f GB in %d items; no access: %@", Double(total) / 1_073_741_824,
                            result.items.count, result.noAccess.map(\.lastPathComponent).joined(separator: ", ")))
        let report = FileManager.default.temporaryDirectory.appendingPathComponent("fresh-real-home-review.txt")
        try lines.joined(separator: "\n").write(to: report, atomically: true, encoding: .utf8)
        print("Review written to \(report.path)")

        // Nothing that would be removed may sit inside user data.
        let entries = planned.values.flatMap { $0 }
        for entry in entries {
            let components = Set(entry.pathComponents)
            #expect(components.isDisjoint(with: CachePathPolicy.protectedNames), "would remove \(entry.path)")
            #expect(!entry.path.contains("/Library/Containers/"), "would remove \(entry.path)")
        }
    }
}
