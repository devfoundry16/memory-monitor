import MemoryCore
import SwiftUI

/// The Clean tab's body: caches grouped by category and app, with checkboxes.
struct CleanerListView: View {
    @Environment(CleanerStore.self) private var cleaner

    var body: some View {
        @Bindable var cleaner = cleaner
        VStack(spacing: 0) {
            if cleaner.phase == .idle {
                CleanerExplainer()
            } else {
                toolbar
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                        ForEach(cleaner.sections) { section in
                            Section {
                                ForEach(section.groups) { group in
                                    GroupRows(group: group)
                                }
                            } header: {
                                SectionHeader(section: section)
                            }
                        }
                        footnote
                    }
                }
            }
            if let report = cleaner.report {
                CleanReportBanner(report: report)
            }
        }
        .background(Theme.Palette.canvas)
        .sheet(isPresented: $cleaner.showingConfirm) {
            CleanConfirm()
        }
    }

    private var toolbar: some View {
        HStack(spacing: Theme.Space.md) {
            Button("Select Recommended", action: cleaner.selectRecommended).buttonStyle(OutlineButtonStyle())
            Button("Deselect All", action: cleaner.deselectAll).buttonStyle(OutlineButtonStyle())
            Spacer()
            Text("Caution items and apps that are running start unchecked")
                .font(Theme.Typeface.captionSm)
                .foregroundStyle(Theme.Palette.mute)
        }
        .disabled(cleaner.phase == .cleaning)
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.vertical, Theme.Space.lg)
    }

    @ViewBuilder private var footnote: some View {
        let notes = [
            cleaner.hiddenSmallCount > 0 ? "\(cleaner.hiddenSmallCount) caches under 1 MB not shown" : nil,
            cleaner.noAccessCount > 0 ? "\(cleaner.noAccessCount) folders macOS protects were skipped" : nil,
        ].compactMap { $0 }
        if !notes.isEmpty {
            Text(notes.joined(separator: " · "))
                .font(Theme.Typeface.captionSm)
                .foregroundStyle(Theme.Palette.mute)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Space.xxl)
                .padding(.vertical, Theme.Space.lg)
        }
    }
}

// MARK: - Rows

private enum Layout {
    static let size: CGFloat = 90
    static let actions: CGFloat = 130
    static let rowHeight: CGFloat = 48
}

private struct SectionHeader: View {
    @Environment(CleanerStore.self) private var cleaner
    let section: CleanerSection

    var body: some View {
        let items = section.groups.flatMap(\.items)
        HStack(spacing: Theme.Space.md) {
            Button { cleaner.toggleAll(items) } label: { CheckBox(cleaner.checkState(items)) }
                .buttonStyle(.plain)
                .disabled(cleaner.phase == .cleaning)
            Text(Theme.label(section.category.title))
                .font(Theme.Typeface.captionMd)
                .foregroundStyle(Theme.Palette.ink)
            Spacer()
            Text(ByteFormatter.format(cleaner.total(section)))
                .font(Theme.Typeface.captionMd)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: Layout.size, alignment: .trailing)
            Spacer().frame(width: Layout.actions)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(height: 32)
        .background(Theme.Palette.surfaceSoft)
        .overlay(alignment: .bottom) { Theme.Palette.hairline.frame(height: 1) }
    }
}

/// An app with one cache shows as a single row; with several, as an expandable group.
private struct GroupRows: View {
    @Environment(CleanerStore.self) private var cleaner
    let group: CleanerGroup

    var body: some View {
        if group.items.count == 1 {
            ItemRow(item: group.items[0], indented: false)
        } else {
            let expanded = cleaner.expanded.contains(group.id)
            HStack(spacing: Theme.Space.md) {
                Button { cleaner.toggleAll(group.items) } label: { CheckBox(cleaner.checkState(group.items)) }
                    .buttonStyle(.plain)
                    .disabled(cleaner.phase == .cleaning || group.items.allSatisfy { cleaner.inUse.contains($0.id) })
                Button {
                    if expanded { cleaner.expanded.remove(group.id) } else { cleaner.expanded.insert(group.id) }
                } label: {
                    HStack(spacing: Theme.Space.sm) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .bold))
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                            .foregroundStyle(Theme.Palette.mute)
                            .frame(width: 10)
                        CacheIcon(item: group.items[0])
                        Text(group.name).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.ink)
                        Text("\(group.items.count) caches").font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.mute)
                        if group.items.contains(where: { cleaner.inUse.contains($0.id) }) {
                            Badge(text: "In use", color: Theme.Palette.warning)
                        }
                        Spacer()
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                Text(ByteFormatter.format(cleaner.total(group)))
                    .font(Theme.Typeface.bodyStrong)
                    .monospacedDigit()
                    .foregroundStyle(Theme.Palette.ink)
                    .frame(width: Layout.size, alignment: .trailing)
                Spacer().frame(width: Layout.actions)
            }
            .padding(.horizontal, Theme.Space.xxl)
            .frame(height: Layout.rowHeight)
            .overlay(alignment: .bottom) { Theme.Palette.hairline.frame(height: 1) }

            if expanded {
                ForEach(group.items) { ItemRow(item: $0, indented: true) }
            }
        }
    }
}

