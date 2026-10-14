import Foundation
import Testing
@testable import MemoryCore

@Suite struct ProcessKillerTests {
    @Test func protectedProcesses() {
        #expect(ProcessKiller.protection(pid: 0, name: "kernel_task") == .protected)
        #expect(ProcessKiller.protection(pid: 1, name: "launchd") == .protected)
        #expect(ProcessKiller.protection(pid: 500, name: "Fresh", ownPID: 500) == .protected)
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

    @Test func refusesWhenStartTimeDiffers() async throws {
        // Same PID and name, different start time: what a reused PID looks like.
        let process = try spawn("/bin/sleep", ["10000"])
        defer { process.terminate() }
        let start = try #require(ProcessSampler.resourceUsage(of: process.processIdentifier)?.startTime)
        let result = await ProcessKiller.forceStop(
            pid: process.processIdentifier, expectedName: "sleep", expectedStart: start + 1)
        #expect(result == .alreadyExited)
        #expect(ProcessKiller.isAlive(process.processIdentifier))
    }

    @Test func matchingStartTimeStops() async throws {
        let process = try spawn("/bin/sleep", ["10000"])
        let start = try #require(ProcessSampler.resourceUsage(of: process.processIdentifier)?.startTime)
        let result = await ProcessKiller.forceStop(
            pid: process.processIdentifier, expectedName: "sleep", expectedStart: start)
        #expect(result == .stopped)
    }

    @Test func fingerprintIsStableAndSafe() async throws {
        let process = try spawn("/bin/sleep", ["10000"])
        defer { process.terminate() }
        let command = ProcessKiller.fingerprintCommand(pid: process.processIdentifier)
        #expect(!command.contains("\""), "must embed in AppleScript without escaping")
        func fingerprint() throws -> String {
            let shell = Process()
            let pipe = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", command]
            shell.standardOutput = pipe
            try shell.run()
            shell.waitUntilExit()
            return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let first = try fingerprint()
        #expect(first.count == 32 && first.allSatisfy(\.isHexDigit))
        #expect(try fingerprint() == first)
    }

    /// Runs the root command as the current user, which exercises the same checks
    /// without an administrator prompt.
    @Test func adminCommandChecksFingerprintBeforeSignalling() throws {
        func sh(_ command: String) throws -> (Int32, String) {
            let shell = Process()
            let pipe = Pipe()
            shell.executableURL = URL(fileURLWithPath: "/bin/sh")
            shell.arguments = ["-c", command]
            shell.standardOutput = pipe
            try shell.run()
            shell.waitUntilExit()
            let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            return (shell.terminationStatus, out.trimmingCharacters(in: .whitespacesAndNewlines))
        }

        let process = try spawn("/bin/sleep", ["10000"])
        let pid = process.processIdentifier
        defer { if ProcessKiller.isAlive(pid) { process.terminate() } }
        let (_, fingerprint) = try sh(ProcessKiller.fingerprintCommand(pid: pid))

        // A stale fingerprint (PID reused) must leave the process alone.
        let wrong = String(repeating: "0", count: 32)
        let (refused, _) = try sh(ProcessKiller.adminShellCommand(pid: pid, fingerprint: wrong))
        #expect(refused == 3)
        #expect(ProcessKiller.isAlive(pid))

        // The matching fingerprint stops it.
        let command = ProcessKiller.adminShellCommand(pid: pid, fingerprint: fingerprint)
        #expect(!command.contains("\""))
        let (stopped, _) = try sh(command)
        #expect(stopped == 0)
        process.waitUntilExit()
        #expect(!ProcessKiller.isAlive(pid))
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
