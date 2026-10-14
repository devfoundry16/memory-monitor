import Darwin

/// What the previous process sample looked like, so the next one can turn cumulative
/// CPU and GPU time into percentages.
public struct UsageBaseline: Sendable {
    struct Entry: Sendable {
        var startTime: UInt64?
        var cpuTime: UInt64?
        var gpuTime: UInt64
    }

    let takenAt: UInt64 // nanoseconds, monotonic
    let entries: [pid_t: Entry]
}

public enum UsageRates {
    /// Fills `cpuPercent` and `gpuPercent` on each row from the change since `previous`,
    /// and returns the baseline for the next call.
    ///
    /// - `now`: a monotonic clock in nanoseconds.
    /// - A PID whose start time changed is a different program reusing the PID, so it gets
    ///   no rate this round.
    public static func apply(
        to rows: inout [ProcessRow], gpuTimes: [pid_t: UInt64], now: UInt64, previous: UsageBaseline?
    ) -> UsageBaseline {
        let elapsed = previous.map { Double(now &- $0.takenAt) } ?? 0
        var entries: [pid_t: UsageBaseline.Entry] = [:]
        entries.reserveCapacity(rows.count)

        for index in rows.indices {
            let row = rows[index]
            let gpuTime = gpuTimes[row.pid] ?? 0
            entries[row.pid] = .init(startTime: row.startTime, cpuTime: row.cpuTime, gpuTime: gpuTime)

            guard elapsed > 0, let old = previous?.entries[row.pid], old.startTime == row.startTime else {
                continue
            }
            if let cpu = row.cpuTime, let oldCPU = old.cpuTime {
                rows[index].cpuPercent = cpu >= oldCPU ? Double(cpu - oldCPU) / elapsed * 100 : 0
            }
            // GPU time can drop when a GPU client closes; treat that as no use.
            rows[index].gpuPercent = gpuTime >= old.gpuTime ? Double(gpuTime - old.gpuTime) / elapsed * 100 : 0
        }
        return UsageBaseline(takenAt: now, entries: entries)
    }
}
