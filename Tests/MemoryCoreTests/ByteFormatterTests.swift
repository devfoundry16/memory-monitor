import Testing
@testable import MemoryCore

@Suite struct ByteFormatterTests {
    let mb: UInt64 = 1024 * 1024
    let gb: UInt64 = 1024 * 1024 * 1024

    @Test func zero() {
        #expect(ByteFormatter.format(0) == "0.0 MB")
    }

    @Test func belowOneMegabyteStillShowsMB() {
        #expect(ByteFormatter.format(400 * 1024) == "0.4 MB")
    }

    @Test func megabytes() {
        #expect(ByteFormatter.format(500 * mb) == "500.0 MB")
        #expect(ByteFormatter.format(1023 * mb + 900 * 1024) == "1023.9 MB")
    }

    @Test func roundingAtBoundarySwitchesToGB() {
        // 1023.96 MB would round to "1024.0 MB"; it must show as GB instead.
        let bytes = UInt64(1023.96 * Double(mb))
        #expect(ByteFormatter.format(bytes) == "1.00 GB")
    }

    @Test func exactlyOneGigabyte() {
        #expect(ByteFormatter.format(gb) == "1.00 GB")
    }

    @Test func gigabytes() {
        #expect(ByteFormatter.format(16 * gb) == "16.00 GB")
        #expect(ByteFormatter.format(gb + gb / 2) == "1.50 GB")
    }
}

@Suite struct MemoryPressureTests {
    @Test func kernelLevels() {
        #expect(MemoryPressure(kernelLevel: 1) == .normal)
        #expect(MemoryPressure(kernelLevel: 2) == .warning)
        #expect(MemoryPressure(kernelLevel: 4) == .critical)
        #expect(MemoryPressure(kernelLevel: 0) == .normal)
    }
}

@Suite struct PercentFormatterTests {
    @Test func wholePercentages() {
        #expect(PercentFormatter.format(0) == "0%")
        #expect(PercentFormatter.format(0.786) == "79%")
        #expect(PercentFormatter.format(1) == "100%")
    }

    @Test func tinyNonZeroValues() {
        #expect(PercentFormatter.format(0.002) == "<1%")
    }

    @Test func fractionOfTotal() {
        let memory = SystemMemory(
            total: 16, appMemory: 4, wired: 2, compressed: 2, cachedFiles: 0, purgeable: 0,
            hardwareReserved: 0, free: 8, fileBacked: 0, swapTotal: 0, swapUsed: 0, pressure: .normal)
        #expect(memory.fractionOfTotal(memory.used) == 0.5)
    }

    /// Activity Monitor's Memory Used is everything but free and file-backed pages: app memory,
    /// wired, compressed, purgeable (also counted in cached files) and hardware-reserved memory.
    @Test func usedMatchesActivityMonitor() {
        let memory = SystemMemory(
            total: 100, appMemory: 40, wired: 15, compressed: 20, cachedFiles: 18, purgeable: 2,
            hardwareReserved: 4, free: 3, fileBacked: 16, swapTotal: 0, swapUsed: 0, pressure: .normal)
        #expect(memory.used == 81)
        #expect(memory.used == memory.appMemory + memory.wired + memory.compressed
            + memory.purgeable + memory.hardwareReserved)
    }

    @Test func usedNeverUnderflows() {
        let memory = SystemMemory(
            total: 10, appMemory: 8, wired: 4, compressed: 0, cachedFiles: 6, purgeable: 0,
            hardwareReserved: 0, free: 5, fileBacked: 6, swapTotal: 0, swapUsed: 0, pressure: .normal)
        #expect(memory.used == 0)
    }
}
