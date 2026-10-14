import MemoryCore
import SwiftUI

/// Theme picker and menu bar options, side by side.
struct SettingsSheet: View {
    @Environment(MonitorStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        @Bindable var themes = ThemeStore.shared
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                CornerSquare()
                Eyebrow("Settings")
            }

            HStack(alignment: .top, spacing: Theme.Space.xl) {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Theme")
                        .font(Theme.Typeface.headingMd)
                        .foregroundStyle(Theme.Palette.ink)
                    Text("From the design systems in VoltAgent/awesome-design-md.")
                        .font(Theme.Typeface.captionSm)
                        .foregroundStyle(Theme.Palette.mute)
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: Theme.Space.sm), GridItem(.flexible())],
                              spacing: Theme.Space.sm) {
                        ForEach(AppTheme.all) { theme in
                            ThemeCard(theme: theme, selected: theme.id == themes.current.id) {
                                themes.current = theme
                            }
                        }
                    }
                }
                .frame(width: 400)

                Theme.Palette.hairline.frame(width: 1)

                VStack(alignment: .leading, spacing: Theme.Space.lg) {
                    Text("Menu bar")
                        .font(Theme.Typeface.headingMd)
                        .foregroundStyle(Theme.Palette.ink)

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Eyebrow("Show")
                        CheckRow(title: "Memory", symbol: Resource.memory.symbol, isOn: $store.menuBarSettings.showMemory)
                        CheckRow(title: "CPU", symbol: Resource.cpu.symbol, isOn: $store.menuBarSettings.showCPU)
                        CheckRow(title: "GPU", symbol: Resource.gpu.symbol, isOn: $store.menuBarSettings.showGPU)
                        CheckRow(title: "Icons", symbol: "photo", isOn: $store.menuBarSettings.showIcons)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Eyebrow("Memory as")
                        PillTabs(
                            options: [(MenuBarSettings.MemoryStyle.both, "Size + %"), (.percent, "Percent"), (.size, "Size")],
                            selection: $store.menuBarSettings.memoryStyle)
                            .disabled(!store.menuBarSettings.showMemory)
                            .opacity(store.menuBarSettings.showMemory ? 1 : 0.4)
                    }

                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        Eyebrow("Preview")
                        // The real menu bar is drawn by macOS, so preview it on a neutral bar.
                        HStack {
                            Image(nsImage: StatusLabel.image(for: store))
                                .renderingMode(.template)
                                .foregroundStyle(Color.white)
                            Spacer()
                        }
                        .padding(.horizontal, Theme.Space.md)
                        .frame(height: 32)
                        .background(Color(hex: 0x2B2B2B), in: .rect(cornerRadius: Theme.radius))
                    }
                }
                .frame(width: 300)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.Space.xl)
        .background(Theme.Palette.canvas)
        .environment(\.colorScheme, Theme.bodyScheme)
    }
}

/// A theme's own colours in miniature: its header with an accent figure over its body.
private struct ThemeCard: View {
    let theme: AppTheme
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        RoundedRectangle(cornerRadius: min(theme.cardRadius, 3)).fill(theme.accent).frame(width: 26, height: 7)
                        RoundedRectangle(cornerRadius: min(theme.cardRadius, 3)).fill(theme.frameCard).frame(width: 18, height: 7)
                        Spacer()
                        Circle().fill(theme.accent).frame(width: 7, height: 7)
                    }
                    RoundedRectangle(cornerRadius: 1).fill(theme.onFrameMute).frame(width: 60, height: 3)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .frame(height: 38)
                .background(theme.frame)
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(theme.name)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(theme.ink)
                        Text(theme.summary)
                            .font(.system(size: 10))
                            .foregroundStyle(theme.mute)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                    if selected {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(theme.accent)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.canvas)
            }
            .clipShape(.rect(cornerRadius: Theme.cardRadius))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.cardRadius)
                    .strokeBorder(selected ? Theme.Palette.primary : Theme.Palette.hairline, lineWidth: selected ? 2 : 1))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(theme.summary)
    }
}

/// A themed checkbox: 2px-radius square that fills NVIDIA green when on.
private struct CheckRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Theme.Space.md) {
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .fill(isOn ? Theme.Palette.primary : Theme.Palette.canvas)
                    RoundedRectangle(cornerRadius: Theme.radius)
                        .strokeBorder(isOn ? Theme.Palette.primary : Theme.Palette.hairline, lineWidth: 1)
                    if isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundStyle(Theme.Palette.onPrimary)
                    }
                }
                .frame(width: 18, height: 18)
                Image(systemName: symbol)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.Palette.body)
                    .frame(width: 18)
                Text(title)
                    .font(Theme.Typeface.body)
                    .foregroundStyle(Theme.Palette.ink)
                Spacer()
            }
            .frame(height: 26)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }
}
