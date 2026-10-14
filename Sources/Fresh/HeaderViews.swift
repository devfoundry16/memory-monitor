import MemoryCore
import SwiftUI

// MARK: - Header (black frame) with Memory / CPU / GPU tabs

struct HeaderView: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(spacing: Theme.Space.md) {
                MainTabs(selection: $store.tab)
                Spacer()
                Button { store.showingSettings = true } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Theme.Palette.onFrameMute)
                        .frame(width: 30, height: 30)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .help("Settings: theme and menu bar")
            }

            switch store.tab {
            case .memory: MemoryHeader()
            case .cpu: CPUHeader()
            case .gpu: GPUHeader()
            case .clean: CleanerHeader()
            }

            if let error = store.errorMessage {
                Text(error).font(Theme.Typeface.body).foregroundStyle(Theme.Palette.error)
            }
        }
        .padding(.horizontal, Theme.Space.xxl)
        .padding(.top, Theme.Space.md) // the safe area already clears the traffic lights
        .padding(.bottom, Theme.Space.xl)
        .background(Theme.Palette.frame.ignoresSafeArea())
    }
}

/// Header tabs on black: the active tab inverts to white, NVIDIA's pill-tab on a dark surface.
private struct MainTabs: View {
    @Binding var selection: MainTab

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(MainTab.allCases, id: \.self) { tab in
                let active = tab == selection
                Button { selection = tab } label: {
                    HStack(spacing: 6) {
                        Image(systemName: tab.symbol).font(.system(size: 12, weight: .semibold))
                        Text(Theme.label(tab.title)).font(Theme.Typeface.captionMd)
                    }
                    .foregroundStyle(active ? Theme.Palette.frame : Theme.Palette.onFrameMute)
                    .padding(.horizontal, 14)
                    .frame(height: 30)
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
            }
        }
    }
}

extension MainTab {
    var title: String { resource?.title ?? "Clean" }
    var symbol: String { resource?.symbol ?? "sparkles" }
}

extension Resource {
    var title: String {
        switch self {
        case .memory: "Memory"
        case .cpu: "CPU"
        case .gpu: "GPU"
        }
    }

    /// Also used for the menu bar icons.
    var symbol: String {
        switch self {
        case .memory: "memorychip"
        case .cpu: "cpu"
        case .gpu: "cube.transparent"
        }
    }
}

// MARK: - Shared pieces

/// Eyebrow, big green figure with a white companion, and a muted subtitle.
struct HeroFigure: View {
    let eyebrow: String
    let value: String
    var companion: String?
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            HStack(spacing: Theme.Space.sm) {
                CornerSquare()
                Eyebrow(eyebrow, color: Theme.Palette.onFrameMute)
            }
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.lg) {
                Text(value).foregroundStyle(Theme.Palette.primary)
                if let companion {
                    Text(companion).foregroundStyle(Theme.Palette.onFrame)
                }
            }
            .font(Theme.Typeface.displayLg)
            .monospacedDigit()
            Text(subtitle)
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.onFrameMute)
                .lineLimit(1)
        }
    }
}

/// The hero row's height is fixed so switching tabs doesn't move the process list.
let heroHeight: CGFloat = 92

struct CardGrid<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: Theme.Space.md), count: 4),
                  spacing: Theme.Space.md) {
            content
        }
    }
}

struct StatCard: View {
    let title: String
    let value: String
    var percent: String?
    /// One-line plain explanation of what the number means.
    let summary: String
    var detail: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xs) {
            Eyebrow(title, color: Theme.Palette.onFrameMute)
            HStack(alignment: .firstTextBaseline, spacing: Theme.Space.sm) {
                Text(value)
                    .font(Theme.Typeface.cardValue)
                    .foregroundStyle(Theme.Palette.onFrame)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let percent {
                    Text(percent)
                        .font(Theme.Typeface.cardPercent)
                        .lineLimit(1)
                        .foregroundStyle(Theme.Palette.primary)
                }
            }
            .monospacedDigit()
            Text(summary)
                .font(Theme.Typeface.cardSummary)
                .foregroundStyle(Theme.Palette.onFrameMute)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
            // Always takes a line, so every card in a row has the same height.
            Text(detail ?? " ")
                .font(Theme.Typeface.captionSm)
                .foregroundStyle(Theme.Palette.onFrame)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Space.lg)
        .background(Theme.Palette.frameCard, in: .rect(cornerRadius: Theme.cardRadius))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius).strokeBorder(Theme.Palette.frameHairline, lineWidth: 1))
        .overlay(alignment: .topLeading) { CornerSquare(size: 8) }
    }
}

