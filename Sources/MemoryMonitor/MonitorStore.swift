import AppKit
import MemoryCore
import Observation

/// A process row enriched with app info (display name, icon) and protection level.
struct DisplayRow: Identifiable {
    let process: ProcessRow
    let displayName: String
    let icon: NSImage?
    let isApp: Bool
    let protection: ProcessProtection
    let parent: ParentInfo?

    var id: pid_t { process.pid }
}

/// One line in the process list.
struct ListItem: Identifiable {
    enum Kind {
        /// A single process (All Processes tab).
        case process
        /// An app with totals across all of its processes (Apps tab).
        case appGroup(AppGroup, expanded: Bool)
        /// One process inside an expanded app group.
        case member(isMain: Bool)
    }

    let id: String
    let row: DisplayRow
    let kind: Kind

    var group: AppGroup? {
        if case .appGroup(let group, _) = kind { return group }
        return nil
    }
    var memory: UInt64? { group?.memory ?? row.process.memory }
    var threads: Int? { group?.threads ?? row.process.threads }
    var cpuPercent: Double? { group.map(\.cpuPercent) ?? row.process.cpuPercent }
    var gpuPercent: Double? { group.map(\.gpuPercent) ?? row.process.gpuPercent }
}

/// The resource the header tabs show; the list sorts by it when the tab changes.
enum Resource: Hashable, CaseIterable {
    case memory, cpu, gpu
}

/// A process or an app (with its helpers) awaiting force-stop confirmation.
struct StopRequest: Identifiable {
    let row: DisplayRow
    let group: AppGroup?
    var id: pid_t { row.id }
}

/// An entry in the menu bar's top list: an app with its helpers, or a standalone process.
struct TopEntry: Identifiable {
    let id: pid_t
    let name: String
    let icon: NSImage?
    let memory: UInt64?
    let cpuPercent: Double?
    let gpuPercent: Double?
}

/// What a process belongs to: the app responsible for it (e.g. "Google Chrome" for a
/// Chrome Helper, "Mail" for Mail's XPC services), otherwise its direct parent process.
struct ParentInfo {
    let pid: pid_t
    let name: String
    let icon: NSImage?
    let isApp: Bool
    /// Full ancestry for the tooltip, e.g. "login (812) ← iTerm2 (701)".
    let chain: String
}

enum SortKey: Hashable {
    case name, pid, user, parent, memory, cpu, gpu, threads
}

enum ProcessFilter: Hashable {
    case all, apps
}

struct StopOutcome: Identifiable {
    let id = UUID()
    let name: String
    let result: KillResult
}

@MainActor
@Observable
final class MonitorStore {
    private(set) var memory: SystemMemory?
    private(set) var cpu: CPUUsage?
    private(set) var loadAverage: [Double] = []
    private(set) var gpu: GPUStats?
    let topology = CPUSampler.topology()
    let gpuInfo = GPUSampler.info()
    let bootTime = CPUSampler.bootTime()

    /// Header tab. Switching it re-sorts the list by that resource.
    var resource: Resource = .memory {
        didSet {
            guard resource != oldValue else { return }
            sortAscending = false
            sortKey = switch resource {
            case .memory: .memory
            case .cpu: .cpu
            case .gpu: .gpu
            }
        }
    }

    var menuBarSettings = MenuBarSettings.load() {
        didSet { menuBarSettings.save() }
    }
    var showingSettings = false
    private(set) var snapshot = ProcessSnapshot(rows: [], threadTotal: 0, restrictedCount: 0, ownCount: 0)
    private(set) var rows: [DisplayRow] = []
    private(set) var appCount = 0
    private(set) var errorMessage: String?

    var sortKey: SortKey = .memory { didSet { updateVisibleRows() } }
    var sortAscending = false { didSet { updateVisibleRows() } }
    var filter: ProcessFilter = .apps { didSet { updateVisibleRows() } }
    var query = "" { didSet { updateVisibleRows() } }
    /// Apps expanded in the Apps tab.
    var expanded: Set<pid_t> = [] { didSet { updateVisibleRows() } }
    /// The selected list item's `id`.
    var selection: String?

