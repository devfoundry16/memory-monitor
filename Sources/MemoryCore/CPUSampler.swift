import Darwin
import Foundation
import IOKit

public enum CoreKind: Sendable, Equatable {
    case performance, efficiency, unknown
}

public struct CPUTopology: Sendable, Equatable {
    public var brand: String
    /// One entry per logical CPU, in the kernel's CPU order.
    public var cores: [CoreKind]

    public var performanceCount: Int { cores.filter { $0 == .performance }.count }
    public var efficiencyCount: Int { cores.filter { $0 == .efficiency }.count }
}

/// Cumulative scheduler ticks per core, as returned by host_processor_info.
public struct CPUTicks: Sendable, Equatable {
    public struct Core: Sendable, Equatable {
        public var user: UInt32
        public var system: UInt32
        public var idle: UInt32
        public var nice: UInt32

        public init(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32) {
            self.user = user
            self.system = system
            self.idle = idle
            self.nice = nice
        }
    }

    public var cores: [Core]

    public init(cores: [Core]) {
        self.cores = cores
    }
}

/// CPU use between two tick samples. Fractions are 0...1.
public struct CPUUsage: Sendable, Equatable {
    public var user: Double
    public var system: Double
    public var idle: Double
    /// Busy fraction of each core (user + system + nice).
    public var perCore: [Double]

    public var total: Double { 1 - idle }
}

public enum CPUSampler {
    public static func topology() -> CPUTopology {
        let brand = (try? sysctlString("machdep.cpu.brand_string")) ?? "CPU"
        let count = Int((try? sysctlValue("hw.logicalcpu", as: Int32.self)) ?? 0)
        var cores = [CoreKind](repeating: .unknown, count: count)

        // Apple Silicon lists each core's cluster ("E" or "P") in the device tree.
        let cpus = IORegistryEntryFromPath(kIOMainPortDefault, "IODeviceTree:/cpus")
        if cpus != 0 {
            defer { IOObjectRelease(cpus) }
            var children: io_iterator_t = 0
            if IORegistryEntryGetChildIterator(cpus, kIODeviceTreePlane, &children) == KERN_SUCCESS {
                defer { IOObjectRelease(children) }
                var child = IOIteratorNext(children)
                while child != 0 {
                    if let id = property(child, "logical-cpu-id") as? Int, id < cores.count,
                       let cluster = property(child, "cluster-type") as? Data, let letter = cluster.first {
                        cores[id] = letter == UInt8(ascii: "P") ? .performance
                            : letter == UInt8(ascii: "E") ? .efficiency : .unknown
                    }
                    IOObjectRelease(child)
                    child = IOIteratorNext(children)
                }
            }
        }
        return CPUTopology(brand: brand, cores: cores)
    }

    public static func ticks() throws -> CPUTicks {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let kr = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &infoCount)
        guard kr == KERN_SUCCESS, let info else { throw SamplerError.kernel(kr) }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.stride))
        }
        let stride = Int(CPU_STATE_MAX)
        let cores = (0..<Int(cpuCount)).map { cpu -> CPUTicks.Core in
            func tick(_ state: Int32) -> UInt32 { UInt32(bitPattern: info[cpu * stride + Int(state)]) }
            return CPUTicks.Core(
                user: tick(CPU_STATE_USER), system: tick(CPU_STATE_SYSTEM),
                idle: tick(CPU_STATE_IDLE), nice: tick(CPU_STATE_NICE))
        }
        return CPUTicks(cores: cores)
    }

    /// Tick counters are 32-bit and wrap, so differences use wrapping subtraction.
    public static func usage(from old: CPUTicks, to new: CPUTicks) -> CPUUsage {
        var user = 0.0, system = 0.0, idle = 0.0, all = 0.0
        var perCore: [Double] = []
        for (a, b) in zip(old.cores, new.cores) {
            let u = Double(b.user &- a.user) + Double(b.nice &- a.nice)
            let s = Double(b.system &- a.system)
            let i = Double(b.idle &- a.idle)
            let sum = u + s + i
            perCore.append(sum > 0 ? (u + s) / sum : 0)
            user += u
            system += s
            idle += i
            all += sum
        }
        guard all > 0 else { return CPUUsage(user: 0, system: 0, idle: 1, perCore: perCore) }
        return CPUUsage(user: user / all, system: system / all, idle: idle / all, perCore: perCore)
    }

    /// 1, 5 and 15 minute load averages.
    public static func loadAverage() -> [Double] {
        var loads = [Double](repeating: 0, count: 3)
        return getloadavg(&loads, 3) == 3 ? loads : []
    }

    public static func bootTime() -> Date? {
        guard let boot = try? sysctlValue("kern.boottime", as: timeval.self) else { return nil }
        return Date(timeIntervalSince1970: Double(boot.tv_sec) + Double(boot.tv_usec) / 1_000_000)
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}

func sysctlString(_ name: String) throws -> String {
    var size = 0
    guard sysctlbyname(name, nil, &size, nil, 0) == 0 else { throw SamplerError.sysctl(name, errno) }
    var buffer = [CChar](repeating: 0, count: size)
    guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { throw SamplerError.sysctl(name, errno) }
    return String(nulTerminated: buffer)
}
