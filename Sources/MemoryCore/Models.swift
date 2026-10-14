import Foundation

public enum MemoryPressure: Sendable, Equatable {
    case normal, warning, critical

    /// Maps `kern.memorystatus_vm_pressure_level` (1 = normal, 2 = warning, 4 = critical).
    public init(kernelLevel: Int32) {
        switch kernelLevel {
        case 4: self = .critical
        case 2: self = .warning
        default: self = .normal
        }
    }
}

/// System-wide memory, using Activity Monitor's definitions. All values are bytes.
public struct SystemMemory: Sendable, Equatable {
    public var total: UInt64
    public var appMemory: UInt64
    public var wired: UInt64
    public var compressed: UInt64
    public var cachedFiles: UInt64
    public var swapTotal: UInt64
    public var swapUsed: UInt64
    public var pressure: MemoryPressure

    /// "Memory Used" in Activity Monitor: app memory + wired + compressed.
    public var used: UInt64 { appMemory + wired + compressed }

    /// `bytes` as a fraction of physical memory.
    public func fractionOfTotal(_ bytes: UInt64) -> Double {
        total == 0 ? 0 : Double(bytes) / Double(total)
    }

    public init(
        total: UInt64, appMemory: UInt64, wired: UInt64, compressed: UInt64,
        cachedFiles: UInt64, swapTotal: UInt64, swapUsed: UInt64, pressure: MemoryPressure
    ) {
        self.total = total
        self.appMemory = appMemory
        self.wired = wired
        self.compressed = compressed
        self.cachedFiles = cachedFiles
        self.swapTotal = swapTotal
        self.swapUsed = swapUsed
        self.pressure = pressure
    }
}

public struct ProcessRow: Identifiable, Sendable, Equatable {
    public var pid: pid_t
    public var name: String
    /// Parent process ID (0 when unknown).
    public var ppid: pid_t
    /// The process macOS holds responsible for this one: usually the app that launched it,
    /// even through launchd (XPC services). `nil` when unknown.
    public var responsiblePID: pid_t?
    public var uid: uid_t
    public var user: String
    /// Physical footprint, as in Activity Monitor's Memory column. `nil` when the kernel
    /// refuses to report it (another user's process, read without privileges).
    public var memory: UInt64?
    /// `nil` when the kernel refuses to report it.
    public var threads: Int?
    /// Total CPU time used since the process started (user + system), in nanoseconds.
    public var cpuTime: UInt64?
    /// When the process started (mach absolute time). Tells a reused PID from the original.
    public var startTime: UInt64?
    /// CPU use over the last sampling interval; 100 = one core fully busy (Activity Monitor's
    /// convention). `nil` until two samples exist or when the kernel refuses to report it.
    public var cpuPercent: Double?
    /// Share of GPU time over the last interval; 100 = the whole GPU. `nil` until two samples exist.
    public var gpuPercent: Double?

    public var id: pid_t { pid }
    public var isRestricted: Bool { memory == nil || threads == nil }

    public init(
        pid: pid_t, ppid: pid_t = 0, responsiblePID: pid_t? = nil, name: String, uid: uid_t,
        user: String, memory: UInt64?, threads: Int?, cpuTime: UInt64? = nil, startTime: UInt64? = nil
    ) {
        self.pid = pid
        self.ppid = ppid
        self.responsiblePID = responsiblePID
        self.name = name
        self.uid = uid
        self.user = user
        self.memory = memory
        self.threads = threads
        self.cpuTime = cpuTime
        self.startTime = startTime
    }
}

public struct ProcessSnapshot: Sendable, Equatable {
    public var rows: [ProcessRow]
    /// Sum of the thread counts that could be read.
    public var threadTotal: Int
    /// Processes whose memory or thread count could not be read.
    public var restrictedCount: Int
    public var ownCount: Int

    public var processCount: Int { rows.count }
    public var othersCount: Int { rows.count - ownCount }

    public init(rows: [ProcessRow], threadTotal: Int, restrictedCount: Int, ownCount: Int) {
        self.rows = rows
        self.threadTotal = threadTotal
        self.restrictedCount = restrictedCount
        self.ownCount = ownCount
    }
}
