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
    ///
    /// PIDs get reused, so the target is identified by name plus start time (when known)
    /// and re-checked immediately before every signal, not just once up front.
    public static func forceStop(
        pid: pid_t, expectedName: String, expectedStart: UInt64? = nil, gracePeriod: Duration = .seconds(2)
    ) async -> KillResult {
        if protection(pid: pid, name: expectedName) == .protected { return .protected }
        let target = Target(pid: pid, name: expectedName, startTime: expectedStart)
        guard target.isStillRunning() else { return .alreadyExited }

        if kill(pid, SIGTERM) != 0 {
            switch errno {
            case ESRCH: return .alreadyExited
            case EPERM: return await forceStopAsAdministrator(target)
            default: return .denied(String(cString: strerror(errno)))
            }
        }
        if await waitForExit(pid, timeout: gracePeriod) { return .stopped }
        guard target.isStillRunning() else { return .stopped }
        kill(pid, SIGKILL)
        if await waitForExit(pid, timeout: .seconds(1)) { return .stopped }
        return .denied("The process did not exit.")
    }

    /// The process a stop request was made for.
    struct Target {
        let pid: pid_t
        let name: String
        let startTime: UInt64?

        /// True while `pid` still belongs to this process rather than one that reused the PID.
        /// Start time is only readable for your own processes; others fall back to the name.
        func isStillRunning() -> Bool {
            guard isAlive(pid), ProcessSampler.name(of: pid) == name else { return false }
            guard let startTime, let current = ProcessSampler.resourceUsage(of: pid) else { return true }
            return current.startTime == startTime
        }
    }

    /// `ps` start time + executable, hashed. The root shell compares this right before each
    /// signal, so a PID reused while the password prompt was open is left alone. Hashing keeps
    /// process names (which can contain any character) out of the shell command.
    static func fingerprintCommand(pid: pid_t) -> String {
        "LC_ALL=C TZ=UTC /bin/ps -o lstart=,comm= -p \(pid) 2>/dev/null | /sbin/md5"
    }

    /// The command run as root. Only integers and a hex hash reach the shell, and it has no
    /// double quotes, so it embeds in AppleScript as-is. Exit 3: the PID now belongs to
    /// another process, so nothing was signalled.
    static func adminShellCommand(pid: pid_t, fingerprint: String) -> String {
        let check = "[ x$(\(fingerprintCommand(pid: pid))) = x\(fingerprint) ] || exit 3"
        return "\(check); /bin/kill -TERM \(pid); for i in $(/usr/bin/seq 20); do "
            + "/bin/kill -0 \(pid) 2>/dev/null || exit 0; /bin/sleep 0.1; done; "
            + "\(check); /bin/kill -KILL \(pid)"
    }

    static func forceStopAsAdministrator(_ target: Target) async -> KillResult {
        let pid = target.pid
        // Fingerprint now, as the current user (ps can read every process's start time).
        let (_, fingerprint, _) = await run("/bin/sh", ["-c", fingerprintCommand(pid: pid)])
        let expected = fingerprint.trimmingCharacters(in: .whitespacesAndNewlines)
        guard expected.count == 32, expected.allSatisfy(\.isHexDigit), target.isStillRunning() else {
            return .alreadyExited
        }

        let shell = adminShellCommand(pid: pid, fingerprint: expected)
        let script = "do shell script \"\(shell)\" with administrator privileges"

        let (status, _, stderr) = await run("/usr/bin/osascript", ["-e", script])
        if stderr.contains("-128") { return .cancelledByUser }
        // osascript reports the shell's exit status in parentheses: "... (3)".
        if stderr.contains("(3)") {
            return target.isStillRunning() ? .denied("The process changed while waiting for the password.") : .alreadyExited
        }
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

    /// Runs a tool and returns (exit status, stdout, stderr). Outputs here are a few bytes,
    /// so reading after exit cannot fill the pipe buffer.
    private static func run(_ executable: String, _ arguments: [String]) async -> (Int32, String, String) {
        await withCheckedContinuation { continuation in
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.terminationHandler = { finished in
                let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
                let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
                continuation.resume(returning: (
                    finished.terminationStatus,
                    String(decoding: output, as: UTF8.self),
                    String(decoding: error, as: UTF8.self)))
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: (-1, "", error.localizedDescription))
            }
        }
    }
}
