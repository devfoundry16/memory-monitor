import Darwin
import Testing
@testable import MemoryCore

@Suite struct AppGroupingTests {
    func row(_ pid: pid_t, ppid: pid_t, responsible: pid_t? = nil, memory: UInt64? = 100, threads: Int? = 2) -> ProcessRow {
        ProcessRow(pid: pid, ppid: ppid, responsiblePID: responsible, name: "p\(pid)", uid: 501,
                   user: "me", memory: memory, threads: threads)
    }

    @Test func childAndGrandchildBelongToApp() {
        let rows = [row(10, ppid: 1), row(11, ppid: 10), row(12, ppid: 11)]
        let byPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        #expect(AppGrouping.owner(of: rows[1], byPID: byPID, appPIDs: [10]) == 10)
        #expect(AppGrouping.owner(of: rows[2], byPID: byPID, appPIDs: [10]) == 10)
    }

    @Test func xpcServiceUnderLaunchdUsesResponsibleApp() {
        let rows = [row(10, ppid: 1), row(20, ppid: 1, responsible: 10)]
        let byPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        #expect(AppGrouping.owner(of: rows[1], byPID: byPID, appPIDs: [10]) == 10)
    }

    @Test func appsAndUnownedDaemonsHaveNoOwner() {
        let rows = [row(10, ppid: 1, responsible: 10), row(30, ppid: 1, responsible: 30)]
        let byPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        #expect(AppGrouping.owner(of: rows[0], byPID: byPID, appPIDs: [10]) == nil)
        #expect(AppGrouping.owner(of: rows[1], byPID: byPID, appPIDs: [10]) == nil)
    }

    @Test func pidCycleTerminates() {
        let rows = [row(40, ppid: 41), row(41, ppid: 40)]
        let byPID = Dictionary(uniqueKeysWithValues: rows.map { ($0.pid, $0) })
        #expect(AppGrouping.owner(of: rows[0], byPID: byPID, appPIDs: [10]) == nil)
    }

    @Test func groupTotalsIncludeEveryHelper() {
        let rows = [
            row(10, ppid: 1, memory: 400, threads: 40),
            row(11, ppid: 10, memory: 1_000, threads: 20),
            row(20, ppid: 1, responsible: 10, memory: 600, threads: 5),
            row(30, ppid: 1, memory: 9_999),            // unrelated daemon
            row(12, ppid: 10, memory: nil, threads: nil), // unreadable helper
        ]
        let group = AppGrouping.groups(rows: rows, appPIDs: [10])[10]
        #expect(group?.processCount == 4)
        #expect(group?.memory == 2_000)
        #expect(group?.threads == 65)
        #expect(group?.restrictedCount == 1)
        #expect(group?.members.first?.pid == 10)          // app's own process first
        #expect(group?.members.dropFirst().first?.pid == 11) // then largest helper
    }

    @Test func liveSamplerReportsResponsiblePID() {
        let me = getpid()
        let row = ProcessSampler().sample().rows.first { $0.pid == me }
        #expect(row?.responsiblePID != nil)
    }
}
