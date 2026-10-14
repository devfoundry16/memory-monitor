import MemoryCore
import SwiftUI

/// Themed replacement for a system alert: system alerts can't take the NVIDIA styling.
struct ForceStopConfirm: View {
    @Environment(MonitorStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let request: StopRequest

    private var row: DisplayRow { request.row }
    private var group: AppGroup? { request.group.flatMap { $0.processCount > 1 ? $0 : nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                Rectangle().fill(Theme.Palette.error).frame(width: 12, height: 12)
                Eyebrow("Force Stop", color: Theme.Palette.error)
            }
            Text("Stop \(row.displayName)?")
                .font(Theme.Typeface.headingMd)
                .foregroundStyle(Theme.Palette.ink)

            Grid(alignment: .leading, horizontalSpacing: Theme.Space.lg, verticalSpacing: Theme.Space.xs) {
                detail("PID", String(row.process.pid))
                detail("User", row.process.user)
                if let group {
                    detail("Processes", String(group.processCount))
                    detail("Memory", ByteFormatter.format(group.memory) + " in total")
                    detail("Threads", String(group.threads) + " in total")
                } else {
                    detail("Memory", row.process.memory.map(ByteFormatter.format) ?? "—")
                    detail("Threads", row.process.threads.map { String($0) } ?? "—")
                }
            }

            Text(explanation)
                .font(Theme.Typeface.body)
                .foregroundStyle(row.protection == .critical ? Theme.Palette.warning : Theme.Palette.body)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.Space.md) {
                Spacer()
                Button("Cancel") {
                    store.pendingStop = nil
                    dismiss()
                }
                .buttonStyle(OutlineButtonStyle())
                .keyboardShortcut(.cancelAction)
                Button("Force Stop") {
                    store.confirmStop()
                    dismiss()
                }
                .buttonStyle(DestructiveButtonStyle())
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 420)
        .background(Theme.Palette.canvas)
        .environment(\.colorScheme, Theme.bodyScheme)
    }

    private var explanation: String {
        var text = "Unsaved work in this process will be lost. It gets 2 seconds to quit, then it is killed along with all of its threads."
        if let group {
            text = "Unsaved work in \(row.displayName) will be lost. The app gets 2 seconds to quit, then it is killed, and any of its \(group.processCount - 1) helper processes still running are stopped too."
        }
        if row.process.uid != getuid() {
            text += " It belongs to \(row.process.user), so macOS will ask for an administrator password."
        }
        if row.protection == .critical {
            text = "Warning: stopping \(row.process.name) will log you out or freeze the screen. " + text
        }
        return text
    }

    private func detail(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(Theme.label(label)).font(Theme.Typeface.captionMd).foregroundStyle(Theme.Palette.mute)
            Text(value).font(Theme.Typeface.bodyStrong).monospacedDigit().foregroundStyle(Theme.Palette.ink)
        }
    }
}
