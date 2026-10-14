import Foundation
import Testing
@testable import MemoryCore

@Suite struct ProcessKillerTests {
    @Test func protectedProcesses() {
        #expect(ProcessKiller.protection(pid: 0, name: "kernel_task") == .protected)
        #expect(ProcessKiller.protection(pid: 1, name: "launchd") == .protected)
        #expect(ProcessKiller.protection(pid: 500, name: "MemoryMonitor", ownPID: 500) == .protected)
    }

    @Test func criticalProcesses() {
        #expect(ProcessKiller.protection(pid: 400, name: "WindowServer") == .critical)
        #expect(ProcessKiller.protection(pid: 401, name: "loginwindow") == .critical)
        #expect(ProcessKiller.protection(pid: 402, name: "Safari") == .none)
    }

    @Test func stopsOwnProcessWithSIGTERM() async throws {
        let process = try spawn("/bin/sleep", ["10000"])
        let result = await ProcessKiller.forceStop(pid: process.processIdentifier, expectedName: "sleep")
        #expect(result == .stopped)
        #expect(!ProcessKiller.isAlive(process.processIdentifier))
    }

    @Test func escalatesToSIGKILLWhenTermIsIgnored() async throws {
        // An ignored signal stays ignored across exec, so `sleep` ignores SIGTERM.
        let process = try spawn("/bin/bash", ["-c", "trap '' TERM; exec /bin/sleep 10000"])
        try await Task.sleep(for: .milliseconds(200)) // let bash exec into sleep
        let start = ContinuousClock.now
        let result = await ProcessKiller.forceStop(
            pid: process.processIdentifier, expectedName: "sleep", gracePeriod: .milliseconds(300))
        #expect(result == .stopped)
        #expect(ContinuousClock.now - start >= .milliseconds(300))
        #expect(process.terminationReason == .uncaughtSignal || !ProcessKiller.isAlive(process.processIdentifier))
    }

    @Test func refusesWhenPIDNowBelongsToAnotherProgram() async throws {
        let process = try spawn("/bin/sleep", ["10000"])
        defer { process.terminate() }
        let result = await ProcessKiller.forceStop(pid: process.processIdentifier, expectedName: "Safari")
        #expect(result == .alreadyExited)
        #expect(ProcessKiller.isAlive(process.processIdentifier))
    }

    @Test func protectedPIDIsNeverSignalled() async {
        #expect(await ProcessKiller.forceStop(pid: 1, expectedName: "launchd") == .protected)
    }

    @Test func samplerSeesSpawnedProcess() throws {
        let process = try spawn("/bin/sleep", ["10000"])
        defer { process.terminate() }
        let row = ProcessSampler().sample().rows.first { $0.pid == process.processIdentifier }
        #expect(row?.name == "sleep")
        #expect(row?.memory != nil)
        #expect(row?.threads == 1)
        #expect(row?.ppid == getpid())
    }

    private func spawn(_ path: String, _ args: [String]) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = args
        try process.run()
        return process
    }
}
