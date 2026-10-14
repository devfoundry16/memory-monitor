import MemoryCore
import SwiftUI

/// The Clean tab's header: the radar Analyze button, what was found, and per-category totals.
struct CleanerHeader: View {
    @Environment(CleanerStore.self) private var cleaner

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .center, spacing: Theme.Space.xxl) {
                RadarView(diameter: 168)
                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    HeroFigure(eyebrow: "Cache Cleaner", value: value, companion: companion, subtitle: subtitle)
                    buttons
                }
                Spacer()
            }

            CardGrid {
                card("Browsers", [.browsers], summary: "Web pages, images and scripts browsers keep.")
                card("Apps", [.apps], summary: "Caches of apps, including Electron apps like Slack.")
                card("Developer Tools", [.developer], summary: "Package and build caches; downloaded again when needed.")
                card("Logs & Other", [.logs, .other, .system], summary: "Logs and other apps' caches.")
            }
        }
    }

    private var value: String {
        switch cleaner.phase {
        case .idle: "Find space"
        case .scanning, .results: ByteFormatter.format(cleaner.foundBytes)
        case .cleaning: "Cleaning…"
        case .done: ByteFormatter.format(cleaner.report?.removedBytes ?? 0)
        }
    }

    private var companion: String? {
        switch cleaner.phase {
        case .results: "\(ByteFormatter.format(cleaner.selectedBytes)) selected"
        case .done: cleaner.report?.trashedFolder != nil ? "moved to the Trash" : "removed"
        default: nil
        }
    }

    private var subtitle: String {
        switch cleaner.phase {
        case .idle:
            return "Caches apps rebuild on their own. Nothing is deleted until you confirm."
        case .scanning:
            return "Measuring \(cleaner.sizedCount) of \(cleaner.items.count) cache folders…"
        case .results:
            return "\(cleaner.visibleItems.count) caches found · \(cleaner.selectedItems.count) selected"
        case .cleaning:
            if cleaner.stopping { return "Stopping after the current file…" }
            let name = cleaner.items.first { $0.id == cleaner.cleaningItem }?.name
            return name.map { "Cleaning \($0)…" } ?? "Cleaning…"
        case .done:
            guard let report = cleaner.report else { return "" }
            if report.mode == .moveToTrash {
                return report.trashedFolder != nil ? "Empty the Trash to free the space." : "Nothing was moved to the Trash."
            }
            return report.freeSpaceChange.map { "Free space up \(ByteFormatter.format(UInt64(max($0, 0))))" }
                ?? "Removed from disk."
        }
    }

    @ViewBuilder private var buttons: some View {
        HStack(spacing: Theme.Space.md) {
            switch cleaner.phase {
            case .idle:
                Button("Analyze", action: cleaner.analyze).buttonStyle(PrimaryButtonStyle())
            case .scanning, .cleaning:
                Button(cleaner.stopping ? "Stopping…" : "Stop", action: cleaner.stop)
                    .buttonStyle(OutlineButtonStyle(foreground: Theme.Palette.onFrame))
                    .disabled(cleaner.stopping)
            case .results, .done:
                Button("Clean Selected…", action: cleaner.requestClean)
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(cleaner.selectedItems.isEmpty)
                    .opacity(cleaner.selectedItems.isEmpty ? 0.4 : 1)
                Button("Scan Again", action: cleaner.analyze)
                    .buttonStyle(OutlineButtonStyle(foreground: Theme.Palette.onFrame))
            }
        }
    }

    private func card(_ title: String, _ categories: [CacheCategory], summary: String) -> some View {
        let items = cleaner.visibleItems.filter { categories.contains($0.category) }
        let found = items.reduce(UInt64(0)) { $0 + cleaner.bytes($1) }
        let selected = items.filter { cleaner.selection.contains($0.id) && !cleaner.inUse.contains($0.id) }
            .reduce(UInt64(0)) { $0 + cleaner.bytes($1) }
        return StatCard(
            title: title, value: cleaner.phase == .idle ? "—" : ByteFormatter.format(found),
            summary: summary,
            detail: items.isEmpty ? nil
                : "\(items.count) \(items.count == 1 ? "cache" : "caches") · " + (selected == 0 ? "none selected" : "\(ByteFormatter.format(selected)) selected"))
    }
}
