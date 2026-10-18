import Darwin
import Foundation
import IOKit

/// Space on one volume. All values are bytes.
public struct VolumeStats: Sendable, Equatable {
    public var name: String
    /// e.g. "APFS".
    public var format: String
    public var total: UInt64
    /// Space no file uses at all.
    public var free: UInt64
    /// Free space plus what macOS can clear on demand (caches, iCloud copies, snapshots).
    /// Finder and System Settings show this as "available".
    public var available: UInt64

    public init(name: String, format: String, total: UInt64, free: UInt64, available: UInt64) {
        self.name = name
        self.format = format
        self.total = total
        self.free = free
        self.available = available
    }

    /// Space files use, not counting what macOS can clear on demand (Finder's "used").
    public var used: UInt64 { total > available ? total - available : 0 }
    /// What macOS can clear when space runs low.
    public var purgeable: UInt64 { available > free ? available - free : 0 }
    public var usedFraction: Double { total == 0 ? 0 : Double(used) / Double(total) }
}

/// Cumulative disk traffic since startup, summed over every block storage driver.
public struct DiskIOCounters: Sendable, Equatable {
    public var bytesRead: UInt64
    public var bytesWritten: UInt64
    public var readOps: UInt64
    public var writeOps: UInt64

    public init(bytesRead: UInt64, bytesWritten: UInt64, readOps: UInt64, writeOps: UInt64) {
        self.bytesRead = bytesRead
        self.bytesWritten = bytesWritten
        self.readOps = readOps
        self.writeOps = writeOps
    }

    /// Reads one driver's `Statistics` dictionary. Missing keys count as 0.
    public static func counters(fromStatistics stats: [String: Any]) -> DiskIOCounters {
        func value(_ key: String) -> UInt64 { (stats[key] as? NSNumber)?.uint64Value ?? 0 }
        return DiskIOCounters(
            bytesRead: value("Bytes (Read)"), bytesWritten: value("Bytes (Write)"),
            readOps: value("Operations (Read)"), writeOps: value("Operations (Write)"))
    }
}

/// Disk traffic over the last sampling interval, plus the totals since startup.
public struct DiskIO: Sendable, Equatable {
    public var readPerSecond: Double
    public var writePerSecond: Double
    public var readOpsPerSecond: Double
    public var writeOpsPerSecond: Double
    public var totals: DiskIOCounters

    public init(readPerSecond: Double, writePerSecond: Double, readOpsPerSecond: Double,
                writeOpsPerSecond: Double, totals: DiskIOCounters) {
        self.readPerSecond = readPerSecond
        self.writePerSecond = writePerSecond
        self.readOpsPerSecond = readOpsPerSecond
        self.writeOpsPerSecond = writeOpsPerSecond
        self.totals = totals
    }

    /// Rates between two samples `elapsed` seconds apart. A counter that went down (a disk
    /// was ejected, so its driver's totals vanished) counts as no traffic.
    public static func rates(from old: DiskIOCounters, to new: DiskIOCounters, elapsed: Double) -> DiskIO {
        func rate(_ a: UInt64, _ b: UInt64) -> Double {
            elapsed > 0 && b >= a ? Double(b - a) / elapsed : 0
        }
        return DiskIO(
            readPerSecond: rate(old.bytesRead, new.bytesRead),
            writePerSecond: rate(old.bytesWritten, new.bytesWritten),
            readOpsPerSecond: rate(old.readOps, new.readOps),
            writeOpsPerSecond: rate(old.writeOps, new.writeOps),
            totals: new)
    }
}

/// Reads disk space and disk traffic. None of this needs administrator rights.
public enum DiskSampler {
    private static let volumeKeys: Set<URLResourceKey> = [
        .volumeNameKey, .volumeLocalizedFormatDescriptionKey, .volumeTotalCapacityKey,
        .volumeAvailableCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
    ]

    /// The startup disk. The "important usage" figure can take a moment to compute, so call
    /// this off the main thread and not every second.
    public static func startupVolume() -> VolumeStats? {
        volume(at: URL(fileURLWithPath: "/"))
    }

    /// Other local volumes (external drives, disk images), skipping hidden system volumes.
    /// Network shares are left out so a stalled server can't hold up sampling.
    public static func otherVolumes() -> [VolumeStats] {
        let urls = FileManager.default.mountedVolumeURLs(
            includingResourceValuesForKeys: [.volumeIsLocalKey, .volumeIsRootFileSystemKey],
            options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRootFileSystemKey])
            guard values?.volumeIsLocal == true, values?.volumeIsRootFileSystem != true else { return nil }
            return volume(at: url)
        }
    }

    static func volume(at url: URL) -> VolumeStats? {
        // A URL caches resource values, so each call needs a fresh one to see new figures.
        let fresh = URL(fileURLWithPath: url.path)
        guard let values = try? fresh.resourceValues(forKeys: volumeKeys),
              let total = values.volumeTotalCapacity, total > 0 else { return nil }
        let free = UInt64(max(values.volumeAvailableCapacity ?? 0, 0))
        let important = values.volumeAvailableCapacityForImportantUsage.map { UInt64(max($0, 0)) } ?? free
        return VolumeStats(
            name: values.volumeName ?? fresh.lastPathComponent,
            format: values.volumeLocalizedFormatDescription ?? "",
            total: UInt64(total), free: free, available: max(important, free))
    }

    /// Cumulative traffic across every disk, or `nil` when no block storage driver is found.
    public static func ioCounters() -> DiskIOCounters? {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iterator)
            == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        var total: DiskIOCounters?
        var driver = IOIteratorNext(iterator)
        while driver != 0 {
            if let stats = IORegistryEntryCreateCFProperty(driver, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                let counters = DiskIOCounters.counters(fromStatistics: stats)
                var sum = total ?? DiskIOCounters(bytesRead: 0, bytesWritten: 0, readOps: 0, writeOps: 0)
                sum.bytesRead &+= counters.bytesRead
                sum.bytesWritten &+= counters.bytesWritten
                sum.readOps &+= counters.readOps
                sum.writeOps &+= counters.writeOps
                total = sum
            }
            IOObjectRelease(driver)
            driver = IOIteratorNext(iterator)
        }
        return total
    }
}
