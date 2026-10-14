import Darwin
import Foundation
import IOKit

public struct GPUInfo: Sendable, Equatable {
    public var name: String
    public var coreCount: Int?
}

/// GPU-wide activity from the accelerator's PerformanceStatistics. Fractions are 0...1.
public struct GPUStats: Sendable, Equatable {
    /// How busy the GPU is overall (Activity Monitor's GPU History).
    public var device: Double
    /// Share of time spent shading pixels.
    public var renderer: Double
    /// Share of time spent processing geometry.
    public var tiler: Double
    /// Memory the GPU is actively using. On Apple Silicon this is shared with the CPU.
    public var inUseMemory: UInt64
    /// Memory reserved for the GPU, used or not.
    public var allocatedMemory: UInt64

    public init(device: Double, renderer: Double, tiler: Double, inUseMemory: UInt64, allocatedMemory: UInt64) {
        self.device = device
        self.renderer = renderer
        self.tiler = tiler
        self.inUseMemory = inUseMemory
        self.allocatedMemory = allocatedMemory
    }
}

/// Reads the GPU through IOKit. None of this needs administrator rights.
public enum GPUSampler {
    public static func info() -> GPUInfo? {
        withAccelerator { accelerator in
            let name = (property(accelerator, "model") as? String) ?? "GPU"
            return GPUInfo(name: name, coreCount: property(accelerator, "gpu-core-count") as? Int)
        }
    }

    public static func stats() -> GPUStats? {
        withAccelerator { accelerator in
            guard let stats = property(accelerator, "PerformanceStatistics") as? [String: Any] else { return nil }
            func fraction(_ key: String) -> Double { Double(stats[key] as? Int ?? 0) / 100 }
            func bytes(_ key: String) -> UInt64 { (stats[key] as? NSNumber)?.uint64Value ?? 0 }
            return GPUStats(
                device: fraction("Device Utilization %"),
                renderer: fraction("Renderer Utilization %"),
                tiler: fraction("Tiler Utilization %"),
                inUseMemory: bytes("In use system memory"),
                allocatedMemory: bytes("Alloc system memory"))
        }
    }

    /// Cumulative GPU time per process, in nanoseconds. Each app talking to the GPU has
    /// one or more accelerator user clients, tagged "pid 123, Name", with an AppUsage list.
    public static func processGPUTimes() -> [pid_t: UInt64] {
        var times: [pid_t: UInt64] = [:]
        forEachAccelerator { accelerator in
            var children: io_iterator_t = 0
            guard IORegistryEntryGetChildIterator(accelerator, kIOServicePlane, &children) == KERN_SUCCESS else { return }
            defer { IOObjectRelease(children) }
            var child = IOIteratorNext(children)
            while child != 0 {
                if let creator = property(child, "IOUserClientCreator") as? String,
                   let pid = parsePID(creator),
                   let usage = property(child, "AppUsage") as? [[String: Any]] {
                    let total = usage.reduce(UInt64(0)) {
                        $0 + ((($1["accumulatedGPUTime"]) as? NSNumber)?.uint64Value ?? 0)
                    }
                    times[pid, default: 0] += total
                }
                IOObjectRelease(child)
                child = IOIteratorNext(children)
            }
        }
        return times
    }

    /// "pid 661, WindowServer" → 661.
    static func parsePID(_ creator: String) -> pid_t? {
        guard creator.hasPrefix("pid ") else { return nil }
        return pid_t(creator.dropFirst(4).prefix { $0.isNumber })
    }

    private static func withAccelerator<T>(_ body: (io_registry_entry_t) -> T?) -> T? {
        var result: T?
        forEachAccelerator { accelerator in
            if result == nil { result = body(accelerator) }
        }
        return result
    }

    private static func forEachAccelerator(_ body: (io_registry_entry_t) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iterator)
            == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        var accelerator = IOIteratorNext(iterator)
        while accelerator != 0 {
            body(accelerator)
            IOObjectRelease(accelerator)
            accelerator = IOIteratorNext(iterator)
        }
    }

    private static func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }
}
