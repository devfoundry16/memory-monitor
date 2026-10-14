import AppKit
import MemoryCore
import Observation

/// One app's (or tool's) caches in the Clean list.
struct CleanerGroup: Identifiable {
    let id: String
    let name: String
    let items: [CacheItem]
}

/// A category in the Clean list, largest group first.
struct CleanerSection: Identifiable {
    let category: CacheCategory
    let groups: [CleanerGroup]
    var id: CacheCategory { category }
}

@MainActor
@Observable
final class CleanerStore {
    enum Phase: Equatable {
        case idle, scanning, results, cleaning, done
    }

    /// Items under this size are left out of the list.
    static let minimumSize: UInt64 = 1 << 20

    private(set) var phase = Phase.idle
    private(set) var items: [CacheItem] = []
    private(set) var sizes: [CacheItem.ID: CacheSize] = [:]
    private(set) var selection: Set<CacheItem.ID> = []
    private(set) var sections: [CleanerSection] = []
    /// Items whose app or tool is running; they can't be selected.
    private(set) var inUse: Set<CacheItem.ID> = []
    /// Owner keys of apps asked to quit, so their caches can be selected once they have.
    private(set) var quitting: Set<String> = []
    private(set) var noAccessCount = 0
    private(set) var report: CleanReport?
    private(set) var cleaningItem: CacheItem.ID?
    /// Stop was pressed during a clean, which is finishing the file it's on.
    private(set) var stopping = false
    /// When the current scan or clean started; drives the radar sweep.
    private(set) var activitySince: Date?
    var showingConfirm = false
    var expanded: Set<String> = []

    // Bookkeeping that views don't read directly, so changing it doesn't redraw anything.
    /// Choices the user made themselves, which later updates leave alone.
    @ObservationIgnored private var touched: Set<CacheItem.ID> = []
    @ObservationIgnored private var pendingSizes: [CacheItem.ID: CacheSize] = [:]
    @ObservationIgnored private var lastFlush = Date.distantPast
    @ObservationIgnored private var work: Task<Void, Never>?
    @ObservationIgnored private var cleanControl: CleanControl?
    /// Filled while views draw, so it must not trigger observation.
    @ObservationIgnored private var icons: [String: NSImage] = [:]
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    @ObservationIgnored private var runningBundleIDs: Set<String> = []
    @ObservationIgnored private var processNames: Set<String> = []
    let environment = CacheEnvironment.current