/// CPU and GPU percentages for one process or app, e.g. "12.3%".
func formatUsage(_ percent: Double?) -> String {
    guard let percent else { return "—" }
    return String(format: "%.1f%%", percent)
}

// MARK: - Memory

private struct MemoryHeader: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                HeroFigure(
                    eyebrow: "Memory Used",
                    value: store.memory.map { ByteFormatter.format($0.used) } ?? "—",
                    companion: store.memory.map { PercentFormatter.format($0.fractionOfTotal($0.used)) },
                    subtitle: store.memory.map {
                        "of \(ByteFormatter.format($0.total)) physical memory · Used = App Memory + Wired + Compressed"
                            + " + \(ByteFormatter.format($0.hardwareReserved)) reserved by hardware"
                            + " + \(ByteFormatter.format($0.purgeable)) purgeable"
                    } ?? "")
                    .help("""
                        Reserved by hardware: Set aside at startup for the chip's built-in processors. macOS can't use it.
                        Purgeable: Caches apps can drop instantly when memory is needed.
                        """)
                Spacer()
                if let memory = store.memory {
                    PressureBadge(pressure: memory.pressure)
                        .help("How hard macOS is working to find free memory. Green is fine; orange or red means the Mac is short on RAM and may slow down.")
                }
            }
            .frame(height: heroHeight)

            HistoryGraph(
                resource: .memory,
                series: [
                    GraphSeries(name: "App Memory", color: Theme.pressureColor(store.memory?.pressure ?? .normal)),
                    GraphSeries(name: "Wired", color: Theme.Palette.onFrameMute),
                    GraphSeries(name: "Compressed", color: Theme.Palette.ash),
                    GraphSeries(name: "Purgeable", color: Theme.Palette.ash.opacity(0.45)),
                    GraphSeries(name: "Reserved by hardware", color: Theme.Palette.ash.opacity(0.25)),
                ],
                describe: describe)

            CardGrid {
                StatCard(
                    title: "App Memory", value: bytes(\.appMemory), percent: percentOfRAM(\.appMemory),
                    summary: "Used by apps and background processes.")
                StatCard(
                    title: "Wired", value: bytes(\.wired), percent: percentOfRAM(\.wired),
                    summary: "Reserved by macOS itself. Can't be compressed or moved to disk.")
                StatCard(
                    title: "Compressed", value: bytes(\.compressed), percent: percentOfRAM(\.compressed),
                    summary: "Idle memory squeezed to make room, instead of writing it to disk.")
                StatCard(
                    title: "Cached Files", value: bytes(\.cachedFiles), percent: percentOfRAM(\.cachedFiles),
                    summary: "Recently used files kept for speed. Freed when apps need the room.")
                StatCard(
                    title: "Swap Used", value: bytes(\.swapUsed),
                    percent: store.memory.flatMap { memory in
                        memory.swapTotal == 0 ? nil
                            : PercentFormatter.format(Double(memory.swapUsed) / Double(memory.swapTotal))
                    },
                    summary: "Memory moved to disk because RAM ran short. A lot of swap slows the Mac.",
                    detail: store.memory.map { "of \(ByteFormatter.format($0.swapTotal)) swap file" })
                StatCard(
                    title: "Processes", value: store.snapshot.processCount.formatted(),
                    summary: "Everything running, including background services.",
                    detail: "\(store.snapshot.ownCount.formatted()) yours · \(store.snapshot.othersCount.formatted()) system")
                StatCard(
                    title: "Apps", value: store.appCount.formatted(),
                    summary: "Apps you opened that have a Dock icon.")
                StatCard(
                    title: "Threads", value: threadsValue,
                    summary: "Tasks running in parallel inside processes.",
                    detail: store.snapshot.restrictedCount > 0
                        ? "\(store.snapshot.restrictedCount) processes need admin to read" : nil)
            }
        }
    }

    private var threadsValue: String {
        let total = store.snapshot.threadTotal.formatted()
        return store.snapshot.restrictedCount > 0 ? "≥ \(total)" : total
    }

    /// "12.81 GB used (80%) · App 5.20 GB · Wired 2.51 GB · Compressed 4.10 GB"
    private func describe(_ point: MetricHistory.Point) -> String {
        guard let total = store.memory?.total else { return "" }
        func size(_ fraction: Double) -> String { ByteFormatter.format(UInt64(fraction * Double(total))) }
        let parts = zip(["App", "Wired", "Compressed"], point.values).map { "\($0) \(size($1))" }
        return (["\(size(point.total)) used (\(PercentFormatter.format(point.total)))"] + parts).joined(separator: " · ")
    }

    private func bytes(_ keyPath: KeyPath<SystemMemory, UInt64>) -> String {
        store.memory.map { ByteFormatter.format($0[keyPath: keyPath]) } ?? "—"
    }

    private func percentOfRAM(_ keyPath: KeyPath<SystemMemory, UInt64>) -> String? {
        store.memory.map { "\(PercentFormatter.format($0.fractionOfTotal($0[keyPath: keyPath]))) of RAM" }
    }
}

