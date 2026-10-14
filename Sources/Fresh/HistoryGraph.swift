import MemoryCore
import SwiftUI

/// One band of a stacked history graph.
struct GraphSeries {
    let name: String
    let color: Color
}

/// The header's history graph: a caption with the range picker, then the values stacked
/// over time (0 at the bottom, the whole at the top). Hovering shows the values at that moment.
struct HistoryGraph: View {
    @Environment(MonitorStore.self) private var store
    let resource: Resource
    /// Bottom band first, matching the order of the history's values.
    let series: [GraphSeries]
    /// The hover readout for one point, e.g. "12.81 GB used".
    let describe: (MetricHistory.Point) -> String

    /// Pointer position while hovering. Plain `State` rather than `@State`, whose macro needs Xcode.
    private let hover = State<CGFloat?>(initialValue: nil)

    private static let height: CGFloat = 64
    /// Samples arrive every second; anything longer apart is a gap (sleep, a stall).
    private static let maxGap = 3.0

    var body: some View {
        @Bindable var store = store
        let end = store.historyTime
        let start = end - store.graphRange.seconds
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            GeometryReader { proxy in
                let segments = store.history[resource]?.segments(
                    from: start, to: end, maxPoints: max(1, Int(min(store.graphRange.seconds, proxy.size.width))),
                    maxGap: Self.maxGap) ?? []
                let hovered = hover.wrappedValue.flatMap {
                    nearest(to: $0, in: segments, start: start, end: end, width: proxy.size.width)
                }
                let plot = Plot(segments: segments, start: start, end: end, size: proxy.size, bands: series.count)
                ZStack(alignment: .topLeading) {
                    // Plain shapes rather than Canvas, which costs ~55 MB and extra CPU here.
                    plot.grid().stroke(Theme.Palette.frameHairline, lineWidth: 1)
                    ForEach(series.indices, id: \.self) { band in
                        plot.band(band).fill(series[band].color)
                    }
                    plot.topLine().stroke(Theme.Palette.onFrame.opacity(0.7), lineWidth: 1.5)
                    if let hovered {
                        plot.marker(at: hovered).stroke(Theme.Palette.onFrame.opacity(0.6), lineWidth: 1)
                        plot.dot(at: hovered).fill(Theme.Palette.onFrame)
                    }
                    Text(hovered.map { "\(ago(end - $0.time)) · \(describe($0))" } ?? " ")
                        .font(Theme.Typeface.captionSm)
                        .monospacedDigit()
                        .foregroundStyle(Theme.Palette.onFrame)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.Palette.frame.opacity(hovered == nil ? 0 : 0.85),
                                    in: .rect(cornerRadius: Theme.radius))
                        .padding(4)
                }
                .contentShape(.rect)
                .onContinuousHover { phase in
                    switch phase {
                    case .active(let location): hover.wrappedValue = location.x
                    case .ended: hover.wrappedValue = nil
                    }
                }
            }
            .frame(height: Self.height)
            .background(Theme.Palette.frameCard)
            .clipShape(.rect(cornerRadius: Theme.radius))

            HStack {
                Text(Theme.label(store.graphRange.caption))
                    .font(Theme.Typeface.captionMd)
                    .foregroundStyle(Theme.Palette.onFrameMute)
                Spacer()
                RangeTabs(selection: $store.graphRange)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(resource.title) history, \(store.graphRange.caption.lowercased())")
    }

    private func nearest(to locationX: CGFloat, in segments: [[MetricHistory.Point]],
                         start: Double, end: Double, width: CGFloat) -> MetricHistory.Point? {
        guard width > 0 else { return nil }
        let time = start + (end - start) * Double(locationX / width)
        let candidate = segments.joined().min { abs($0.time - time) < abs($1.time - time) }
        // Over a gap, show nothing rather than a far-away point.
        guard let candidate, abs(candidate.time - time) <= max(Self.maxGap, (end - start) / Double(width) * 4)
        else { return nil }
        return candidate
    }

