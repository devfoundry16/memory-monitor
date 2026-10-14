import MemoryCore
import SwiftUI

struct MainWindowView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(spacing: 0) {
            HeaderView()
                .environment(\.colorScheme, Theme.frameScheme)
                // Separate from the Force Stop sheet below: one sheet modifier per view.
                .sheet(isPresented: $store.showingSettings) {
                    SettingsSheet()
                }
            ProcessListView()
                .environment(\.colorScheme, Theme.bodyScheme)
        }
        .background(Theme.Palette.canvas)
        .frame(minWidth: 1100, minHeight: 680)
        .sheet(item: $store.pendingStop) { request in
            ForceStopConfirm(request: request)
        }
    }
}

// MARK: - Process list (white body)

private enum Column {
    static let pid: CGFloat = 60
    static let user: CGFloat = 100
    static let parent: CGFloat = 150
    static let memory: CGFloat = 96
    static let usage: CGFloat = 70
    static let threads: CGFloat = 66
    static let action: CGFloat = 104
}

private struct ProcessListView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        let items = store.visibleItems
        VStack(spacing: 0) {
            HStack(spacing: Theme.Space.lg) {
                PillTabs(options: [(ProcessFilter.apps, "Apps"), (.all, "All Processes")], selection: $store.filter)
                SearchField(text: $store.query)
                Spacer()
                Text(store.filter == .apps
                     ? "\(store.groups.count) apps · totals include helper processes"
                     : "\(items.count.formatted()) shown")
                    .font(Theme.Typeface.captionSm)
                    .foregroundStyle(Theme.Palette.mute)
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.vertical, Theme.Space.lg)

            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                        ForEach(items) { item in
                            ProcessRowView(item: item, selected: item.id == store.selection)
                        }
                    } header: {
                        ColumnHeader()
                    }
                }
            }

            if let outcome = store.lastOutcome {
                OutcomeBanner(outcome: outcome)
            }
        }
        .background(Theme.Palette.canvas)
    }
}