// MARK: - CPU

private struct CPUHeader: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let topology = store.topology
        let cpu = store.cpu
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .center, spacing: Theme.Space.xl) {
                HeroFigure(
                    eyebrow: "CPU Usage",
                    value: cpu.map { PercentFormatter.format($0.total) } ?? "—",
                    subtitle: coresSubtitle(topology))
                Spacer()
                if let cpu {
                    CoreBars(topology: topology, perCore: cpu.perCore)
                }
            }
            .frame(height: heroHeight)

            HistoryGraph(
                resource: .cpu,
                series: [
                    GraphSeries(name: "User", color: Theme.Palette.primary),
                    GraphSeries(name: "System", color: Theme.Palette.onFrameMute),
                ],
                describe: { point in
                    let parts = zip(["User", "System"], point.values).map { "\($0) \(PercentFormatter.format($1))" }
                    return (["\(PercentFormatter.format(point.total)) busy"] + parts).joined(separator: " · ")
                })

            CardGrid {
                StatCard(
                    title: "User", value: percent(cpu?.user),
                    summary: "Apps and programs you run.")
                StatCard(
                    title: "System", value: percent(cpu?.system),
                    summary: "Work done by macOS itself for those apps.")
                StatCard(
                    title: "Idle", value: percent(cpu?.idle),
                    summary: "Spare capacity, free for anything that needs it.")
                StatCard(
                    title: "Load Average", value: store.loadAverage.first.map { String(format: "%.2f", $0) } ?? "—",
                    summary: "Tasks running or waiting for a core. Above \(topology.cores.count) means work is queuing.",
                    detail: store.loadAverage.count == 3
                        ? String(format: "5 min %.2f · 15 min %.2f", store.loadAverage[1], store.loadAverage[2]) : nil)
                StatCard(
                    title: "Performance Cores", value: percent(average(of: .performance)),
                    summary: "Fast cores for demanding work.",
                    detail: "\(topology.performanceCount) cores")
                StatCard(
                    title: "Efficiency Cores", value: percent(average(of: .efficiency)),
                    summary: "Low-power cores for background work.",
                    detail: "\(topology.efficiencyCount) cores")
                StatCard(
                    title: "Busiest", value: formatUsage(topCPU?.cpuPercent),
                    summary: "Busiest app (with its helpers) or process. 100% = one full core.",
                    detail: topCPU?.name)
                StatCard(
                    title: "Uptime", value: uptime,
                    summary: "Time since the Mac last started.")
            }
        }
    }

    private var topCPU: TopEntry? { store.topEntry { $0.cpuPercent } }

    private func percent(_ fraction: Double?) -> String {
        fraction.map(PercentFormatter.format) ?? "—"
    }

    private func average(of kind: CoreKind) -> Double? {
        guard let cpu = store.cpu else { return nil }
        let values = zip(store.topology.cores, cpu.perCore).filter { $0.0 == kind }.map(\.1)
        return values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    private func coresSubtitle(_ topology: CPUTopology) -> String {
        if topology.performanceCount + topology.efficiencyCount == topology.cores.count {
            return "\(topology.brand) · \(topology.performanceCount) performance + \(topology.efficiencyCount) efficiency cores"
        }
        return "\(topology.brand) · \(topology.cores.count) cores"
    }

    private var uptime: String {
        guard let boot = store.bootTime else { return "—" }
        let minutes = Int(Date().timeIntervalSince(boot) / 60)
        let (days, hours, mins) = (minutes / 1440, minutes / 60 % 24, minutes % 60)
        return days > 0 ? "\(days)d \(hours)h" : "\(hours)h \(mins)m"
    }
}

