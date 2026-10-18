import Foundation
import Testing
@testable import MemoryCore

@Suite struct DiskTests {
    @Test func parsesDriverStatistics() {
        let stats: [String: Any] = [
            "Bytes (Read)": NSNumber(value: 1_501_028_855_808 as UInt64), "Bytes (Write)": 606_594_785_280,
            "Operations (Read)": 64_902_112, "Operations (Write)": 21_502_310, "Errors (Read)": 0,
        ]
        #expect(DiskIOCounters.counters(fromStatistics: stats) == DiskIOCounters(
            bytesRead: 1_501_028_855_808, bytesWritten: 606_594_785_280, readOps: 64_902_112, writeOps: 21_502_310))
    }

    @Test func missingStatisticsCountAsZero() {
        #expect(DiskIOCounters.counters(fromStatistics: ["Bytes (Read)": 10])
            == DiskIOCounters(bytesRead: 10, bytesWritten: 0, readOps: 0, writeOps: 0))
    }

    @Test func ratesFromDeltas() {
        let old = DiskIOCounters(bytesRead: 1_000, bytesWritten: 0, readOps: 10, writeOps: 0)
        let new = DiskIOCounters(bytesRead: 5_000, bytesWritten: 2_000, readOps: 30, writeOps: 4)
        let io = DiskIO.rates(from: old, to: new, elapsed: 2)
        #expect(io.readPerSecond == 2_000)
        #expect(io.writePerSecond == 1_000)
        #expect(io.readOpsPerSecond == 10)
        #expect(io.writeOpsPerSecond == 2)
        #expect(io.totals == new)
    }

    @Test func droppedCounterIsNoTraffic() {
        // An ejected disk takes its driver's totals with it.
        let old = DiskIOCounters(bytesRead: 9_000, bytesWritten: 9_000, readOps: 9, writeOps: 9)
        let new = DiskIOCounters(bytesRead: 4_000, bytesWritten: 9_500, readOps: 4, writeOps: 9)
        let io = DiskIO.rates(from: old, to: new, elapsed: 1)
        #expect(io.readPerSecond == 0)
        #expect(io.writePerSecond == 500)
        #expect(DiskIO.rates(from: old, to: new, elapsed: 0).writePerSecond == 0)
    }

    @Test func volumeUsedAndPurgeable() {
        let volume = VolumeStats(name: "Macintosh HD", format: "APFS", total: 1_000, free: 200, available: 300)
        #expect(volume.used == 700)
        #expect(volume.purgeable == 100)
        #expect(volume.usedFraction == 0.7)
        let odd = VolumeStats(name: "x", format: "", total: 100, free: 150, available: 120)
        #expect(odd.used == 0)
        #expect(odd.purgeable == 0)
    }

    @Test func niceCeilingSteps() {
        #expect(MetricHistory.niceCeiling(0) == 1)
        #expect(MetricHistory.niceCeiling(1_000_000) == 1_000_000)
        #expect(MetricHistory.niceCeiling(1_000_001) == 2_000_000)
        #expect(MetricHistory.niceCeiling(3_400_000) == 5_000_000)
        #expect(MetricHistory.niceCeiling(7_000_000) == 10_000_000)
        #expect(MetricHistory.niceCeiling(0.3) == 0.5)
    }

    /// Reads only: the startup disk's size and the drivers' counters.
    @Test func liveDiskOnThisMac() throws {
        let volume = try #require(DiskSampler.startupVolume())
        #expect(volume.total > 0)
        #expect(volume.available >= volume.free)
        #expect(volume.used <= volume.total)
        let counters = try #require(DiskSampler.ioCounters(), "no IOBlockStorageDriver found")
        #expect(counters.bytesRead > 0)
    }
}
