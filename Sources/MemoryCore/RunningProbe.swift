import Darwin
import Foundation

/// Whether the app or tool that owns a cache is running right now.
public enum RunningProbe {
    /// - `runningBundleIDs`: from NSWorkspace's running applications.
    /// - `processNames`: names of running processes, for command-line tools.
    public static func isRunning(_ owner: CacheOwner, runningBundleIDs: Set<String>, processNames: Set<String>) -> Bool {
        owner.bundleIDs.contains(where: runningBundleIDs.contains)
            || owner.processNames.contains(where: processNames.contains)
            || owner.singletonLocks.contains { lockHolderPID($0).map(ProcessKiller.isAlive) ?? false }
    }

    /// Names of running programs: each process's name and, for script interpreters, the script
    /// it runs. npm, pip and brew show up as node, Python and ruby, so their names come from
    /// the command line instead (e.g. "npm" for `node /opt/homebrew/bin/npm install`).
    public static func runningToolNames(_ rows: [ProcessRow]) -> Set<String> {
        var names = Set(rows.map(\.name))
        for row in rows where interpreters.contains(where: { row.name.lowercased().hasPrefix($0) }) {
            guard let arguments = arguments(of: row.pid) else { continue }
            names.formUnion(toolNames(fromArguments: arguments))
        }
        return names
    }

    private static let interpreters = ["node", "python", "ruby", "java", "bun", "deno"]
    private static let scriptSuffixes = [".js", ".cjs", ".mjs", ".py", ".rb", "-cli"]

    /// Reported for a program running out of ~/.npm/_npx (e.g. an MCP server started with npx).
    public static let npxPackageRunning = "npx package"

    /// The tools a command line runs: the script name (without extension), a `-m` module, npx
    /// packages (run from ~/.npm/_npx) and Gradle (a Java class).
    static func toolNames(fromArguments arguments: [String]) -> Set<String> {
        var names = Set<String>()
        if arguments.count > 1, !arguments[1].hasPrefix("-") {
            var script = (arguments[1] as NSString).lastPathComponent
            for suffix in scriptSuffixes where script.hasSuffix(suffix) { script = String(script.dropLast(suffix.count)) }
            names.insert(script)
        }
        if let module = arguments.firstIndex(of: "-m"), module + 1 < arguments.count {
            names.insert(arguments[module + 1])
        }
        if arguments.contains(where: { $0.contains("/.npm/_npx/") }) { names.insert(npxPackageRunning) }
        if arguments.contains(where: { $0.contains("org.gradle") }) { names.insert("gradle") }
        return names
    }

    /// A process's command line, from KERN_PROCARGS2. `nil` for other users' processes.
    static func arguments(of pid: pid_t) -> [String]? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        // Layout: argc, the executable path, NUL padding, then argc NUL-terminated arguments.
        let argc = buffer.withUnsafeBytes { Int($0.load(as: Int32.self)) }
        var index = MemoryLayout<Int32>.size
        while index < size, buffer[index] != 0 { index += 1 }
        while index < size, buffer[index] == 0 { index += 1 }
        var arguments: [String] = []
        while arguments.count < argc, index < size {
            let start = index
            while index < size, buffer[index] != 0 { index += 1 }
            arguments.append(String(decoding: buffer[start..<index], as: UTF8.self))
            index += 1
        }
        return arguments
    }

    /// Chromium's SingletonLock is a symlink to "<host>-<pid>" while the app runs.
    static func lockHolderPID(_ lock: URL) -> pid_t? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = readlink(lock.path, &buffer, buffer.count - 1)
        guard length > 0 else { return nil }
        let target = String(cString: buffer)
        guard let dash = target.lastIndex(of: "-"), let pid = pid_t(target[target.index(after: dash)...]), pid > 0
        else { return nil }
        return pid
    }
}
