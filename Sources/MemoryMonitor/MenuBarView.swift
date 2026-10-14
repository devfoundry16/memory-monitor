import MemoryCore
import SwiftUI

/// The dropdown panel under the menu bar item: a black NVIDIA "chapter".
struct MenuBarView: View {
    @Environment(MonitorStore.self) private var store
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(alignment: .top, spacing: Theme.Space.sm) {
                Tile(resource: .memory,
                     fraction: store.memory.map { $0.fractionOfTotal($0.used) },
                     detail: store.memory.map { ByteFormatter.format($0.used) } ?? "—",
                     color: store.memory.map { Theme.pressureColor($0.pressure) } ?? Theme.Palette.primary)
                Tile(resource: .cpu,
                     fraction: store.cpu?.total,
                     detail: store.loadAverage.first.map { String(format: "load %.2f", $0) } ?? "—")
                Tile(resource: .gpu,
                     fraction: store.gpu?.device,
                     detail: store.gpu.map { ByteFormatter.format($0.inUseMemory) } ?? "—")
            }

            divider
            VStack(spacing: Theme.Space.sm) {
                stat("Processes", store.snapshot.processCount.formatted())
                stat("Apps", store.appCount.formatted())
                stat("Threads", (store.snapshot.restrictedCount > 0 ? "≥ " : "") + store.snapshot.threadTotal.formatted())
                stat("Swap", store.memory.map { ByteFormatter.format($0.swapUsed) } ?? "—")
            }

            divider
            Eyebrow("Top Memory", color: Theme.Palette.onFrameMute)
                .help("Apps include all of their helper processes.")
            VStack(spacing: Theme.Space.sm) {
                ForEach(store.topEntries) { entry in
                    HStack(spacing: Theme.Space.sm) {
                        if let icon = entry.icon {
                            Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                        }
                        Text(entry.name)
                            .font(Theme.Typeface.body)
                            .foregroundStyle(Theme.Palette.onFrame)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer()
                        Text(entry.memory.map(ByteFormatter.format) ?? "—")
                            .font(Theme.Typeface.bodyStrong)
                            .monospacedDigit()
                            .foregroundStyle(Theme.Palette.onFrame)
                    }
                }
            }

            HStack(spacing: Theme.Space.sm) {
                Button("Open Monitor", action: onOpenMonitor)
                    .buttonStyle(PrimaryButtonStyle())
                Button(action: onOpenSettings) {
                    Image(systemName: "gearshape")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Theme.Palette.onFrameMute)
                        .frame(width: 32, height: 32)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Settings: theme and menu bar")
                Spacer()
                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(OutlineButtonStyle(foreground: Theme.Palette.onFrame))
                    .keyboardShortcut("q")
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 340)
        .background(Theme.Palette.frame)
        .environment(\.colorScheme, Theme.frameScheme)
    }

    private var divider: some View {
        Theme.Palette.frameHairline.frame(height: 1)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        HStack {
            Text(Theme.label(label)).font(Theme.Typeface.captionMd).foregroundStyle(Theme.Palette.onFrameMute)
            Spacer()
            Text(value).font(Theme.Typeface.bodyStrong).monospacedDigit().foregroundStyle(Theme.Palette.onFrame)
        }
    }
}

/// One resource in the dropdown: icon, name, big percentage, a detail line and a thin bar.
private struct Tile: View {
    let resource: Resource
    let fraction: Double?
    let detail: String
    var color: Color = Theme.Palette.primary

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            HStack(spacing: 4) {
                Image(systemName: resource.symbol).font(.system(size: 10, weight: .semibold))
                Text(Theme.label(resource.title)).font(Theme.Typeface.captionMd)
            }
            .foregroundStyle(Theme.Palette.onFrameMute)
            Text(fraction.map(PercentFormatter.format) ?? "—")
                .font(Theme.Typeface.font(24, bold: true, heading: true))
                .monospacedDigit()
                .foregroundStyle(color)
            Text(detail)
                .font(Theme.Typeface.captionSm)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.onFrameMute)
                .lineLimit(1)
            GeometryReader { proxy in
                Rectangle()
                    .fill(color)
                    .frame(width: proxy.size.width * CGFloat(min(max(fraction ?? 0, 0), 1)))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.Palette.frameCard)
            }
            .frame(height: 4)
            .clipShape(.rect(cornerRadius: Theme.radius))
        }
        .padding(Theme.Space.md)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.Palette.frameCard, in: .rect(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.Palette.frameHairline, lineWidth: 1))
    }
}
