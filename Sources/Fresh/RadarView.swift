import MemoryCore
import SwiftUI

/// The Analyze button: a radar face that sweeps while scanning or cleaning, with a blip for
/// each large cache found. Drawn with plain shapes (Canvas costs ~55 MB here), and animated
/// only while there's work going on, so it costs nothing when idle.
struct RadarView: View {
    @Environment(CleanerStore.self) private var cleaner
    let diameter: CGFloat
    /// Plain `State` rather than `@State`, whose macro needs Xcode.
    private let hovering = State<Bool>(initialValue: false)

    private static let sweepDegreesPerSecond = 120.0
    private static let maxBlips = 48

    var body: some View {
        Button(action: cleaner.analyze) {
            ZStack {
                face
                if let since = cleaner.activitySince {
                    TimelineView(.animation(minimumInterval: 1 / 30)) { context in
                        let angle = context.date.timeIntervalSince(since) * Self.sweepDegreesPerSecond
                        ZStack {
                            sweep(at: angle)
                            blips(sweepAngle: angle)
                        }
                    }
                } else {
                    blips(sweepAngle: nil)
                }
                label
            }
            .frame(width: diameter, height: diameter)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .disabled(cleaner.phase == .scanning || cleaner.phase == .cleaning)
        .onHover { hovering.wrappedValue = $0 }
        .help(cleaner.phase == .idle ? "Look for caches" : "Scan again")
        .accessibilityLabel(cleaner.phase == .idle ? "Analyze caches" : "Scan again")
    }

    private var face: some View {
        ZStack {
            Circle().fill(Theme.Palette.frameCard)
            ForEach([1.0, 0.75, 0.5, 0.25], id: \.self) { scale in
                Circle()
                    .strokeBorder(Theme.Palette.frameHairline, lineWidth: 1)
                    .frame(width: diameter * scale, height: diameter * scale)
            }
            Crosshair().stroke(Theme.Palette.frameHairline, lineWidth: 1)
            Circle()
                .strokeBorder(hovering.wrappedValue ? Theme.Palette.primary : Theme.Palette.frameHairline,
                              lineWidth: hovering.wrappedValue ? 2 : 1)
        }
    }

    private func sweep(at angle: Double) -> some View {
        ZStack {
            Wedge(degrees: 60)
                .fill(AngularGradient(
                    colors: [Theme.Palette.primary.opacity(0), Theme.Palette.primary.opacity(0.45)],
                    center: .center, startAngle: .degrees(-60), endAngle: .zero))
            Wedge(degrees: 0).stroke(Theme.Palette.primary, lineWidth: 1.5)
        }
        .rotationEffect(.degrees(angle))
    }

    /// The largest caches as dots. Each keeps its place between scans (its angle comes from a
    /// hash of its id), sits on a ring by category, and grows with its size.
    private func blips(sweepAngle: Double?) -> some View {
        let largest = cleaner.items
            .compactMap { item in cleaner.sizes[item.id].map { (item, $0.bytes) } }
            .filter { $0.1 >= CleanerStore.minimumSize }
            .sorted { $0.1 > $1.1 }
            .prefix(Self.maxBlips)
        let biggest = Double(largest.first?.1 ?? 1)
        return ZStack {
            ForEach(Array(largest), id: \.0.id) { item, bytes in
                let hash = Self.hash(item.id)
                let angle = Double(hash % 360)
                let ring = Self.ring(item.category) + Double((hash >> 20) % 100) / 100 * 0.12
                let size = 4 + 7 * (Double(bytes) / biggest).squareRoot()
                // Brightest just after the sweep passes, fading as it comes round again.
                let behind = sweepAngle.map { (($0 - angle).truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360) }
                Circle()
                    .fill(Theme.Palette.primary)
                    .frame(width: size, height: size)
                    .opacity(behind.map { max(0.2, 1 - $0 / 300) } ?? 0.85)
                    .offset(x: cos(angle * .pi / 180) * ring * diameter / 2,
                            y: sin(angle * .pi / 180) * ring * diameter / 2)
            }
        }
    }

    private var label: some View {
        VStack(spacing: 2) {
            Text(Theme.label(title))
                .font(Theme.Typeface.captionMd)
                .foregroundStyle(Theme.Palette.onFrame)
            if let detail {
                Text(detail)
                    .font(Theme.Typeface.captionSm)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.onFrameMute)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Theme.Palette.frame.opacity(0.85), in: .rect(cornerRadius: Theme.buttonRadius))
    }

    private var title: String {
        switch cleaner.phase {
        case .idle: "Analyze"
        case .scanning: "Scanning"
        case .cleaning: "Cleaning"
        case .results, .done: "Scan Again"
        }
    }

    private var detail: String? {
        guard cleaner.phase == .scanning, !cleaner.items.isEmpty else { return nil }
        return PercentFormatter.format(Double(cleaner.sizedCount) / Double(cleaner.items.count))
    }

    private static func ring(_ category: CacheCategory) -> Double {
        switch category {
        case .browsers: 0.3
        case .apps: 0.5
        case .developer: 0.68
        case .logs, .other, .system: 0.82
        }
    }

    /// FNV-1a, so blip positions are the same on every launch (Swift's hashValue isn't).
    private static func hash(_ text: String) -> UInt64 {
        text.utf8.reduce(14_695_981_039_346_656_037) { ($0 ^ UInt64($1)) &* 1_099_511_628_211 }
    }
}

/// A pie slice from the centre, ending at angle 0 (pointing right) and `degrees` wide.
private struct Wedge: Shape {
    let degrees: Double

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        var path = Path()
        path.move(to: center)
        if degrees == 0 {
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        } else {
            path.addArc(center: center, radius: rect.width / 2, startAngle: .degrees(-degrees), endAngle: .zero,
                        clockwise: false)
            path.closeSubpath()
        }
        return path
    }
}

private struct Crosshair: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        return path
    }
}