private struct ColumnHeader: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            header("Name", .name).frame(maxWidth: .infinity, alignment: .leading)
            header("PID", .pid).frame(width: Column.pid, alignment: .trailing)
            header("User", .user).frame(width: Column.user, alignment: .leading)
            header("Parent", .parent).frame(width: Column.parent, alignment: .leading)
            header("Memory", .memory).frame(width: Column.memory, alignment: .trailing)
            header("CPU %", .cpu).frame(width: Column.usage, alignment: .trailing)
            header("GPU %", .gpu).frame(width: Column.usage, alignment: .trailing)
            header("Threads", .threads).frame(width: Column.threads, alignment: .trailing)
            Color.clear.frame(width: Column.action)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(height: 32)
        .background(Theme.Palette.surfaceSoft)
        .overlay(alignment: .bottom) { Theme.Palette.hairline.frame(height: 1) }
    }

    private func header(_ title: String, _ key: SortKey) -> some View {
        let active = store.sortKey == key
        return Button { store.toggleSort(key) } label: {
            HStack(spacing: Theme.Space.xs) {
                Text(Theme.label(title))
                    .font(Theme.Typeface.captionMd)
                    .foregroundStyle(active ? Theme.Palette.ink : Theme.Palette.mute)
                if active {
                    Image(systemName: store.sortAscending ? "chevron.up" : "chevron.down")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}

private struct ProcessRowView: View {
    @Environment(MonitorStore.self) private var store
    let item: ListItem
    let selected: Bool

    private var row: DisplayRow { item.row }

    var body: some View {
        let text = selected ? Theme.Palette.onSelection : Theme.Palette.ink
        let secondary = selected ? Theme.Palette.onSelectionMute : Theme.Palette.mute
        HStack(spacing: Theme.Space.md) {
            NameCell(item: item, text: text, secondary: secondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(String(row.process.pid))
                .font(Theme.Typeface.body).monospacedDigit()
                .foregroundStyle(secondary)
                .frame(width: Column.pid, alignment: .trailing)
            Text(row.process.user)
                .font(Theme.Typeface.body)
                .foregroundStyle(secondary)
                .lineLimit(1)
                .frame(width: Column.user, alignment: .leading)
            ParentCell(parent: row.parent, text: text, secondary: secondary)
                .frame(width: Column.parent, alignment: .leading)
            Text(memoryText)
                .font(Theme.Typeface.bodyStrong).monospacedDigit()
                .foregroundStyle(item.memory == nil ? secondary : text)
                .frame(width: Column.memory, alignment: .trailing)
            Text(item.cpuPercent.map { String(format: "%.1f", $0) } ?? "—")
                .font(Theme.Typeface.body).monospacedDigit()
                .foregroundStyle(usageColor(item.cpuPercent, text: text, secondary: secondary))
                .frame(width: Column.usage, alignment: .trailing)
            Text(item.gpuPercent.map { String(format: "%.1f", $0) } ?? "—")
                .font(Theme.Typeface.body).monospacedDigit()
                .foregroundStyle(usageColor(item.gpuPercent, text: text, secondary: secondary))
                .frame(width: Column.usage, alignment: .trailing)
            Text(item.threads.map { String($0) } ?? "—")
                .font(Theme.Typeface.body).monospacedDigit()
                .foregroundStyle(secondary)
                .frame(width: Column.threads, alignment: .trailing)

            // A fixed-width slot, so unselected rows keep the same columns as the header.
            Color.clear
                .frame(width: Column.action, height: 1)
                .overlay(alignment: .trailing) {
                    if selected { stopButton }
                }
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(height: 30)
        .background(background)
        .overlay(alignment: .bottom) { Theme.Palette.hairline.opacity(0.6).frame(height: 1) }
        .contentShape(.rect)
        .onTapGesture { store.selection = item.id }
        .contextMenu {
            Button(stopTitle + "…") { store.requestStop(item) }
                .disabled(row.protection == .protected)
        }
    }

    /// Idle values stay muted so the busy ones stand out.
    private func usageColor(_ percent: Double?, text: Color, secondary: Color) -> Color {
        (percent ?? 0) >= 0.05 ? text : secondary
    }

    private var background: Color {
        if selected { return Theme.Palette.selection }
        if case .member = item.kind { return Theme.Palette.surfaceSoft }
        return Theme.Palette.canvas
    }

    /// App totals are a lower bound when some helpers could not be read.
    private var memoryText: String {
        guard let memory = item.memory else { return "—" }
        let prefix = (item.group?.restrictedCount ?? 0) > 0 ? "≥ " : ""
        return prefix + ByteFormatter.format(memory)
    }

    private var stopTitle: String {
        if let group = item.group, group.processCount > 1 {
            return "Force Stop \(row.displayName) and its \(group.processCount - 1) other processes"
        }
        return "Force Stop \(row.displayName)"
    }

    @ViewBuilder private var stopButton: some View {
        if store.stopping.contains(row.id) {
            ProgressView().controlSize(.small).tint(Theme.Palette.primary)
        } else {
            Button("Force Stop") { store.requestStop(item) }
                .buttonStyle(OutlineButtonStyle(foreground: Theme.Palette.onSelection))
                .disabled(row.protection == .protected)
                .help(row.protection == .protected ? "Stopping this process would crash macOS." : stopTitle)
        }
    }
}

/// Icon and name. App groups get a disclosure arrow and their process count;
/// members are indented under their app.
private struct NameCell: View {
    @Environment(MonitorStore.self) private var store
    let item: ListItem
    let text: Color
    let secondary: Color

    var body: some View {
        let row = item.row
        HStack(spacing: Theme.Space.sm) {
            switch item.kind {
            case .appGroup(let group, let expanded):
                Button { store.toggleExpanded(row.id) } label: {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(Theme.Palette.primary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .frame(width: 16, height: 16)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help(expanded ? "Hide processes" : "Show processes")
                icon(row)
                name(row, bold: true)
                Text(group.processCount == 1 ? "1 process" : "\(group.processCount) processes")
                    .font(Theme.Typeface.captionSm)
                    .foregroundStyle(secondary)
                    .fixedSize()
            case .member(let isMain):
                Color.clear.frame(width: 16 + Theme.Space.sm, height: 1) // indent under the arrow
                icon(row)
                name(row, bold: false)
                if isMain {
                    Text(Theme.label("Main")).font(Theme.Typeface.captionMd).foregroundStyle(secondary)
                }
            case .process:
                icon(row)
                name(row, bold: row.isApp)
            }
            if row.protection == .critical {
                Text(Theme.label("Critical"))
                    .font(Theme.Typeface.captionMd)
                    .foregroundStyle(Theme.Palette.warning)
            }
        }
    }

    private func icon(_ row: DisplayRow) -> some View {
        Group {
            if let icon = row.icon {
                Image(nsImage: icon).resizable()
            } else {
                Image(systemName: "gearshape").foregroundStyle(secondary)
            }
        }
        .frame(width: 16, height: 16)
    }

    private func name(_ row: DisplayRow, bold: Bool) -> some View {
        // Members show the executable name, so "Google Chrome Helper (Renderer)" stays distinct.
        let title: String
        if case .member = item.kind { title = row.process.name } else { title = row.displayName }
        return Text(title)
            .font(bold ? Theme.Typeface.bodyStrong : Theme.Typeface.body)
            .foregroundStyle(text)
            .lineLimit(1)
            .truncationMode(.middle)
    }
}

/// The owning app (with icon) when there is one, otherwise the direct parent process.
private struct ParentCell: View {
    let parent: ParentInfo?
    let text: Color
    let secondary: Color

    var body: some View {
        if let parent {
            HStack(spacing: Theme.Space.xs) {
                if let icon = parent.icon {
                    Image(nsImage: icon).resizable().frame(width: 14, height: 14)
                }
                Text(parent.name)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(parent.isApp ? text : secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .help(parent.chain)
        } else {
            Text("—").font(Theme.Typeface.body).foregroundStyle(secondary)
        }
    }
}

private struct OutcomeBanner: View {
    @Environment(MonitorStore.self) private var store
    let outcome: StopOutcome

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Rectangle().fill(color).frame(width: 12, height: 12)
            Text(message).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.ink)
            Spacer()
            Button { store.lastOutcome = nil } label: {
                Image(systemName: "xmark").foregroundStyle(Theme.Palette.mute)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(height: 40)
        .background(Theme.Palette.surfaceSoft)
        .overlay(alignment: .top) { Theme.Palette.hairline.frame(height: 1) }
        .task(id: outcome.id) {
            try? await Task.sleep(for: .seconds(5))
            if store.lastOutcome?.id == outcome.id { store.lastOutcome = nil }
        }
    }

    private var color: Color {
        switch outcome.result {
        case .stopped, .alreadyExited: Theme.Palette.primary
        case .cancelledByUser: Theme.Palette.ash
        case .protected, .denied: Theme.Palette.error
        }
    }

    private var message: String {
        switch outcome.result {
        case .stopped: "Stopped \(outcome.name)."
        case .alreadyExited: "\(outcome.name) had already exited."
        case .cancelledByUser: "Cancelled. \(outcome.name) is still running."
        case .protected: "\(outcome.name) is protected and can't be stopped."
        case .denied(let reason): "Couldn't stop \(outcome.name): \(reason)"
        }
    }
}
