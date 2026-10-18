import Foundation

/// Formats byte counts as "12.34 GB" at or above 1 GB, otherwise "512.3 MB".
/// Units are binary (1 GB = 1024³ bytes), matching Activity Monitor.
public enum ByteFormatter {
    public static let megabyte: Double = 1024 * 1024
    public static let gigabyte: Double = 1024 * 1024 * 1024

    public static func format(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        let mb = (value / megabyte * 10).rounded() / 10
        // Decide the unit after rounding so 1023.96 MB shows as "1.00 GB", not "1024.0 MB".
        if value >= gigabyte || mb >= 1024 {
            return String(format: "%.2f GB", value / gigabyte)
        }
        return String(format: "%.1f MB", mb)
    }
}

/// Formats a 0...1 fraction as a whole percentage, e.g. 0.786 → "79%".
/// Anything above zero that would round to 0 shows as "<1%".
public enum PercentFormatter {
    public static func format(_ fraction: Double) -> String {
        let percent = (fraction * 100).rounded()
        if percent == 0 && fraction > 0 { return "<1%" }
        return "\(Int(max(0, percent)))%"
    }
}

/// Disk sizes and disk traffic, in decimal units (1 GB = 1000³ bytes) as Finder and
/// System Settings ▸ Storage show them.
public enum DiskFormatter {
    /// "512.3 MB", "245.3 GB", "1.82 TB".
    public static func format(_ bytes: UInt64) -> String {
        let value = Double(bytes)
        // Decide the unit after rounding, so 999.96 GB shows as "1.00 TB", not "1000.0 GB".
        if (value / 1e9 * 10).rounded() / 10 >= 1000 { return String(format: "%.2f TB", value / 1e12) }
        if (value / 1e6 * 10).rounded() / 10 >= 1000 { return String(format: "%.1f GB", value / 1e9) }
        return String(format: "%.1f MB", value / 1e6)
    }

    /// "0 KB/s", "512 KB/s", "12.3 MB/s", "1.20 GB/s".
    public static func formatRate(_ bytesPerSecond: Double) -> String {
        let value = max(bytesPerSecond, 0)
        if (value / 1e6 * 10).rounded() / 10 >= 1000 { return String(format: "%.2f GB/s", value / 1e9) }
        if (value / 1e3).rounded() >= 1000 { return String(format: "%.1f MB/s", value / 1e6) }
        return String(format: "%.0f KB/s", value / 1e3)
    }
}
