import MemoryCore
import SwiftUI

/// General (theme picker and menu bar options, side by side) and the Quick List.
struct SettingsSheet: View {
    @Environment(MonitorStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    /// Theme column + gap + divider + gap + menu bar column.
    private static let generalWidth: CGFloat = 400 + Theme.Space.xl + 1 + Theme.Space.xl + 300

    var body: some View {
        @Bindable var store = store
        @Bindable var themes = ThemeStore.shared
        VStack(alignment: .leading, spacing: Theme.Space.lg) {
            HStack(spacing: Theme.Space.sm) {
                CornerSquare()
                Eyebrow("Settings")
                Spacer()
                PillTabs(options: [(SettingsSection.general, "General"), (.quickList, "Quick List")],
                         selection: $store.settingsSection)
            }

            // Both tabs stay laid out, one on top of the other, so the sheet is always the size
            // of the larger (General) and never resizes when switching.
            ZStack(alignment: .topLeading) {
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
                            CheckRow(title: "Disk", symbol: Resource.disk.symbol, isOn: $store.menuBarSettings.showDisk)
                            CheckRow(title: "Memory", symbol: Resource.memory.symbol, isOn: $store.menuBarSettings.showMemory)
                            CheckRow(title: "CPU", symbol: Resource.cpu.symbol, isOn: $store.menuBarSettings.showCPU)
                            CheckRow(title: "GPU", symbol: Resource.gpu.symbol, isOn: $store.menuBarSettings.showGPU)
                            CheckRow(title: "Icons", symbol: "photo", isOn: $store.menuBarSettings.showIcons)
                        }

                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Eyebrow("Memory as")
                            PillTabs(
                                options: [(MenuBarSettings.MemoryStyle.percent, "Percent"), (.size, "Size"), (.both, "Size + %")],
                                selection: $store.menuBarSettings.memoryStyle)
                                .disabled(!store.menuBarSettings.showMemory)
                                .opacity(store.menuBarSettings.showMemory ? 1 : 0.4)
                        }

                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Eyebrow("Disk as")
                            PillTabs(
                                options: [(MenuBarSettings.DiskStyle.percent, "Percent used"), (.free, "Free space")],
                                selection: $store.menuBarSettings.diskStyle)
                                .disabled(!store.menuBarSettings.showDisk)
                                .opacity(store.menuBarSettings.showDisk ? 1 : 0.4)
                        }

                        VStack(alignment: .leading, spacing: Theme.Space.sm) {
                            Eyebrow("Dropdown shows")
                            CheckRow(title: "Disk", symbol: Resource.disk.symbol, isOn: $store.menuBarSettings.dropdownDisk)
                            CheckRow(title: "Memory", symbol: Resource.memory.symbol, isOn: $store.menuBarSettings.dropdownMemory)
                            CheckRow(title: "CPU", symbol: Resource.cpu.symbol, isOn: $store.menuBarSettings.dropdownCPU)
                            CheckRow(title: "GPU", symbol: Resource.gpu.symbol, isOn: $store.menuBarSettings.dropdownGPU)
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
                .shown(store.settingsSection == .general)

                QuickListSettings()
                    .frame(width: Self.generalWidth, alignment: .topLeading)
                    .shown(store.settingsSection == .quickList)
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

private extension View {
    /// Hides an inactive Settings tab while keeping its space.
    func shown(_ visible: Bool) -> some View {
        opacity(visible ? 1 : 0)
            .allowsHitTesting(visible)
            .accessibilityHidden(!visible)
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

/// A checkbox with an icon and a title.
private struct CheckRow: View {
    let title: String
    let symbol: String
    @Binding var isOn: Bool

    var body: some View {
        Button { isOn.toggle() } label: {
            HStack(spacing: Theme.Space.md) {
                CheckBox(isOn: isOn)
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