/// One bar per core, performance cores first, labelled P and E.
private struct CoreBars: View {
    let topology: CPUTopology
    let perCore: [Double]

    var body: some View {
        let cores = Array(zip(topology.cores, perCore).enumerated())
        let ordered = cores.filter { $0.element.0 == .performance } + cores.filter { $0.element.0 != .performance }
        HStack(alignment: .bottom, spacing: 4) {
            ForEach(ordered, id: \.offset) { _, core in
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        Rectangle().fill(Theme.Palette.frameCard)
                        Rectangle()
                            .fill(core.0 == .performance ? Theme.Palette.primary : Theme.Palette.onFrameMute)
                            .frame(height: 56 * CGFloat(min(max(core.1, 0), 1)))
                    }
                    .frame(width: 14, height: 56)
                    .clipShape(.rect(cornerRadius: Theme.radius))
                    Text(core.0 == .performance ? "P" : core.0 == .efficiency ? "E" : "·")
                        .font(Theme.Typeface.captionMd)
                        .foregroundStyle(Theme.Palette.onFrameMute)
                }
                .help("\(core.0 == .performance ? "Performance" : "Efficiency") core: \(PercentFormatter.format(core.1))")
            }
        }
    }
}

// MARK: - GPU

private struct GPUHeader: View {
    @Environment(MonitorStore.self) private var store

    var body: some View {
        let gpu = store.gpu
        VStack(alignment: .leading, spacing: Theme.Space.xl) {
            HStack(alignment: .center) {
                HeroFigure(
                    eyebrow: "GPU Usage",
                    value: gpu.map { PercentFormatter.format($0.device) } ?? "—",
                    subtitle: subtitle)
                Spacer()
            }
            .frame(height: heroHeight)

            HistoryGraph(
                resource: .gpu,
                series: [GraphSeries(name: "GPU", color: Theme.Palette.primary)],
                describe: { "\(PercentFormatter.format($0.total)) busy" })

            CardGrid {
                StatCard(
                    title: "Renderer", value: gpu.map { PercentFormatter.format($0.renderer) } ?? "—",
                    summary: "Drawing pixels: windows, video, games.")
                StatCard(
                    title: "Tiler", value: gpu.map { PercentFormatter.format($0.tiler) } ?? "—",
                    summary: "Preparing shapes before they are drawn.")
                StatCard(
                    title: "GPU Memory In Use", value: gpu.map { ByteFormatter.format($0.inUseMemory) } ?? "—",
                    percent: percentOfRAM(gpu?.inUseMemory),
                    summary: "Shared with the CPU: Apple Silicon has one pool of RAM.")
                StatCard(
                    title: "GPU Memory Reserved", value: gpu.map { ByteFormatter.format($0.allocatedMemory) } ?? "—",
                    percent: percentOfRAM(gpu?.allocatedMemory),
                    summary: "Set aside for the GPU, used or not.")
                StatCard(
                    title: "Busiest", value: formatUsage(topGPU?.gpuPercent),
                    summary: "App (with its helpers) or process using the most GPU time.",
                    detail: topGPU?.name)
                StatCard(
                    title: "Apps Using GPU", value: appsUsingGPU.formatted(),
                    summary: "Apps and processes that used the GPU in the last 2 seconds.")
                StatCard(
                    title: "Screen Drawing", value: formatUsage(windowServer?.gpuPercent),
                    summary: "WindowServer, which draws the desktop and every window.")
                StatCard(
                    title: "GPU Cores", value: store.gpuInfo?.coreCount.map(String.init) ?? "—",
                    summary: "Graphics cores in this chip.")
            }
        }
    }

    private var subtitle: String {
        guard let info = store.gpuInfo else { return "No GPU statistics available" }
        let cores = info.coreCount.map { " · \($0) GPU cores" } ?? ""
        return "\(info.name)\(cores) · Per-app figures are each app's share of GPU time"
    }

    private var topGPU: TopEntry? { store.topEntry { $0.gpuPercent } }

    private var appsUsingGPU: Int {
        store.topLevelEntries.filter { ($0.gpuPercent ?? 0) >= 0.05 }.count
    }

    private var windowServer: ProcessRow? {
        store.snapshot.rows.first { $0.name == "WindowServer" }
    }

    private func percentOfRAM(_ bytes: UInt64?) -> String? {
        guard let bytes, let memory = store.memory else { return nil }
        return "\(PercentFormatter.format(memory.fractionOfTotal(bytes))) of RAM"
    }
}
