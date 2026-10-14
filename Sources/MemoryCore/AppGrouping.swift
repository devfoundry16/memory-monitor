import Darwin

/// An app plus every process that belongs to it (helpers, renderers, XPC services).
public struct AppGroup: Sendable, Equatable {
    public var appPID: pid_t
    /// The app's own process first, then its helpers by memory, largest first.
    public var members: [ProcessRow]

    /// Sum of every member's footprint that could be read.
    public var memory: UInt64 { members.reduce(0) { $0 + ($1.memory ?? 0) } }
    public var threads: Int { members.reduce(0) { $0 + ($1.threads ?? 0) } }
    /// Sum of members' CPU use (100 = one core), or `nil` before rates exist.
    public var cpuPercent: Double? { sum(\.cpuPercent) }
    /// Sum of members' share of GPU time, or `nil` before rates exist.
    public var gpuPercent: Double? { sum(\.gpuPercent) }

    private func sum(_ keyPath: KeyPath<ProcessRow, Double?>) -> Double? {
        let values = members.compactMap { $0[keyPath: keyPath] }
        return values.isEmpty ? nil : values.reduce(0, +)
    }
    /// Members whose memory or threads could not be read, so the totals are a lower bound.
    public var restrictedCount: Int { members.filter(\.isRestricted).count }
    public var processCount: Int { members.count }
}

public enum AppGrouping {
    /// The app a process belongs to, or `nil` for apps themselves and for processes no app owns.
    ///
    /// 1. The responsible process, when it is an app. This catches XPC services, whose
    ///    parent is launchd (e.g. Mail's and Safari's helpers).
    /// 2. Otherwise the nearest app among its ancestors (e.g. Chrome's helpers).
    public static func owner(
        of row: ProcessRow, byPID: [pid_t: ProcessRow], appPIDs: Set<pid_t>
    ) -> pid_t? {
        if appPIDs.contains(row.pid) { return nil }
        if let responsible = row.responsiblePID, responsible != row.pid, appPIDs.contains(responsible) {
            return responsible
        }
        // The step limit guards against cycles caused by PID reuse between samples.
        var current = row.ppid
        for _ in 0..<16 where current > 1 {
            if appPIDs.contains(current) { return current }
            guard let next = byPID[current]?.ppid else { return nil }
            current = next
        }
        return nil
    }

    /// Groups processes under their owning apps, keyed by app PID. Apps whose own
    /// process is not in `rows` are skipped.
    public static func groups(rows: [ProcessRow], appPIDs: Set<pid_t>) -> [pid_t: AppGroup] {
        let byPID = Dictionary(rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        var helpers: [pid_t: [ProcessRow]] = [:]
        for row in rows {
            if let owner = owner(of: row, byPID: byPID, appPIDs: appPIDs) {
                helpers[owner, default: []].append(row)
            }
        }
        var result: [pid_t: AppGroup] = [:]
        for pid in appPIDs {
            guard let app = byPID[pid] else { continue }
            let sorted = (helpers[pid] ?? []).sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }
            result[pid] = AppGroup(appPID: pid, members: [app] + sorted)
        }
        return result
    }
}
