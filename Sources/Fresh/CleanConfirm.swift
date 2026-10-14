import MemoryCore
import SwiftUI

/// Confirms a clean and picks how: Move to Trash (undoable) or Delete Permanently.
struct CleanConfirm: View {
    @Environment(CleanerStore.self) private var cleaner
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let items = cleaner.selectedItems.sorted { cleaner.bytes($0) > cleaner.bytes($1) }
        let cautions = items.filter { $0.advisory?.isCaution ?? false }
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                Rectangle().fill(Theme.Palette.warning).frame(width: 12, height: 12)
                Eyebrow("Clean Caches", color: Theme.Palette.warning)
            }
            Text("Remove \(ByteFormatter.format(cleaner.selectedBytes)) of caches?")
                .font(Theme.Typeface.headingMd)
                .foregroundStyle(Theme.Palette.ink)

            Grid(alignment: .leading, horizontalSpacing: Theme.Space.lg, verticalSpacing: Theme.Space.xs) {
                ForEach(items.prefix(5)) { item in
                    GridRow {
                        Text(item.name + (item.detail.map { " · \($0)" } ?? ""))
                            .font(Theme.Typeface.body).foregroundStyle(Theme.Palette.body).lineLimit(1)
                        Text(ByteFormatter.format(cleaner.bytes(item)))
                            .font(Theme.Typeface.bodyStrong).monospacedDigit().foregroundStyle(Theme.Palette.ink)
                            .gridColumnAlignment(.trailing)
                    }
                }
                if items.count > 5 {
                    GridRow {
                        Text("and \(items.count - 5) more").font(Theme.Typeface.body).foregroundStyle(Theme.Palette.mute)
                        Text(ByteFormatter.format(items.dropFirst(5).reduce(0) { $0 + cleaner.bytes($1) }))
                            .font(Theme.Typeface.body).monospacedDigit().foregroundStyle(Theme.Palette.mute)
                    }
                }
            }

            Text("Only the contents of these cache folders are removed. Apps rebuild them as needed, so some may load a little slower the first time.")
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.body)
                .fixedSize(horizontal: false, vertical: true)
            if !cautions.isEmpty {
                Text("Includes items marked with a caution: \(cautions.map(\.name).joined(separator: ", ")). Check their notes first.")
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: Theme.Space.md) {
                Button("Cancel") {
                    cleaner.showingConfirm = false
                    dismiss()
                }
                .buttonStyle(OutlineButtonStyle())
                .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Move to Trash") { cleaner.confirmClean(.moveToTrash) }
                    .buttonStyle(PrimaryButtonStyle())
                    .help("Undoable until you empty the Trash; frees no space until then")
                Button("Delete Permanently") { cleaner.confirmClean(.deletePermanently) }
                    .buttonStyle(DestructiveButtonStyle())
                    .help("Frees the space now; can't be undone")
            }
        }
        .padding(Theme.Space.xl)
        .frame(width: 520)
        .background(Theme.Palette.canvas)
        .environment(\.colorScheme, Theme.bodyScheme)
    }
}
