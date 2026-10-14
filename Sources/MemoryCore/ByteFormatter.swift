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
