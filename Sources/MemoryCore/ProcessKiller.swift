import Foundation

public enum KillResult: Sendable, Equatable {
    case stopped
    case alreadyExited
    case cancelledByUser
    case protected
    case denied(String)
}

public enum ProcessProtection: Sendable, Equatable {
    case none
    /// Killable, but doing so logs the user out or freezes the session.
    case critical
    /// Never killable: kernel_task, launchd, or this app itself.
    case protected
}

public enum ProcessKiller {
    public static let criticalNames: Set<String> = ["WindowServer", "loginwindow"]

    public static func protection(pid: pid_t, name: String, ownPID: pid_t = getpid()) -> ProcessProtection {
        if pid <= 1 || pid == ownPID { return .protected }
        if criticalNames.contains(name) { return .critical }
        return .none
    }

    public static func isAlive(_ pid: pid_t) -> Bool {
        kill(pid, 0) == 0 || errno == EPERM
    }

    /// Sends SIGTERM, waits `gracePeriod`, then SIGKILL. Processes owned by another user
    /// (including root) go through an administrator password prompt.
    public static func forceStop(
        pid: pid_t, expectedName: String, gracePeriod: Duration = .seconds(2)
    ) async -> KillResult {
        if protection(pid: pid, name: expectedName) == .protected { return .protected }
        // The PID may have been reused by a different program since the list was sampled.
        guard isAlive(pid), ProcessSampler.name(of: pid) == expectedName else { return .alreadyExited }

        if kill(pid, SIGTERM) != 0 {
            switch errno {
            case ESRCH: return .alreadyExited
            case EPERM: return await forceStopAsAdministrator(pid: pid)
            default: return .denied(String(cString: strerror(errno)))
            }
        }
        if await waitForExit(pid, timeout: gracePeriod) { return .stopped }
        kill(pid, SIGKILL)
        if await waitForExit(pid, timeout: .seconds(1)) { return .stopped }
        return .denied("The process did not exit.")
    }

    static func forceStopAsAdministrator(pid: pid_t) async -> KillResult {
        // `pid` is an integer, so nothing user-controlled reaches the shell.
        let shell = "/bin/kill -TERM \(pid); for i in $(/usr/bin/seq 20); do "
            + "/bin/kill -0 \(pid) 2>/dev/null || exit 0; /bin/sleep 0.1; done; /bin/kill -KILL \(pid)"
        let script = "do shell script \"\(shell)\" with administrator privileges"

        let (status, stderr) = await run("/usr/bin/osascript", ["-e", script])
        if stderr.contains("-128") { return .cancelledByUser }
        if await waitForExit(pid, timeout: .seconds(1)) { return .stopped }
        if status != 0 {
            let reason = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return .denied(reason.isEmpty ? "Administrator kill failed." : reason)
        }
        return .denied("The process did not exit. It may be protected by System Integrity Protection.")
    }

    static func waitForExit(_ pid: pid_t, timeout: Duration) async -> Bool {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            if !isAlive(pid) { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return !isAlive(pid)
    }

    private static func run(_ executable: String, _ arguments: [String]) async -> (Int32, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardError = errorPipe
            process.standardOutput = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (finished.terminationStatus, String(decoding: data, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, error.localizedDescription))
            }
        }
    }
}
