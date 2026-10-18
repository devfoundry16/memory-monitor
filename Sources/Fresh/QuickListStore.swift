import AppKit
import MemoryCore
import Observation

/// The apps and folders on the dropdown's quick list, and what can be done to them:
/// open, quit, take off the list, or move to the Trash after confirming.
@MainActor
@Observable
final class QuickListStore {
    private(set) var items: [QuickItem]
    /// Bundle IDs of running apps. Follows NSWorkspace's running-apps list itself rather than
    /// launch/quit notifications, which can be missed and leave an app marked running.
    private(set) var runningBundleIDs: Set<String> = []
    /// Installed apps for the Add App… picker, read when the picker first opens.
    private(set) var installedApps: [AppIndex.App] = []

    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var runningObservation: NSKeyValueObservation?

    private static let key = "quickItems"

    init() {
        let data = UserDefaults.standard.data(forKey: Self.key)
        items = data.flatMap { try? JSONDecoder().decode([QuickItem].self, from: $0) } ?? []
        refreshRunning()
        // KVO-compliant per Apple's docs; changes arrive on the main thread.
        runningObservation = NSWorkspace.shared.observe(\.runningApplications) { [weak self] _, _ in
            Task { @MainActor in self?.refreshRunning() }
        }
    }

    /// Reads the running apps again. Also called when the dropdown or Settings opens.
    func refreshRunning() {
        let running = Set(NSWorkspace.shared.runningApplications
            .filter { !$0.isTerminated }
            .compactMap(\.bundleIdentifier))
        if running != runningBundleIDs { runningBundleIDs = running }
    }

    // MARK: Looking things up

    /// Where the item is now: its saved path, or for an app that moved, wherever its bundle ID is.
    func resolvedURL(_ item: QuickItem) -> URL? {
        if FileManager.default.fileExists(atPath: item.path) { return item.url }
        guard item.kind == .app, let id = item.bundleID else { return nil }
        return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
    }

    func isRunning(_ item: QuickItem) -> Bool {
        item.kind == .app && item.bundleID.map(runningBundleIDs.contains) == true
    }

    func icon(_ item: QuickItem) -> NSImage {
        if let cached = icons[item.id] { return cached }
        let icon = NSWorkspace.shared.icon(forFile: resolvedURL(item)?.path ?? item.path)
        icons[item.id] = icon
        return icon
    }

    /// Why Move to Trash is unavailable for the item, or `nil` when it's allowed.
    func trashRefusal(_ item: QuickItem) -> String? {
        guard let url = resolvedURL(item) else { return "Not found." }
        return TrashPolicy.refusal(
            for: url, home: FileManager.default.homeDirectoryForCurrentUser, ownBundle: Bundle.main.bundleURL)
    }

    func contains(appAt url: URL) -> Bool {
        items.contains { $0.path == url.path }
    }

    func loadInstalledApps() {
        guard installedApps.isEmpty else { return }
        let home = FileManager.default.homeDirectoryForCurrentUser
        let directories = ["/Applications", "/Applications/Utilities", "/System/Applications",
                           "/System/Applications/Utilities"].map { URL(fileURLWithPath: $0) }
            + [home.appendingPathComponent("Applications")]
        Task {
            installedApps = await Task.detached { AppIndex(scanning: directories).apps }.value
        }
    }

    // MARK: Editing the list

    func add(app: AppIndex.App) {
        guard !contains(appAt: app.url) else { return }
        items.append(QuickItem(kind: .app, path: app.url.path, bundleID: app.bundleID))
        save()
    }

    func add(folders: [URL]) {
        for url in folders where !items.contains(where: { $0.path == url.path }) {
            items.append(QuickItem(kind: .folder, path: url.path))
        }
        save()
    }

