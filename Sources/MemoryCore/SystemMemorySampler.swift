import Darwin

public enum SamplerError: Error, Equatable {
    case kernel(kern_return_t)
    case sysctl(String, Int32)
}

/// Reads system-wide memory the same way Activity Monitor does.
public struct SystemMemorySampler: Sendable {
    // mach_host_self() hands out a new port right on every call, so take it once.
    private let host: host_t
    private let pageSize: UInt64
    private let total: UInt64

    public init() throws {
        host = mach_host_self()
        var size: vm_size_t = 0
        let kr = host_page_size(host, &size)
        guard kr == KERN_SUCCESS else { throw SamplerError.kernel(kr) }
        pageSize = UInt64(size)
        total = try sysctlValue("hw.memsize", as: UInt64.self)
    }

    public func sample() throws -> SystemMemory {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let kr = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        guard kr == KERN_SUCCESS else { throw SamplerError.kernel(kr) }

        let internalPages = UInt64(stats.internal_page_count)
        let purgeable = UInt64(stats.purgeable_count)
        let swap = try sysctlValue("vm.swapusage", as: xsw_usage.self)
        let level = (try? sysctlValue("kern.memorystatus_vm_pressure_level", as: Int32.self)) ?? 1

        return SystemMemory(
            total: total,
            appMemory: (internalPages - min(purgeable, internalPages)) * pageSize,
            wired: UInt64(stats.wire_count) * pageSize,
            compressed: UInt64(stats.compressor_page_count) * pageSize,
            cachedFiles: (UInt64(stats.external_page_count) + purgeable) * pageSize,
            swapTotal: swap.xsu_total,
            swapUsed: swap.xsu_used,
            pressure: MemoryPressure(kernelLevel: level)
        )
    }
}

func sysctlValue<T>(_ name: String, as _: T.Type) throws -> T {
    let pointer = UnsafeMutablePointer<T>.allocate(capacity: 1)
    defer { pointer.deallocate() }
    var size = MemoryLayout<T>.size
    guard sysctlbyname(name, pointer, &size, nil, 0) == 0 else {
        throw SamplerError.sysctl(name, errno)
    }
    return pointer.pointee
}