private struct ItemRow: View {
    @Environment(CleanerStore.self) private var cleaner
    let item: CacheItem
    let indented: Bool

    var body: some View {
        let inUse = cleaner.inUse.contains(item.id)
        let size = cleaner.sizes[item.id]
        HStack(spacing: Theme.Space.md) {
            Button { cleaner.toggle(item) } label: {
                CheckBox(isOn: cleaner.selection.contains(item.id) && !inUse).opacity(inUse ? 0.4 : 1)
            }
            .buttonStyle(.plain)
            .disabled(inUse || cleaner.phase == .cleaning)
            .help(inUse ? "\(item.owner?.name ?? item.name) is running. Quit it to clean this." : "")
            if indented { Spacer().frame(width: 28) }
            CacheIcon(item: item)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Theme.Space.sm) {
                    Text(item.name).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.ink).lineLimit(1)
                    if let detail = item.detail {
                        Text(detail).font(Theme.Typeface.captionSm).foregroundStyle(Theme.Palette.mute).lineLimit(1)
                    }
                    if inUse {
                        Badge(text: isQuitting ? "Quitting" : "In use", color: Theme.Palette.warning)
                    }
                    if cleaner.cleaningItem == item.id {
                        Badge(text: "Cleaning", color: Theme.Palette.primary)
                    }
                }
                subtitle
            }
            Spacer(minLength: Theme.Space.md)
            Text(size.map { ($0.unreadable > 0 ? "≥ " : "") + ByteFormatter.format($0.bytes) } ?? "—")
                .font(Theme.Typeface.body)
                .monospacedDigit()
                .foregroundStyle(Theme.Palette.ink)
                .frame(width: Layout.size, alignment: .trailing)
            HStack(spacing: Theme.Space.sm) {
                Spacer(minLength: 0)
                if inUse, cleaner.runningApp(for: item) != nil, !isQuitting {
                    Button("Quit") { cleaner.quit(item) }
                        .buttonStyle(OutlineButtonStyle())
                        .help("Ask \(item.owner?.name ?? item.name) to quit, so its cache can be cleaned")
                }
                Button { cleaner.reveal(item) } label: {
                    Image(systemName: "folder").foregroundStyle(Theme.Palette.mute)
                }
                .buttonStyle(.plain)
                .help("Show in Finder")
            }
            .frame(width: Layout.actions)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(height: Layout.rowHeight)
        .overlay(alignment: .bottom) { Theme.Palette.hairline.frame(height: 1) }
        .contextMenu {
            ForEach(item.targets, id: \.url) { target in
                Button(abbreviated(target.url)) { NSWorkspace.shared.activateFileViewerSelecting([target.url]) }
            }
        }
    }

    private var isQuitting: Bool { item.owner.map { cleaner.quitting.contains($0.key) } ?? false }

    @ViewBuilder private var subtitle: some View {
        if let advisory = item.advisory {
            Text(advisory.text)
                .font(Theme.Typeface.captionSm)
                .foregroundStyle(advisory.isCaution ? Theme.Palette.warning : Theme.Palette.mute)
                .lineLimit(1)
                .help(advisory.text)
        } else {
            let paths = item.targets.map(\.url)
            Text(abbreviated(paths[0]) + (paths.count > 1 ? "  +\(paths.count - 1) more" : ""))
                .font(Theme.Typeface.captionSm)
                .foregroundStyle(Theme.Palette.mute)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(paths.map(abbreviated).joined(separator: "\n"))
        }
    }

    private func abbreviated(_ url: URL) -> String {
        let home = NSHomeDirectory()
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

/// The owning app's icon, or a symbol for the kind of cache.
private struct CacheIcon: View {
    @Environment(CleanerStore.self) private var cleaner
    let item: CacheItem

    var body: some View {
        Group {
            if let icon = cleaner.icon(for: item) {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: item.category.symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.mute)
            }
        }
        .frame(width: 20, height: 20)
    }
}

