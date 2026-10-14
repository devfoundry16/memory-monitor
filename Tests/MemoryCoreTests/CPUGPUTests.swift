import Darwin
import Foundation
import Testing
@testable import MemoryCore

@Suite struct CPUUsageTests {
    @Test func splitsUserSystemIdleAcrossCores() {
        let old = CPUTicks(cores: [
            .init(user: 100, system: 100, idle: 100, nice: 0),
            .init(user: 0, system: 0, idle: 0, nice: 0),
        ])
        let new = CPUTicks(cores: [
            .init(user: 150, system: 125, idle: 125, nice: 0), // 75% busy
            .init(user: 0, system: 0, idle: 100, nice: 0),     // idle
        ])
        let usage = CPUSampler.usage(from: old, to: new)
        #expect(usage.perCore == [0.75, 0])
        #expect(usage.user == 0.25)
        #expect(usage.system == 0.125)
        #expect(usage.idle == 0.625)
        #expect(usage.total == 0.375)
    }

    @Test func survivesCounterWraparound() {
        let old = CPUTicks(cores: [.init(user: UInt32.max - 9, system: 0, idle: 0, nice: 0)])
        let new = CPUTicks(cores: [.init(user: 10, system: 0, idle: 20, nice: 0)])
        #expect(CPUSampler.usage(from: old, to: new).perCore == [0.5])
    }

    @Test func liveTopologyAndTicksAgree() throws {
        let topology = CPUSampler.topology()
        let ticks = try CPUSampler.ticks()
        #expect(ticks.cores.count == topology.cores.count)
        #expect(!topology.brand.isEmpty)
        #expect(CPUSampler.loadAverage().count == 3)
    }

    @Test func machTicksConvertToNanoseconds() {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        let ticks: UInt64 = 24_000_000
        #expect(ProcessSampler.nanoseconds(fromMachTime: ticks) == ticks * UInt64(info.numer) / UInt64(info.denom))
    }

    @Test func busyLoopShowsAsCPUTime() throws {
        let before = try #require(ProcessSampler.resourceUsage(of: getpid()))
        let start = Date()
        var x = 0.0
        while Date().timeIntervalSince(start) < 0.3 { x += sin(x) }
        let after = try #require(ProcessSampler.resourceUsage(of: getpid()))
        let spent = Double(after.cpuTime - before.cpuTime) / 1e9
        #expect(spent > 0.2 && spent < 0.5, "a 0.3 s busy loop should cost ~0.3 s of CPU, got \(spent)")
    }
}

@Suite struct UsageRateTests {
    func row(_ pid: pid_t, cpu: UInt64?, start: UInt64? = 1) -> ProcessRow {
        ProcessRow(pid: pid, name: "p", uid: 501, user: "me", memory: 1, threads: 1, cpuTime: cpu, startTime: start)
    }

    @Test func firstSampleHasNoRates() {
        var rows = [row(1, cpu: 100)]
        _ = UsageRates.apply(to: &rows, gpuTimes: [:], now: 1_000, previous: nil)
        #expect(rows[0].cpuPercent == nil)
        #expect(rows[0].gpuPercent == nil)
    }

    @Test func ratesFromDeltas() {
        var rows = [row(1, cpu: 0)]
        let baseline = UsageRates.apply(to: &rows, gpuTimes: [1: 0], now: 0, previous: nil)
        rows = [row(1, cpu: 500_000_000)] // 0.5 s of CPU
        _ = UsageRates.apply(to: &rows, gpuTimes: [1: 250_000_000], now: 1_000_000_000, previous: baseline)
        #expect(rows[0].cpuPercent == 50)
        #expect(rows[0].gpuPercent == 25)
    }

    @Test func reusedPIDGetsNoRate() {
        var rows = [row(1, cpu: 0, start: 1)]
        let baseline = UsageRates.apply(to: &rows, gpuTimes: [:], now: 0, previous: nil)
        rows = [row(1, cpu: 900_000_000, start: 2)]
        _ = UsageRates.apply(to: &rows, gpuTimes: [:], now: 1_000_000_000, previous: baseline)
        #expect(rows[0].cpuPercent == nil)
    }

    @Test func groupSumsRates() {
        var app = row(10, cpu: 0)
        app.cpuPercent = 20
        app.gpuPercent = 5
        var helper = row(11, cpu: 0)
        helper.cpuPercent = 30.5
        let group = AppGroup(appPID: 10, members: [app, helper])
        #expect(group.cpuPercent == 50.5)
        #expect(group.gpuPercent == 5)
    }
}

@Suite struct GPUTests {
    @Test func parsesClientCreator() {
        #expect(GPUSampler.parsePID("pid 661, WindowServer") == 661)
        #expect(GPUSampler.parsePID("WindowServer") == nil)
    }

    @Test func liveStatsOnThisMac() throws {
        let stats = try #require(GPUSampler.stats(), "no IOAccelerator found")
        #expect((0...1).contains(stats.device))
        #expect(GPUSampler.info() != nil)
        #expect(!GPUSampler.processGPUTimes().isEmpty)
    }
}