    /// Apps keyed by PID, each with every process that belongs to it.
    private(set) var groups: [pid_t: AppGroup] = [:]
    /// Filtered and sorted items, cached so views don't re-sort ~700 rows on every render.
    private(set) var visibleItems: [ListItem] = []
    private(set) var topEntries: [TopEntry] = []

    var pendingStop: StopRequest?
    private(set) var stopping: Set<pid_t> = []
    var lastOutcome: StopOutcome?

    private let systemSampler: SystemMemorySampler?
    private let processSampler = ProcessSampler()
    private var loop: Task<Void, Never>?
    private var previousTicks: CPUTicks?
    private var usageBaseline: UsageBaseline?

    init() {
        do {
            systemSampler = try SystemMemorySampler()
        } catch {
            systemSampler = nil
            errorMessage = "Could not read system memory: \(error)"
        }
    }

    /// Samples memory, CPU and GPU every second and the process list every two seconds.
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            var tick = 0
            while !Task.isCancelled {
                await self?.refresh(includeProcesses: tick.isMultiple(of: 2))
                tick += 1
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    func refresh(includeProcesses: Bool) async {
        let systemSampler = systemSampler
        let system = await Task.detached {
            (memory: systemSampler.map { sampler in Result { try sampler.sample() } },
             ticks: try? CPUSampler.ticks(),
             load: CPUSampler.loadAverage(),
             gpu: GPUSampler.stats())
        }.value

        // Observation notifies on every assignment, so skip identical samples.
        switch system.memory {
        case .success(let value) where value != memory: memory = value
        case .failure(let error): errorMessage = "Could not read system memory: \(error)"
        default: break
        }
        if let ticks = system.ticks {
            if let previousTicks { cpu = CPUSampler.usage(from: previousTicks, to: ticks) }
            previousTicks = ticks
        }
        if system.load != loadAverage { loadAverage = system.load }
        if system.gpu != gpu { gpu = system.gpu }

        guard includeProcesses else { return }
        let sampler = processSampler
        let baseline = usageBaseline
        let (sampled, nextBaseline) = await Task.detached {
            var snapshot = sampler.sample()
            let gpuTimes = GPUSampler.processGPUTimes()
            let now = UInt64(clock_gettime_nsec_np(CLOCK_UPTIME_RAW))
            let next = UsageRates.apply(to: &snapshot.rows, gpuTimes: gpuTimes, now: now, previous: baseline)
            return (snapshot, next)
        }.value
        snapshot = sampled
        usageBaseline = nextBaseline
        rebuildRows()
    }

    private func rebuildRows() {
        var apps: [pid_t: NSRunningApplication] = [:]
        for app in NSWorkspace.shared.runningApplications where app.activationPolicy == .regular {
            apps[app.processIdentifier] = app
        }
        appCount = apps.count
        let appPIDs = Set(apps.keys)
        let byPID = Dictionary(snapshot.rows.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        groups = AppGrouping.groups(rows: snapshot.rows, appPIDs: appPIDs)

        var owners: [pid_t: pid_t] = [:]
        rows = snapshot.rows.map { process in
            let app = apps[process.pid]
            let owner = AppGrouping.owner(of: process, byPID: byPID, appPIDs: appPIDs)
            owners[process.pid] = owner
            return DisplayRow(
                process: process,
                displayName: app?.localizedName ?? process.name,
                icon: app?.icon,
                isApp: app != nil,
                protection: ProcessKiller.protection(pid: process.pid, name: process.name),
                parent: Self.parent(of: process, owner: owner, byPID: byPID, apps: apps))
        }
        rowsByPID = Dictionary(rows.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        // Menu bar top list: apps count all their helpers; standalone processes count alone.
        let appEntries = groups.values.compactMap { group -> TopEntry? in
            guard let row = rowsByPID[group.appPID] else { return nil }
            return TopEntry(
                id: row.id, name: row.displayName, icon: row.icon, memory: group.memory,
                cpuPercent: group.cpuPercent, gpuPercent: group.gpuPercent)
        }
        let standalone = rows.filter { !$0.isApp && owners[$0.id] == nil }.map {
            TopEntry(
                id: $0.id, name: $0.displayName, icon: $0.icon, memory: $0.process.memory,
                cpuPercent: $0.process.cpuPercent, gpuPercent: $0.process.gpuPercent)
        }
        topLevelEntries = appEntries + standalone
        topEntries = Array((appEntries + standalone).sorted { ($0.memory ?? 0) > ($1.memory ?? 0) }.prefix(5))
        updateVisibleRows()
    }

    private var rowsByPID: [pid_t: DisplayRow] = [:]
    /// Apps (with helpers) and standalone processes: nothing counted twice.
    private(set) var topLevelEntries: [TopEntry] = []

    /// The biggest top-level entry for a resource, e.g. the app using the most CPU.
    func topEntry(by value: (TopEntry) -> Double?) -> TopEntry? {
        topLevelEntries.max { (value($0) ?? 0) < (value($1) ?? 0) }
    }

    static func parent(
        of process: ProcessRow, owner: pid_t?, byPID: [pid_t: ProcessRow], apps: [pid_t: NSRunningApplication]
    ) -> ParentInfo? {
        guard process.pid > 1, process.ppid > 0 else { return nil }
        func label(_ pid: pid_t) -> String {
            apps[pid]?.localizedName ?? byPID[pid]?.name ?? (pid == 1 ? "launchd" : "pid \(pid)")
        }

        // Ancestry for the tooltip, up to the nearest app. The depth limit guards against
        // a PID cycle caused by reuse between samples.
        var ancestors: [pid_t] = []
        var current = process.ppid
        while current > 1, ancestors.count < 16, !ancestors.contains(current) {
            ancestors.append(current)
            if apps[current] != nil { break }
            guard let next = byPID[current]?.ppid else { break }
            current = next
        }
        if ancestors.isEmpty { ancestors = [process.ppid] } // parent is launchd
        var chain = ancestors.map { "\(label($0)) (\($0))" }.joined(separator: " ← ")
        if let owner, !ancestors.contains(owner) {
            chain += " · belongs to \(label(owner)) (\(owner))"
        }

        let pid = owner ?? process.ppid
        return ParentInfo(pid: pid, name: label(pid), icon: apps[pid]?.icon, isApp: owner != nil, chain: chain)
    }

    private func matches(_ row: DisplayRow, _ needle: String) -> Bool {
        needle.isEmpty
            || row.displayName.localizedCaseInsensitiveContains(needle)
            || row.process.name.localizedCaseInsensitiveContains(needle)
            || (row.parent?.name.localizedCaseInsensitiveContains(needle) ?? false)
            || String(row.process.pid).hasPrefix(needle)
    }

    private func updateVisibleRows() {
        let needle = query.trimmingCharacters(in: .whitespaces)
        switch filter {
        case .all:
            visibleItems = rows
                .filter { matches($0, needle) }
                .map { Metrics(row: $0, memory: $0.process.memory, threads: $0.process.threads,
                               cpu: $0.process.cpuPercent, gpu: $0.process.gpuPercent) }
                .sorted(by: isOrderedBefore)
                .map { ListItem(id: "p\($0.row.id)", row: $0.row, kind: .process) }

        case .apps:
            var items: [ListItem] = []
            let sortedGroups = groups.values
                .compactMap { group -> Metrics? in
                    rowsByPID[group.appPID].map {
                        Metrics(row: $0, memory: group.memory, threads: group.threads,
                                cpu: group.cpuPercent, gpu: group.gpuPercent)
                    }
                }
                .sorted(by: isOrderedBefore)
            for app in sortedGroups.map(\.row) {
                guard let group = groups[app.id] else { continue }
                let members = group.members.compactMap { rowsByPID[$0.pid] }
                let matching = members.filter { matches($0, needle) }
                guard !matching.isEmpty else { continue }
                // A search that only hits helpers opens the app so the hits are visible.
                let isOpen = expanded.contains(app.id) || (!needle.isEmpty && !matches(app, needle))
                items.append(ListItem(id: "a\(app.id)", row: app, kind: .appGroup(group, expanded: isOpen)))
                if isOpen {
                    for member in needle.isEmpty || matches(app, needle) ? members : matching {
                        items.append(ListItem(id: "m\(member.id)", row: member, kind: .member(isMain: member.id == app.id)))
                    }
                }
            }
            visibleItems = items
        }
        if let selection, !visibleItems.contains(where: { $0.id == selection }) {
            self.selection = nil
        }
    }

    /// A row plus the numbers to sort by: its own, or its app group's totals.
    private struct Metrics {
        let row: DisplayRow
        let memory: UInt64?
        let threads: Int?
        let cpu: Double?
        let gpu: Double?
    }

    /// Sort order shared by single processes and app groups.
    private func isOrderedBefore(_ a: Metrics, _ b: Metrics) -> Bool {
        let ordered: Bool
        switch sortKey {
        case .name:
            let comparison = a.row.displayName.localizedCaseInsensitiveCompare(b.row.displayName)
            if comparison == .orderedSame { return a.row.id < b.row.id }
            ordered = comparison == .orderedAscending
        case .pid: ordered = a.row.id < b.row.id
        case .user: ordered = (a.row.process.user, a.row.id) < (b.row.process.user, b.row.id)
        case .parent:
            let comparison = (a.row.parent?.name ?? "").localizedCaseInsensitiveCompare(b.row.parent?.name ?? "")
            if comparison == .orderedSame { return a.row.id < b.row.id }
            ordered = comparison == .orderedAscending
        case .memory:
            let (x, y) = (a.memory ?? 0, b.memory ?? 0)
            if x == y { return a.row.id < b.row.id }
            ordered = x < y
        case .threads:
            let (x, y) = (a.threads ?? -1, b.threads ?? -1)
            if x == y { return a.row.id < b.row.id }
            ordered = x < y
        case .cpu, .gpu:
            let (x, y) = sortKey == .cpu ? (a.cpu ?? -1, b.cpu ?? -1) : (a.gpu ?? -1, b.gpu ?? -1)
            if x == y { return (a.memory ?? 0) < (b.memory ?? 0) }
            ordered = x < y
        }
        return sortAscending ? ordered : !ordered
    }

    func toggleExpanded(_ appPID: pid_t) {
        if expanded.contains(appPID) {
            expanded.remove(appPID)
        } else {
            expanded.insert(appPID)
        }
    }

    func toggleSort(_ key: SortKey) {
        if sortKey == key {
            sortAscending.toggle()
        } else {
            sortKey = key
            // Numbers read best largest-first, text A→Z.
            sortAscending = key == .name || key == .user || key == .parent
        }
    }

    /// Asks for confirmation before stopping a process, or an app and all of its processes.
    func requestStop(_ item: ListItem) {
        guard item.row.protection != .protected else { return }
        pendingStop = StopRequest(row: item.row, group: item.group)
    }

    func confirmStop() {
        guard let request = pendingStop else { return }
        pendingStop = nil
        let row = request.row
        stopping.insert(row.id)
        Task {
            let result = await ProcessKiller.forceStop(pid: row.process.pid, expectedName: row.process.name)
            var name = row.displayName
            if result == .stopped, let group = request.group {
                // Child helpers exit with the app, but XPC services can outlive it.
                // Stop what is left; only your own, so there is no password prompt per helper.
                let leftovers = group.members.dropFirst().filter { $0.uid == getuid() && ProcessKiller.isAlive($0.pid) }
                await withTaskGroup(of: Void.self) { tasks in
                    for helper in leftovers {
                        tasks.addTask {
                            _ = await ProcessKiller.forceStop(
                                pid: helper.pid, expectedName: helper.name, gracePeriod: .milliseconds(500))
                        }
                    }
                }
                if group.processCount > 1 {
                    name += " and its \(group.processCount - 1) other processes"
                }
            }
            stopping.remove(row.id)
            lastOutcome = StopOutcome(name: name, result: result)
            await refresh(includeProcesses: true)
        }
    }
}
