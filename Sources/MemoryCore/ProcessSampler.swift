import Darwin

/// Lists every running process with its memory footprint and thread count.
public struct ProcessSampler: Sendable {
    public init() {}

    public func sample() -> ProcessSnapshot {
        let myUID = getuid()
        var userNames: [uid_t: String] = [:]
        var rows: [ProcessRow] = []
        var threadTotal = 0
        var restricted = 0
        var own = 0

        for pid in Self.allPIDs() {
            guard let (uid, ppid) = Self.ownership(of: pid) else { continue } // exited mid-scan

            let usage = Self.resourceUsage(of: pid)
            let threads = Self.threadCount(of: pid)
            let user = userNames[uid] ?? Self.userName(for: uid)
            userNames[uid] = user

            let row = ProcessRow(
                pid: pid, ppid: ppid, responsiblePID: Self.responsiblePID(of: pid),
                name: Self.name(of: pid), uid: uid, user: user,
                memory: usage?.footprint, threads: threads,
                cpuTime: usage?.cpuTime, startTime: usage?.startTime)
            rows.append(row)
            threadTotal += threads ?? 0
            if row.isRestricted { restricted += 1 }
            if uid == myUID { own += 1 }
        }

        return ProcessSnapshot(
            rows: rows, threadTotal: threadTotal, restrictedCount: restricted, ownCount: own)
    }

    static func allPIDs() -> [pid_t] {
        // Ask for the count, then over-allocate in case processes start in between.
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count)))
    }

    /// Owner and parent PID. This works for every user's processes, unlike memory and threads.
    static func ownership(of pid: pid_t) -> (uid: uid_t, ppid: pid_t)? {
        var info = proc_bsdshortinfo()
        let size = Int32(MemoryLayout<proc_bsdshortinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDT_SHORTBSDINFO, 0, &info, size) == size else { return nil }
        return (info.pbsi_uid, pid_t(info.pbsi_ppid))
    }

    /// Full executable name (proc_name truncates at 32 characters), falling back to proc_name.
    public static func name(of pid: pid_t) -> String {
        if pid == 0 { return "kernel_task" }
        var path = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        if proc_pidpath(pid, &path, UInt32(path.count)) > 0 {
            let full = String(nulTerminated: path)
            if let last = full.split(separator: "/").last { return String(last) }
        }
        var name = [CChar](repeating: 0, count: Int(MAXCOMLEN) * 2 + 1)
        if proc_name(pid, &name, UInt32(name.count)) > 0 {
            return String(nulTerminated: name)
        }
        return "pid \(pid)"
    }

    /// `responsibility_get_pid_responsible_for_pid` is private but stable SPI in libSystem;
    /// Activity Monitor relies on the same information. Looked up at runtime so the app
    /// still works (falling back to the parent chain) if it ever disappears.
    private static let responsibleFor: (@convention(c) (pid_t) -> pid_t)? = {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), // RTLD_DEFAULT
                                 "responsibility_get_pid_responsible_for_pid") else { return nil }
        return unsafeBitCast(symbol, to: (@convention(c) (pid_t) -> pid_t).self)
    }()

    static func responsiblePID(of pid: pid_t) -> pid_t? {
        guard let responsibleFor else { return nil }
        let responsible = responsibleFor(pid)
        return responsible > 0 ? responsible : nil
    }

    /// Converts mach absolute time to nanoseconds. On Apple Silicon one tick is 125/3 ns,
    /// and rusage CPU times are reported in ticks, not nanoseconds.
    private static let timebase: (numer: UInt64, denom: UInt64) = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return (UInt64(info.numer), UInt64(max(info.denom, 1)))
    }()

    static func nanoseconds(fromMachTime ticks: UInt64) -> UInt64 {
        // Split the division so the multiplication cannot overflow.
        ticks / timebase.denom * timebase.numer + ticks % timebase.denom * timebase.numer / timebase.denom
    }

    static func resourceUsage(of pid: pid_t) -> (footprint: UInt64, cpuTime: UInt64, startTime: UInt64)? {
        var info = rusage_info_v4()
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
            }
        }
        guard result == 0 else { return nil }
        let cpuTime = nanoseconds(fromMachTime: info.ri_user_time + info.ri_system_time)
        return (info.ri_phys_footprint, cpuTime, info.ri_proc_start_abstime)
    }

    static func threadCount(of pid: pid_t) -> Int? {
        var info = proc_taskinfo()
        let size = Int32(MemoryLayout<proc_taskinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, size) == size else { return nil }
        return Int(info.pti_threadnum)
    }

    static func userName(for uid: uid_t) -> String {
        guard let entry = getpwuid(uid), let name = entry.pointee.pw_name else { return "\(uid)" }
        return String(cString: name)
    }
}

extension String {
    init(nulTerminated buffer: [CChar]) {
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        self = String(decoding: bytes, as: UTF8.self)
    }
}
