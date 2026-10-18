import MemoryCore
import SwiftUI

/// The dropdown panel under the menu bar item: a black NVIDIA "chapter".
struct MenuBarView: View {
    @Environment(MonitorStore.self) private var store
    @Environment(QuickListStore.self) private var quick
    let onOpenMonitor: () -> Void
    let onOpenSettings: () -> Void

    /// Every tile keeps the same width; the panel grows to fit more than three.
    private static let tileWidth: CGFloat = 92
    private static let minWidth: CGFloat = 340

    private var width: CGFloat {
        let count = CGFloat(store.menuBarSettings.dropdownTileCount)
        let tiles = count * Self.tileWidth + max(count - 1, 0) * Theme.Space.sm + Theme.Space.xl * 2
        return max(Self.minWidth, tiles)
    }

    var body: some View {
        let settings = store.menuBarSettings
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            if settings.dropdownTileCount > 0 {
                // Same order as the menu bar: Disk first.
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    if settings.dropdownDisk {
                        Tile(resource: .disk,
                             fraction: store.volume?.usedFraction,
                             detail: store.volume.map { "\(DiskFormatter.format($0.available)) free" } ?? "—")
                    }
                    if settings.dropdownMemory {
                        Tile(resource: .memory,
                             fraction: store.memory.map { $0.fractionOfTotal($0.used) },
                             detail: store.memory.map { ByteFormatter.format($0.used) } ?? "—",
                             color: store.memory.map { Theme.pressureColor($0.pressure) } ?? Theme.Palette.primary)
                    }
                    if settings.dropdownCPU {
                        Tile(resource: .cpu,
                             fraction: store.cpu?.total,
                             detail: store.loadAverage.first.map { String(format: "load %.2f", $0) } ?? "—")
                    }
                    if settings.dropdownGPU {
                        Tile(resource: .gpu,
                             fraction: store.gpu?.device,
                             detail: store.gpu.map { ByteFormatter.format($0.inUseMemory) } ?? "—")
                    }
                }

                divider
            }
            quickOpen

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
        .frame(width: width)
        .background(Theme.Palette.frame)
        .environment(\.colorScheme, Theme.frameScheme)
    }

    /// Rows shown before the quick list scrolls.
    private static let quickVisibleRows = 8
    private static let quickRowHeight: CGFloat = 18

    @ViewBuilder private var quickOpen: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack {
                Eyebrow("Quick Open", color: Theme.Palette.onFrameMute)
                    .help("Apps and folders you chose in Settings. Right-click one for more.")
                Spacer()
                if quick.runningApps.count > 1 {
                    Button("Quit All", action: quick.confirmQuitAll)
                        .buttonStyle(.plain)
                        .font(Theme.Typeface.captionMd)
                        .foregroundStyle(Theme.Palette.onFrameMute)
                        .help("Quit every running app on the list. Asks first.")
                }
            }
            if quick.items.isEmpty {
                HStack {
                    Text("Add apps and folders you use often.")
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.Palette.onFrameMute)
                    Spacer()
                    Button("Add in Settings") {
                        store.settingsSection = .quickList
                        onOpenSettings()
                    }
                    .buttonStyle(OutlineButtonStyle(foreground: Theme.Palette.onFrame))
                }
            } else {
                let rows = VStack(spacing: Theme.Space.sm) {
                    ForEach(quick.items) { QuickRow(item: $0) }
                }
                if quick.items.count > Self.quickVisibleRows {
                    let height = CGFloat(Self.quickVisibleRows) * (Self.quickRowHeight + Theme.Space.sm) - Theme.Space.sm
                    ScrollView { rows }.frame(height: height)
                } else {
                    rows
                }
            }
        }
        .onAppear(perform: quick.refreshRunning)
    }

    private var divider: some View {
        Theme.Palette.frameHairline.frame(height: 1)
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

/// One app or folder in the dropdown: click to open; running apps get a Quit button.
private struct QuickRow: View {
    @Environment(QuickListStore.self) private var quick
    let item: QuickItem

    var body: some View {
        let found = quick.resolvedURL(item) != nil
        let running = quick.isRunning(item)
        HStack(spacing: Theme.Space.sm) {
            Image(nsImage: quick.icon(item)).resizable().frame(width: 14, height: 14)
                .opacity(found ? 1 : 0.4)
            Text(item.name)
                .font(Theme.Typeface.body)
                .foregroundStyle(found ? Theme.Palette.onFrame : Theme.Palette.onFrameMute)
                .lineLimit(1)
                .truncationMode(.middle)
            if running {
                Circle().fill(Theme.Palette.primary).frame(width: 6, height: 6)
                    .help("Running")
            }
            Spacer()
            if !found {
                Text("Not found").font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.onFrameMute)
            } else if running {
                Button("Quit") { quick.quit(item) }
                    .buttonStyle(.plain)
                    .font(Theme.Typeface.captionMd)
                    .foregroundStyle(Theme.Palette.onFrameMute)
                    .help("Quit \(item.name)")
            }
        }
        .frame(height: 18)
        .contentShape(.rect)
        .onTapGesture { if found { quick.open(item) } }
        .help(found ? item.path : "\(item.path) is no longer there")
        .contextMenu { QuickItemMenu(item: item) }
    }
}

/// The right-click menu for a quick list item, shared by the dropdown and Settings.
struct QuickItemMenu: View {
    @Environment(QuickListStore.self) private var quick
    let item: QuickItem

    var body: some View {
        let found = quick.resolvedURL(item) != nil
        if found {
            Button("Open") { quick.open(item) }
            if quick.isRunning(item) { Button("Quit \(item.name)") { quick.quit(item) } }
            Button("Show in Finder") { quick.revealInFinder(item) }
            Divider()
        }
        Button("Remove from List") { quick.remove(item) }
        if found {
            Button("Move to Trash…") { quick.confirmAndTrash(item) }
                .disabled(quick.trashRefusal(item) != nil)
        }
    }
}
