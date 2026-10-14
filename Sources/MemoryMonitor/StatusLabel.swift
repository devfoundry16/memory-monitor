import AppKit
import MemoryCore

/// Draws the menu bar label (icons + figures) into one template image, so macOS tints
/// it correctly for light and dark menu bars.
@MainActor
enum StatusLabel {
    struct Segment: Equatable {
        let symbol: String
        let text: String
        /// The widest strings this figure can show. Its slot is sized to fit them, so the
        /// label keeps the same width when a value drops a digit (e.g. 22% → 0%).
        var widest: [String] = []
    }

    private static let widestPercent = "100%"

    static func segments(for store: MonitorStore) -> [Segment] {
        let settings = store.menuBarSettings
        var segments: [Segment] = []
        if settings.showMemory {
            let text = store.memory.map { memory -> String in
                let size = ByteFormatter.format(memory.used)
                let percent = PercentFormatter.format(memory.fractionOfTotal(memory.used))
                switch settings.memoryStyle {
                case .both: return "\(size) · \(percent)"
                case .size: return size
                case .percent: return percent
                }
            } ?? "—"
            // Sizes range from "0.0 MB" up to "88.88 GB" (or "888.88 GB" on a 100 GB+ Mac).
            var widestSizes = ["888.8 MB", "88.88 GB"]
            if let total = store.memory?.total, Double(total) >= 100 * ByteFormatter.gigabyte {
                widestSizes.append("888.88 GB")
            }
            let widest: [String] = switch settings.memoryStyle {
            case .both: widestSizes.map { "\($0) · \(widestPercent)" }
            case .size: widestSizes
            case .percent: [widestPercent]
            }
            segments.append(Segment(symbol: Resource.memory.symbol, text: text, widest: widest))
        }
        if settings.showCPU {
            segments.append(Segment(
                symbol: Resource.cpu.symbol, text: store.cpu.map { PercentFormatter.format($0.total) } ?? "—",
                widest: [widestPercent]))
        }
        if settings.showGPU {
            segments.append(Segment(
                symbol: Resource.gpu.symbol, text: store.gpu.map { PercentFormatter.format($0.device) } ?? "—",
                widest: [widestPercent]))
        }
        return segments
    }

    static func image(for store: MonitorStore) -> NSImage {
        image(segments: segments(for: store), showIcons: store.menuBarSettings.showIcons)
    }

    static func image(segments: [Segment], showIcons: Bool) -> NSImage {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.black]
        let symbolConfig = NSImage.SymbolConfiguration(pointSize: 12, weight: .medium)
        let height: CGFloat = 18
        let iconGap: CGFloat = 3
        let segmentGap: CGFloat = 10

        // With every figure turned off, keep a plain icon so the item stays clickable.
        let drawn = segments.isEmpty ? [Segment(symbol: Resource.memory.symbol, text: "")] : segments
        let showIcons = showIcons || segments.isEmpty

        let parts = drawn.map { segment -> (icon: NSImage?, text: NSAttributedString, slot: CGFloat) in
            let icon = showIcons ? symbol(segment.symbol, config: symbolConfig) : nil
            let text = NSAttributedString(string: segment.text, attributes: attributes)
            let slot = ([segment.text] + segment.widest)
                .map { ceil(NSAttributedString(string: $0, attributes: attributes).size().width) }
                .max() ?? 0
            return (icon, text, slot)
        }
        let widths = parts.map { part in
            (part.icon.map { $0.size.width + (part.slot > 0 ? iconGap : 0) } ?? 0) + part.slot
        }
        let width = widths.reduce(0, +) + segmentGap * CGFloat(max(parts.count - 1, 0))

        let image = NSImage(size: NSSize(width: max(width, 1), height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (part, partWidth) in zip(parts, widths) {
                var cursor = x
                if let icon = part.icon {
                    icon.draw(in: NSRect(x: cursor, y: (height - icon.size.height) / 2,
                                         width: icon.size.width, height: icon.size.height))
                    cursor += icon.size.width + iconGap
                }
                // Right-aligned in its slot: the icon stays put and the digits line up.
                let textSize = part.text.size()
                part.text.draw(at: NSPoint(x: cursor + part.slot - ceil(textSize.width), y: (height - textSize.height) / 2))
                x += partWidth + segmentGap
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    /// Symbol lookups are cached: the label is redrawn every second.
    private static var symbols: [String: NSImage] = [:]

    private static func symbol(_ name: String, config: NSImage.SymbolConfiguration) -> NSImage? {
        if let cached = symbols[name] { return cached }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        symbols[name] = image
        return image
    }
}