    func remove(_ item: QuickItem) {
        items.removeAll { $0.id == item.id }
        icons[item.id] = nil
        save()
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    // MARK: Actions

    /// Launches or brings forward an app; opens a folder in Finder.
    func open(_ item: QuickItem) {
        guard let url = resolvedURL(item) else { return }
        switch item.kind {
        case .app: NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
        case .folder: NSWorkspace.shared.open(url)
        }
    }

    func revealInFinder(_ item: QuickItem) {
        guard let url = resolvedURL(item) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// Asks the app to quit, as if chosen from its menu. Never forced: an app with unsaved
    /// work can ask to save or cancel.
    func quit(_ item: QuickItem) {
        guard let id = item.bundleID else { return }
        NSRunningApplication.runningApplications(withBundleIdentifier: id).forEach { $0.terminate() }
    }

    /// Apps on the list that are running now.
    var runningApps: [QuickItem] { items.filter(isRunning) }
    var folders: [QuickItem] { items.filter { $0.kind == .folder } }

    /// Asks once, then politely quits every running app on the list. Apps with unsaved
    /// work still ask to save, and can cancel.
    func confirmQuitAll() {
        let apps = runningApps
        guard !apps.isEmpty else { return }
        let names = apps.map(\.name).formatted(.list(type: .and))
        guard confirm(
            apps.count == 1 ? "Quit \(names)?" : "Quit \(apps.count) apps?",
            info: (apps.count == 1 ? "" : "\(names). ") + "Apps with unsaved work will ask you to save first.",
            button: "Quit")
        else { return }
        apps.forEach(quit)
    }

    /// Folders on the list that exist and may be trashed.
    var trashableFolders: [QuickItem] {
        folders.filter { resolvedURL($0) != nil && trashRefusal($0) == nil }
    }

    /// Asks once, listing every folder, then moves them all to the Trash (undoable until it's
    /// emptied) and takes them off the list. Protected folders are skipped and named.
    func confirmTrashAllFolders() {
        let folders = trashableFolders
        guard !folders.isEmpty else { return }
        let skipped = self.folders.filter { resolvedURL($0) != nil && trashRefusal($0) != nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        func shown(_ item: QuickItem) -> String {
            item.path.hasPrefix(home + "/") ? "~" + item.path.dropFirst(home.count) : item.path
        }
        let listed = folders.prefix(10).map { "• " + shown($0) }
            + (folders.count > 10 ? ["…and \(folders.count - 10) more"] : [])
        var info = listed.joined(separator: "\n")
            + "\n\nEverything inside them goes too. You can put them back from the Trash until you empty it."
        if !skipped.isEmpty {
            info += "\n\nSkipped, because macOS needs them: " + skipped.map(\.name).formatted(.list(type: .and)) + "."
        }
        guard confirm(
            folders.count == 1 ? "Move “\(folders[0].name)” to the Trash?" : "Move \(folders.count) folders to the Trash?",
            info: info, button: "Move to Trash", destructive: true)
        else { return }
        Task {
            var failed: [String] = []
            for item in folders {
                // Already gone with a listed folder that contained it.
                guard let url = resolvedURL(item) else { remove(item); continue }
                do {
                    _ = try await NSWorkspace.shared.recycle([url])
                    remove(item)
                } catch {
                    failed.append("\(item.name): \(error.localizedDescription)")
                }
            }
            if !failed.isEmpty {
                showError("Some folders couldn't be moved to the Trash:\n" + failed.joined(separator: "\n"))
            }
        }
    }

    private func confirm(_ message: String, info: String, button: String, destructive: Bool = false) -> Bool {
        let alert = NSAlert()
        alert.alertStyle = destructive ? .warning : .informational
        alert.messageText = message
        alert.informativeText = info
        alert.addButton(withTitle: button).hasDestructiveAction = destructive
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        return alert.runModal() == .alertFirstButtonReturn
    }

    /// Asks first, quits an app, then moves the item to the Trash (undoable until emptied).
    func confirmAndTrash(_ item: QuickItem) {
        guard let url = resolvedURL(item), trashRefusal(item) == nil else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Move “\(item.name)” to the Trash?"
        var info = "You can put it back from the Trash until you empty it."
        if item.kind == .app {
            info += " \(item.name) will be quit first. Its settings and caches stay; the Clean tab can remove caches."
        }
        alert.informativeText = info
        alert.addButton(withTitle: "Move to Trash").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        Task { await trash(item, at: url) }
    }

    private func trash(_ item: QuickItem, at url: URL) async {
        if item.kind == .app, let id = item.bundleID {
            let running = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            running.forEach { $0.terminate() }
            for _ in 0..<50 where running.contains(where: { !$0.isTerminated }) {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if running.contains(where: { !$0.isTerminated }) {
                showError("\(item.name) didn't quit. Save your work in it and try again.")
                return
            }
        }
        do {
            _ = try await NSWorkspace.shared.recycle([url])
            remove(item)
        } catch {
            showError("Couldn't move \(item.name) to the Trash: \(error.localizedDescription)")
        }
    }

    private func showError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        NSApp.activate()
        alert.runModal()
    }
}
