import AppKit
import MemoryCore
import SwiftUI

/// Settings ▸ Quick List: the apps and folders in the dropdown, in order, with Add App…,
/// Add Folder…, and per-item Quit, Remove from List and Move to Trash….
struct QuickListSettings: View {
    @Environment(QuickListStore.self) private var quick
    /// Plain `State` rather than `@State`, whose macro needs Xcode.
    private let pickingApp = State(initialValue: false)

    private static let listHeight: CGFloat = 340

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            Text("Quick List")
                .font(Theme.Typeface.headingMd)
                .foregroundStyle(Theme.Palette.ink)
            Text("Apps and folders in the menu bar dropdown. Click one there to open it, or right-click it there to quit, remove or trash it. Drag rows here to reorder.")
                .font(Theme.Typeface.captionSm)
                .foregroundStyle(Theme.Palette.mute)

            Group {
                if quick.items.isEmpty {
                    Text("No apps or folders yet.")
                        .font(Theme.Typeface.body)
                        .foregroundStyle(Theme.Palette.mute)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List {
                        ForEach(quick.items) { item in
                            SettingsRow(item: item)
                                .listRowSeparator(.hidden)
                                .listRowBackground(Theme.Palette.canvas)
                        }
                        .onMove { quick.move(fromOffsets: $0, toOffset: $1) }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .frame(height: Self.listHeight)
            .background(Theme.Palette.canvas)
            .clipShape(.rect(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).strokeBorder(Theme.Palette.hairline, lineWidth: 1))

            HStack(spacing: Theme.Space.md) {
                Button("Add App…") { pickingApp.wrappedValue = true }
                    .buttonStyle(PrimaryButtonStyle())
                Button("Add Folder…", action: addFolders)
                    .buttonStyle(OutlineButtonStyle())
                Spacer()
                Button("Quit All Apps", action: quick.confirmQuitAll)
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(quick.runningApps.isEmpty)
                    .help("Quit every running app on the list. Asks first.")
                Button("Move All Folders to Trash…", action: quick.confirmTrashAllFolders)
                    .buttonStyle(OutlineButtonStyle())
                    .disabled(quick.trashableFolders.isEmpty)
                    .help(quick.trashableFolders.isEmpty
                          ? "No folders on the list can be moved to the Trash."
                          : "Delete every folder on the list (protected ones are skipped). Asks first, listing them all.")
            }
        }
        .sheet(isPresented: pickingApp.projectedValue) {
            AppPicker()
        }
        .onAppear(perform: quick.refreshRunning)
    }

    private func addFolders() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add"
        panel.message = "Choose folders to add to the Quick List."
        if panel.runModal() == .OK { quick.add(folders: panel.urls) }
    }
}

private struct SettingsRow: View {
    @Environment(QuickListStore.self) private var quick
    let item: QuickItem

    var body: some View {
        let found = quick.resolvedURL(item) != nil
        let running = quick.isRunning(item)
        let refusal = quick.trashRefusal(item)
        HStack(spacing: Theme.Space.md) {
            Image(nsImage: quick.icon(item)).resizable().frame(width: 20, height: 20)
                .opacity(found ? 1 : 0.4)
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: Theme.Space.sm) {
                    Text(item.name)
                        .font(Theme.Typeface.bodyStrong)
                        .foregroundStyle(found ? Theme.Palette.ink : Theme.Palette.mute)
                    if running {
                        Circle().fill(Theme.Palette.primary).frame(width: 6, height: 6).help("Running")
                    }
                }
                Text(found ? item.path : "Not found · \(item.path)")
                    .font(Theme.Typeface.captionSm)
                    .foregroundStyle(Theme.Palette.mute)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: Theme.Space.md)
            if running {
                rowButton("Quit", help: "Quit \(item.name)") { quick.quit(item) }
            }
            rowButton("Remove", help: "Take \(item.name) off the list. Nothing is deleted.") { quick.remove(item) }
            rowButton("Move to Trash…", help: refusal ?? "Move \(item.name) to the Trash. Asks first.") {
                quick.confirmAndTrash(item)
            }
            .disabled(refusal != nil)
        }
        .padding(.vertical, Theme.Space.xs)
        .contextMenu { QuickItemMenu(item: item) }
    }

    /// Outlined text buttons, so every action on a row is visible and named.
    private func rowButton(_ title: String, help: String, action: @escaping () -> Void) -> some View {
        Button(title, action: action)
            .buttonStyle(OutlineButtonStyle())
            .help(help)
    }
}

/// Installed apps with a search field. Clicking one adds it; added apps show a checkmark.
private struct AppPicker: View {
    @Environment(QuickListStore.self) private var quick
    @Environment(\.dismiss) private var dismiss
    private let query = State(initialValue: "")

    var body: some View {
        let needle = query.wrappedValue.trimmingCharacters(in: .whitespaces)
        let apps = quick.installedApps.filter { needle.isEmpty || $0.name.localizedCaseInsensitiveContains(needle) }
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            HStack {
                Text("Add App")
                    .font(Theme.Typeface.headingMd)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                SearchField(text: query.projectedValue, prompt: "Search apps")
            }
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(apps, id: \.url) { app in
                        PickerRow(app: app, added: quick.contains(appAt: app.url)) { quick.add(app: app) }
                    }
                }
            }
            .frame(height: 400)
            .overlay {
                if quick.installedApps.isEmpty {
                    ProgressView().controlSize(.small)
                } else if apps.isEmpty {
                    Text("No apps match “\(needle)”.").font(Theme.Typeface.body).foregroundStyle(Theme.Palette.mute)
                }
            }
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .background(Theme.Palette.canvas)
        .environment(\.colorScheme, Theme.bodyScheme)
        .onAppear { quick.loadInstalledApps() }
    }
}

private struct PickerRow: View {
    let app: AppIndex.App
    let added: Bool
    let add: () -> Void

    var body: some View {
        Button(action: add) {
            HStack(spacing: Theme.Space.md) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: app.url.path)).resizable().frame(width: 20, height: 20)
                Text(app.name)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
                if added {
                    Image(systemName: "checkmark").foregroundStyle(Theme.Palette.primary).help("On the list")
                }
            }
            .padding(.horizontal, Theme.Space.sm)
            .frame(height: 32)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(added)
        .overlay(alignment: .bottom) { Theme.Palette.hairline.opacity(0.6).frame(height: 1) }
    }
}