extension CacheCategory {
    var title: String {
        switch self {
        case .browsers: "Browsers"
        case .apps: "Apps"
        case .developer: "Developer Tools"
        case .logs: "Logs"
        case .other: "Other Caches"
        case .system: "macOS"
        }
    }

    var symbol: String {
        switch self {
        case .browsers: "globe"
        case .apps: "app"
        case .developer: "hammer"
        case .logs: "doc.text"
        case .other: "folder"
        case .system: "gearshape"
        }
    }
}

// MARK: - Before the first scan

private struct CleanerExplainer: View {
    var body: some View {
        HStack(alignment: .top, spacing: Theme.Space.xxl) {
            block("What it looks at", [
                "Browser caches: Chrome, Firefox, Edge, Brave, Arc",
                "App caches, including Electron apps like Slack, Notion and VS Code",
                "Developer caches: npm, Homebrew, uv, pip, Xcode and more",
                "Logs in ~/Library/Logs",
            ])
            block("What it never touches", [
                "Your documents, and app data like IndexedDB, Local Storage and Cookies",
                "Containers, Mail, Messages, Safari and other private folders",
                "System folders that need an administrator password",
                "Caches of apps that are running (until you quit them)",
            ])
            block("How it works", [
                "Analyze measures each cache; nothing changes yet",
                "Tick what to remove; safe items are pre-selected",
                "Choose Move to Trash (undoable) or Delete Permanently",
                "Apps rebuild caches as they need them",
            ])
        }
        .padding(Theme.Space.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func block(_ title: String, _ lines: [String]) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Eyebrow(title)
            ForEach(lines, id: \.self) { line in
                HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                    Rectangle().fill(Theme.Palette.primary).frame(width: 6, height: 6)
                    Text(line).font(Theme.Typeface.body).foregroundStyle(Theme.Palette.body)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - After cleaning

private struct CleanReportBanner: View {
    @Environment(CleanerStore.self) private var cleaner
    let report: CleanReport

    var body: some View {
        HStack(spacing: Theme.Space.md) {
            Rectangle().fill(problems > 0 ? Theme.Palette.warning : Theme.Palette.primary).frame(width: 12, height: 12)
            Text(message).font(Theme.Typeface.bodyStrong).foregroundStyle(Theme.Palette.ink).lineLimit(2)
            Spacer()
            Button(action: cleaner.dismissReport) {
                Image(systemName: "xmark").foregroundStyle(Theme.Palette.mute)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, Theme.Space.xxl)
        .frame(minHeight: 40)
        .background(Theme.Palette.surfaceSoft)
        .overlay(alignment: .top) { Theme.Palette.hairline.frame(height: 1) }
        .help(failureDetails)
    }

    private var cleaned: Int { report.results.filter { $0.status == .cleaned || $0.removedBytes > 0 }.count }
    private var skipped: Int { report.results.filter { $0.status == .skippedInUse }.count }
    private var stopped: Int { report.results.filter { $0.status == .cancelled }.count }
    private var problems: Int {
        report.results.filter {
            if case .refused = $0.status { return true }
            return !$0.failures.isEmpty
        }.count
    }

    private var message: String {
        let size = ByteFormatter.format(report.removedBytes)
        var parts: [String]
        switch report.mode {
        case .moveToTrash where report.trashedFolder != nil:
            parts = ["Moved \(size) from \(cleaned) caches to the Trash. Empty the Trash to free the space"]
        case .moveToTrash:
            parts = ["Couldn't move to the Trash, so nothing was removed"]
        case .deletePermanently:
            parts = ["Removed \(size) from \(cleaned) caches"]
        }
        if let change = report.freeSpaceChange, change > 0 {
            parts.append("free space +\(ByteFormatter.format(UInt64(change)))")
        }
        if stopped > 0 { parts.append("stopped before \(stopped) caches") }
        if skipped > 0 { parts.append("\(skipped) skipped (app running)") }
        if problems > 0 { parts.append("\(problems) not fully cleaned (hover for details)") }
        return parts.joined(separator: " · ")
    }

    private var failureDetails: String {
        report.results.flatMap { result -> [String] in
            if case .refused(let reason) = result.status { return ["\(result.id): refused (\(reason))"] }
            return result.failures.prefix(3).map { "\($0.path): \($0.reason)" }
        }
        .prefix(12)
        .joined(separator: "\n")
    }
}