    init() {
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification] {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshRunning() }
            })
        }
    }

    // MARK: Derived values

    var visibleItems: [CacheItem] { sections.flatMap { $0.groups.flatMap(\.items) } }
    var foundBytes: UInt64 { visibleItems.reduce(0) { $0 + (sizes[$1.id]?.bytes ?? 0) } }
    var selectedBytes: UInt64 { selectedItems.reduce(0) { $0 + (sizes[$1.id]?.bytes ?? 0) } }
    var selectedItems: [CacheItem] { visibleItems.filter { selection.contains($0.id) && !inUse.contains($0.id) } }
    var sizedCount: Int { items.filter { sizes[$0.id] != nil }.count }
    var hiddenSmallCount: Int {
        items.filter { (sizes[$0.id]?.bytes).map { $0 < Self.minimumSize } ?? false }.count
    }

    func icon(for item: CacheItem) -> NSImage? {
        guard let owner = item.owner else { return nil }
        if let icon = icons[owner.key] { return icon }
        for bundleID in owner.bundleIDs {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                let icon = NSWorkspace.shared.icon(forFile: url.path)
                icons[owner.key] = icon
                return icon
            }
        }
        return nil
    }

    func runningApp(for item: CacheItem) -> NSRunningApplication? {
        guard let owner = item.owner else { return nil }
        return owner.bundleIDs.lazy.compactMap { NSRunningApplication.runningApplications(withBundleIdentifier: $0).first }.first
    }

    // MARK: Scanning

    func analyze() {
        work?.cancel()
        phase = .scanning
        activitySince = Date()
        items = []
        sizes = [:]
        selection = []
        touched = []
        sections = []
        report = nil
        pendingSizes = [:]
        let scanner = CacheScanner(environment: environment)
        work = Task {
            await refreshRunningAsync()
            for await event in scanner.scan() {
                switch event {
                case .discovered(let result):
                    items = result.items
                    noAccessCount = result.noAccess.count
                    updateInUse()
                    selection = Set(items.filter { $0.isRecommended && !inUse.contains($0.id) }.map(\.id))
                case .sized(let id, let size):
                    pendingSizes[id] = size
                    if Date().timeIntervalSince(lastFlush) > 0.15 { flushSizes() }
                case .finished:
                    break
                }
            }
            flushSizes()
            guard !Task.isCancelled else { return }
            phase = .results
            activitySince = nil
        }
    }

    /// Stops a scan straight away. A clean stops after the file it's on, then reports what it did.
    func stop() {
        if phase == .cleaning {
            cleanControl?.stop()
            stopping = true
            return
        }
        work?.cancel()
        work = nil
        flushSizes()
        activitySince = nil
        phase = items.isEmpty ? .idle : .results
    }

    private func flushSizes() {
        guard !pendingSizes.isEmpty else { return }
        sizes.merge(pendingSizes) { $1 }
        pendingSizes = [:]
        lastFlush = Date()
        // Small items drop out of the list, and out of the selection with them.
        for (id, size) in sizes where size.bytes < Self.minimumSize { selection.remove(id) }
        updateSections()
    }

    private func updateSections() {
        let shown = items.filter { item in sizes[item.id].map { $0.bytes >= Self.minimumSize } ?? false }
        sections = CacheCategory.allCases.compactMap { category in
            let inCategory = shown.filter { $0.category == category }
            guard !inCategory.isEmpty else { return nil }
            let grouped = Dictionary(grouping: inCategory) { $0.owner?.key ?? $0.id }
            let groups = grouped.map { key, members in
                CleanerGroup(id: key, name: members[0].owner?.name ?? members[0].name,
                             items: members.sorted { bytes($0) > bytes($1) })
            }
            return CleanerSection(category: category, groups: groups.sorted { total($0) > total($1) })
        }
    }

    func bytes(_ item: CacheItem) -> UInt64 { sizes[item.id]?.bytes ?? 0 }
    func total(_ group: CleanerGroup) -> UInt64 { group.items.reduce(0) { $0 + bytes($1) } }
    func total(_ section: CleanerSection) -> UInt64 { section.groups.reduce(0) { $0 + total($1) } }

    // MARK: Selection

    func toggle(_ item: CacheItem) {
        guard !inUse.contains(item.id) else { return }
        touched.insert(item.id)
        if selection.contains(item.id) { selection.remove(item.id) } else { selection.insert(item.id) }
    }

    func checkState(_ items: [CacheItem]) -> CheckBox.Value {
        let selectable = items.filter { !inUse.contains($0.id) }
        let chosen = selectable.filter { selection.contains($0.id) }.count
        return chosen == 0 ? .off : chosen == selectable.count ? .on : .mixed
    }

    /// Selects all of `items` unless all are selected, in which case it clears them.
    func toggleAll(_ items: [CacheItem]) {
        let selectable = items.filter { !inUse.contains($0.id) }
        let select = checkState(selectable) != .on
        for item in selectable {
            touched.insert(item.id)
            if select { selection.insert(item.id) } else { selection.remove(item.id) }
        }
    }

    func selectRecommended() {
        touched = []
        selection = Set(visibleItems.filter { $0.isRecommended && !inUse.contains($0.id) }.map(\.id))
    }

    func deselectAll() {
        touched = Set(items.map(\.id))
        selection = []
    }

    // MARK: Running apps

    /// Asks the app to quit, as if chosen from its menu. Its caches get selected once it has.
    func quit(_ item: CacheItem) {
        guard let owner = item.owner, let app = runningApp(for: item) else { return }
        quitting.insert(owner.key)
        app.terminate()
        Task {
            try? await Task.sleep(for: .seconds(10))
            quitting.remove(owner.key) // gave up waiting, e.g. it asked to save a document
        }
    }

    func refreshRunning() {
        Task { await refreshRunningAsync() }
    }

    private func refreshRunningAsync() async {
        runningBundleIDs = Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        processNames = await Task.detached { RunningProbe.runningToolNames(ProcessSampler().sample().rows) }.value
        updateInUse()
    }

    private func updateInUse() {
        let wasInUse = inUse
        inUse = Set(items.filter { item in
            item.owner.map { RunningProbe.isRunning($0, runningBundleIDs: runningBundleIDs, processNames: processNames) }
                ?? false
        }.map(\.id))
        for id in inUse { selection.remove(id) }
        // Apps the user quit from here: select their safe caches now that they're free.
        for item in items where wasInUse.contains(item.id) && !inUse.contains(item.id) {
            guard let key = item.owner?.key, quitting.contains(key) else { continue }
            if item.isRecommended { selection.insert(item.id) }
            quitting.remove(key)
        }
    }

    // MARK: Cleaning

    func requestClean() {
        Task {
            await refreshRunningAsync()
            if !selectedItems.isEmpty { showingConfirm = true }
        }
    }

    func confirmClean(_ mode: CleanMode) {
        showingConfirm = false
        let chosen = selectedItems
        guard phase != .cleaning, phase != .scanning, !chosen.isEmpty else { return }
        phase = .cleaning
        activitySince = Date()
        report = nil
        stopping = false
        let control = CleanControl()
        cleanControl = control
        let cleaner = CacheCleaner(environment: environment, isInUse: { owner in
            let running = await MainActor.run {
                Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
            }
            let names = owner.processNames.isEmpty ? [] : RunningProbe.runningToolNames(ProcessSampler().sample().rows)
            return RunningProbe.isRunning(owner, runningBundleIDs: running, processNames: names)
        })
        let scanner = CacheScanner(environment: environment)
        work = Task {
            // Read to the end even after Stop: the cleaner finishes with a report of what it did.
            var finalReport: CleanReport?
            for await event in cleaner.clean(chosen, mode: mode, control: control) {
                switch event {
                case .started(let id): cleaningItem = id
                case .finished: break
                case .done(let done): finalReport = done
                }
            }
            cleaningItem = nil
            // Measure again, so the list shows what's left.
            for await event in scanner.measure(chosen) {
                if case .sized(let id, let size) = event { pendingSizes[id] = size }
            }
            flushSizes()
            let cleaned = Set(finalReport?.results.filter { $0.status == .cleaned }.map(\.id) ?? [])
            selection.subtract(cleaned)
            report = finalReport
            cleanControl = nil
            stopping = false
            activitySince = nil
            phase = .done
        }
    }

    func dismissReport() {
        report = nil
        if phase == .done { phase = .results }
    }

    func reveal(_ item: CacheItem) {
        NSWorkspace.shared.activateFileViewerSelecting(item.targets.map(\.url))
    }
}