    private func ago(_ seconds: Double) -> String {
        let s = Int(seconds.rounded())
        if s < 1 { return "Now" }
        if s < 60 { return "\(s) s ago" }
        return s % 60 == 0 ? "\(s / 60) min ago" : "\(s / 60) min \(s % 60) s ago"
    }
}

/// Turns history points into paths for a plot of the given size.
private struct Plot {
    let segments: [[MetricHistory.Point]]
    let start: Double
    let end: Double
    let size: CGSize
    let bands: Int

    func x(_ time: Double) -> CGFloat { size.width * CGFloat((time - start) / (end - start)) }
    func y(_ value: Double) -> CGFloat { size.height * CGFloat(1 - min(max(value, 0), 1)) }

    func grid() -> Path {
        var path = Path()
        for level in [0.25, 0.5, 0.75] {
            path.move(to: CGPoint(x: 0, y: y(level)))
            path.addLine(to: CGPoint(x: size.width, y: y(level)))
        }
        return path
    }

    /// The area between the stacked total below `band` and the total including it.
    func band(_ band: Int) -> Path {
        var path = Path()
        for points in drawable {
            let below = points.map { stacked($0, upTo: band) }
            let above = points.map { stacked($0, upTo: band + 1) }
            path.move(to: CGPoint(x: x(points[0].time), y: y(above[0])))
            for i in points.indices.dropFirst() { path.addLine(to: CGPoint(x: x(points[i].time), y: y(above[i]))) }
            for i in points.indices.reversed() { path.addLine(to: CGPoint(x: x(points[i].time), y: y(below[i]))) }
            path.closeSubpath()
        }
        return path
    }

    func topLine() -> Path {
        var path = Path()
        for points in drawable {
            path.move(to: CGPoint(x: x(points[0].time), y: y(stacked(points[0], upTo: bands))))
            for point in points.dropFirst() { path.addLine(to: CGPoint(x: x(point.time), y: y(stacked(point, upTo: bands)))) }
        }
        return path
    }

    func marker(at point: MetricHistory.Point) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x(point.time), y: 0))
        path.addLine(to: CGPoint(x: x(point.time), y: size.height))
        return path
    }

    func dot(at point: MetricHistory.Point) -> Path {
        Path(ellipseIn: CGRect(x: x(point.time) - 3, y: y(stacked(point, upTo: bands)) - 3, width: 6, height: 6))
    }

    /// Segments ready to draw: a lone point gets a sliver of width so it shows.
    private var drawable: [[MetricHistory.Point]] {
        segments.map { segment in
            segment.count == 1
                ? [MetricHistory.Point(time: segment[0].time - 0.5, values: segment[0].values), segment[0]]
                : segment
        }
    }

    private func stacked(_ point: MetricHistory.Point, upTo band: Int) -> Double {
        point.values.prefix(band).reduce(0, +)
    }
}

/// Small 1M / 10M / 1H tabs on the dark frame, styled like the resource tabs.
private struct RangeTabs: View {
    @Binding var selection: GraphRange

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(GraphRange.allCases, id: \.self) { range in
                let active = range == selection
                Button { selection = range } label: {
                    Text(range.shortTitle)
                        .font(Theme.Typeface.captionMd)
                        .foregroundStyle(active ? Theme.Palette.frame : Theme.Palette.onFrameMute)
                        .padding(.horizontal, 8)
                        .frame(height: 22)
                        .background(active ? Theme.Palette.onFrame : .clear, in: .rect(cornerRadius: Theme.buttonRadius))
                        .overlay {
                            if !active {
                                RoundedRectangle(cornerRadius: Theme.buttonRadius)
                                    .strokeBorder(Theme.Palette.frameHairline, lineWidth: 1)
                            }
                        }
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(range.caption)
            }
        }
    }
}
