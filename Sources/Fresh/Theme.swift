import MemoryCore
import SwiftUI

/// Design tokens for the selected theme (see Themes.swift). Everything reads through
/// here, so switching theme re-renders the whole UI.
@MainActor
enum Theme {
    static var current: AppTheme { ThemeStore.shared.current }

    @MainActor enum Palette {
        static var primary: Color { current.accent }
        static var primaryDark: Color { current.accentPressed }
        static var onPrimary: Color { current.onAccent }

        static var frame: Color { current.frame }
        static var frameCard: Color { current.frameCard }
        static var frameHairline: Color { current.frameHairline }
        static var onFrame: Color { current.onFrame }
        static var onFrameMute: Color { current.onFrameMute }

        static var canvas: Color { current.canvas }
        static var surfaceSoft: Color { current.canvasSoft }
        static var hairline: Color { current.hairline }
        static var ink: Color { current.ink }
        static var body: Color { current.body }
        static var mute: Color { current.mute }
        static var ash: Color { current.ash }

        static var selection: Color { current.selection }
        static var onSelection: Color { current.onSelection }
        static var onSelectionMute: Color { current.onSelectionMute }

        static var warning: Color { current.warning }
        static var error: Color { current.error }
        static var errorDeep: Color { current.errorPressed }
    }

    enum Space {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
        static let xxl: CGFloat = 32
    }

    /// Tabs, inputs, badges.
    static var radius: CGFloat { current.controlRadius }
    static var buttonRadius: CGFloat { current.buttonRadius }
    static var cardRadius: CGFloat { current.cardRadius }

    static var frameScheme: ColorScheme { current.frameIsDark ? .dark : .light }
    static var bodyScheme: ColorScheme { current.bodyIsDark ? .dark : .light }

    /// Labels and eyebrows: uppercase in themes whose design calls for it.
    static func label(_ text: String) -> String {
        current.uppercaseLabels ? text.uppercased() : text
    }

    /// Sizes are scaled down from each design's web scale for a dense desktop window.
    @MainActor enum Typeface {
        static func font(_ size: CGFloat, bold: Bool = false, heading: Bool = false) -> Font {
            let weight: Font.Weight = bold ? .bold : .regular
            switch heading ? current.headingFamily : current.textFamily {
            case .named(let name): return .custom(name, size: size).weight(weight)
            case .system: return .system(size: size, weight: weight)
            case .systemSerif: return .system(size: size, weight: weight, design: .serif)
            }
        }
        static var displayLg: Font { font(36, bold: true, heading: true) }
        static var headingMd: Font { font(20, bold: true, heading: true) }
        static var cardValue: Font { font(28, bold: true, heading: true) }
        static var cardPercent: Font { font(16, bold: true) }
        static var cardSummary: Font { font(12) }
        static var body: Font { font(13) }
        static var bodyStrong: Font { font(13, bold: true) }
        static var captionMd: Font { font(11, bold: true) } // eyebrow
        static var captionSm: Font { font(11) }
        static var button: Font { font(13, bold: true) }
    }

    static func pressureColor(_ pressure: MemoryPressure) -> Color {
        switch pressure {
        case .normal: Palette.primary
        case .warning: Palette.warning
        case .critical: Palette.error
        }
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

// MARK: - Components

/// The 12px green square NVIDIA anchors to a card corner. Other themes don't use it.
struct CornerSquare: View {
    var size: CGFloat = 12
    var body: some View {
        if Theme.current.cornerMark {
            Rectangle().fill(Theme.Palette.primary).frame(width: size, height: size)
        }
    }
}

/// Small label above a value (`caption-md`).
struct Eyebrow: View {
    let text: String
    var color: Color = Theme.Palette.mute
    init(_ text: String, color: Color = Theme.Palette.mute) {
        self.text = text
        self.color = color
    }
    var body: some View {
        Text(Theme.label(text)).font(Theme.Typeface.captionMd).foregroundStyle(color)
    }
}

struct PressureBadge: View {
    let pressure: MemoryPressure
    var body: some View {
        Text(label)
            .font(Theme.Typeface.captionMd)
            .foregroundStyle(textColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Theme.pressureColor(pressure), in: .rect(cornerRadius: Theme.radius))
    }
    private var textColor: Color {
        switch pressure {
        case .normal: Theme.Palette.onPrimary
        case .warning: .black
        case .critical: .white
        }
    }
    private var label: String {
        switch pressure {
        case .normal: Theme.label("Pressure normal")
        case .warning: Theme.label("Pressure warning")
        case .critical: Theme.label("Pressure critical")
        }
    }
}

/// `button-primary`: accent fill, darker when pressed.
struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.button)
            .foregroundStyle(Theme.Palette.onPrimary)
            .padding(.horizontal, Theme.Space.xl)
            .frame(height: 32)
            .background(
                configuration.isPressed ? Theme.Palette.primaryDark : Theme.Palette.primary,
                in: .rect(cornerRadius: Theme.buttonRadius))
            .contentShape(.rect)
    }
}

/// `button-outline`: transparent with a 2px accent border. Disabled → `button-disabled`.
struct OutlineButtonStyle: ButtonStyle {
    /// Text colour; pass the "on" colour of whatever surface the button sits on.
    var foreground: Color = Theme.Palette.ink
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.button)
            .foregroundStyle(isEnabled ? foreground : Theme.Palette.ash)
            .padding(.horizontal, Theme.Space.md)
            .frame(height: 28)
            .background(isEnabled ? Color.clear : Theme.Palette.surfaceSoft, in: .rect(cornerRadius: Theme.buttonRadius))
            .overlay {
                if isEnabled {
                    RoundedRectangle(cornerRadius: Theme.buttonRadius)
                        .strokeBorder(configuration.isPressed ? Theme.Palette.primaryDark : Theme.Palette.primary, lineWidth: 2)
                }
            }
            .contentShape(.rect)
    }
}

/// Destructive confirmation: the only red fill in the app.
struct DestructiveButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.Typeface.button)
            .foregroundStyle(.white)
            .padding(.horizontal, Theme.Space.xl)
            .frame(height: 32)
            .background(
                configuration.isPressed ? Theme.Palette.errorDeep : Theme.Palette.error,
                in: .rect(cornerRadius: Theme.buttonRadius))
            .contentShape(.rect)
    }
}

/// `pill-tab` segmented control: the active tab takes the selection colours.
struct PillTabs<Value: Hashable>: View {
    let options: [(Value, String)]
    @Binding var selection: Value

    var body: some View {
        HStack(spacing: Theme.Space.xs) {
            ForEach(options, id: \.0) { value, title in
                let active = value == selection
                Button { selection = value } label: {
                    Text(Theme.label(title))
                        .font(Theme.Typeface.captionMd)
                        .foregroundStyle(active ? Theme.Palette.onSelection : Theme.Palette.ink)
                        .padding(.horizontal, 14)
                        .frame(height: 28)
                        .background(active ? Theme.Palette.selection : .clear, in: .rect(cornerRadius: Theme.buttonRadius))
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// `search-input`: 1px hairline border, 2px accent border when focused.
struct SearchField: View {
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: Theme.Space.sm) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.Palette.mute)
            TextField("Search processes", text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typeface.body)
                .foregroundStyle(Theme.Palette.ink)
                .focused($focused)
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark").foregroundStyle(Theme.Palette.mute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Space.md)
        .frame(width: 260, height: 30)
        .background(Theme.Palette.canvas, in: .rect(cornerRadius: Theme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(focused ? Theme.Palette.primary : Theme.Palette.hairline, lineWidth: focused ? 2 : 1))
    }
}
