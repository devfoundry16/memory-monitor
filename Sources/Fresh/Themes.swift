import Foundation
import Observation
import SwiftUI

/// A visual theme whose palette comes from a DESIGN.md file in VoltAgent/awesome-design-md
/// (MIT licensed). Themes carry neutral names; the source file is noted on each.
/// Values marked "derived" are not in that file and were picked to fit the system.
struct AppTheme: Identifiable {
    enum Family {
        case named(String)
        case system
        case systemSerif
    }

    let id: String
    let name: String
    let summary: String

    // Accent: highlights, primary buttons, focus, bars.
    let accent: Color
    let accentPressed: Color
    let onAccent: Color

    // Frame: the window header and the menu bar dropdown.
    let frame: Color
    let frameCard: Color
    let frameHairline: Color
    let onFrame: Color
    let onFrameMute: Color
    let frameIsDark: Bool

    // Body: the process list and sheets.
    let canvas: Color
    let canvasSoft: Color
    let hairline: Color
    let ink: Color
    let body: Color
    let mute: Color
    let ash: Color
    let bodyIsDark: Bool

    // Selected list row and active pill tab.
    let selection: Color
    let onSelection: Color
    let onSelectionMute: Color

    let warning: Color
    let error: Color
    let errorPressed: Color

    /// Tabs, inputs and badges.
    let controlRadius: CGFloat
    /// Buttons; a large value makes pills.
    let buttonRadius: CGFloat
    let cardRadius: CGFloat
    let textFamily: Family
    let headingFamily: Family
    /// NVIDIA's green corner squares.
    let cornerMark: Bool
    let uppercaseLabels: Bool
}

extension AppTheme {
    static let all: [AppTheme] = [.volt, .terracotta, .cobalt, .gold, .midnight, .indigo, .mono]

    static func named(_ id: String?) -> AppTheme {
        let id = id.flatMap { legacyIDs[$0] } ?? id
        return all.first { $0.id == id } ?? .volt
    }

    /// Saved choices from before themes got neutral names.
    private static let legacyIDs = [
        "nvidia": "volt", "claude": "terracotta", "meta": "cobalt", "binance": "gold",
        "spotify": "midnight", "linear": "indigo", "vercel": "mono", "apple": "cobalt",
    ]

    /// Palette from design-md/nvidia.
    static let volt = AppTheme(
        id: "volt", name: "Volt", summary: "Electric green on black, sharp corners",
        accent: Color(hex: 0x76B900), accentPressed: Color(hex: 0x5A8D00), onAccent: Color(hex: 0x000000),
        frame: Color(hex: 0x000000), frameCard: Color(hex: 0x1A1A1A), frameHairline: Color(hex: 0x5E5E5E),
        onFrame: Color(hex: 0xFFFFFF), onFrameMute: Color.white.opacity(0.7), frameIsDark: true,
        canvas: Color(hex: 0xFFFFFF), canvasSoft: Color(hex: 0xF7F7F7), hairline: Color(hex: 0xCCCCCC),
        ink: Color(hex: 0x000000), body: Color(hex: 0x1A1A1A), mute: Color(hex: 0x757575), ash: Color(hex: 0xA7A7A7),
        bodyIsDark: false,
        selection: Color(hex: 0x000000), onSelection: Color(hex: 0xFFFFFF), onSelectionMute: Color.white.opacity(0.7),
        warning: Color(hex: 0xDF6500), error: Color(hex: 0xE52020), errorPressed: Color(hex: 0x650B0B),
        controlRadius: 2, buttonRadius: 2, cardRadius: 2,
        textFamily: .named("Arial"), headingFamily: .named("Arial"), // NVIDIA-EMEA's documented fallback
        cornerMark: true, uppercaseLabels: true)

    /// Palette from design-md/claude.
    static let terracotta = AppTheme(
        id: "terracotta", name: "Terracotta", summary: "Warm clay on cream, serif",
        accent: Color(hex: 0xCC785C), accentPressed: Color(hex: 0xA9583E), onAccent: Color(hex: 0xFFFFFF),
        frame: Color(hex: 0x181715), frameCard: Color(hex: 0x252320), frameHairline: Color(hex: 0x3A3835), // derived
        onFrame: Color(hex: 0xFAF9F5), onFrameMute: Color(hex: 0xA09D96), frameIsDark: true,
        canvas: Color(hex: 0xFAF9F5), canvasSoft: Color(hex: 0xF5F0E8), hairline: Color(hex: 0xE6DFD8),
        ink: Color(hex: 0x141413), body: Color(hex: 0x3D3D3A), mute: Color(hex: 0x6C6A64), ash: Color(hex: 0x8E8B82),
        bodyIsDark: false,
        selection: Color(hex: 0x181715), onSelection: Color(hex: 0xFAF9F5), onSelectionMute: Color(hex: 0xA09D96),
        warning: Color(hex: 0xD4A017), error: Color(hex: 0xC64545), errorPressed: Color(hex: 0x9E3535), // derived
        controlRadius: 8, buttonRadius: 8, cardRadius: 12,
        textFamily: .system, headingFamily: .systemSerif, // Styrene / Copernicus are proprietary
        cornerMark: false, uppercaseLabels: false)

    /// Palette from design-md/meta.
    static let cobalt = AppTheme(
        id: "cobalt", name: "Cobalt", summary: "Deep blue, pill buttons",
        accent: Color(hex: 0x0064E0), accentPressed: Color(hex: 0x0457CB), onAccent: Color(hex: 0xFFFFFF),
        frame: Color(hex: 0x0A1317), frameCard: Color(hex: 0x1C1E21), frameHairline: Color(hex: 0x444950),
        onFrame: Color(hex: 0xFFFFFF), onFrameMute: Color(hex: 0xBCC0C4), frameIsDark: true,
        canvas: Color(hex: 0xFFFFFF), canvasSoft: Color(hex: 0xF1F4F7), hairline: Color(hex: 0xDEE3E9),
        ink: Color(hex: 0x1C1E21), body: Color(hex: 0x444950), mute: Color(hex: 0x5D6C7B), ash: Color(hex: 0x8595A4),
        bodyIsDark: false,
        selection: Color(hex: 0x1C1E21), onSelection: Color(hex: 0xFFFFFF), onSelectionMute: Color(hex: 0xBCC0C4),
        warning: Color(hex: 0xF7B928), error: Color(hex: 0xE41E3F), errorPressed: Color(hex: 0xB3122F), // derived
        controlRadius: 6, buttonRadius: 100, cardRadius: 16,
        textFamily: .system, headingFamily: .system, // Optimistic VF is proprietary
        cornerMark: false, uppercaseLabels: false)

    /// Palette from design-md/binance.
    static let gold = AppTheme(
        id: "gold", name: "Gold", summary: "Yellow on near-black",
        accent: Color(hex: 0xFCD535), accentPressed: Color(hex: 0xF0B90B), onAccent: Color(hex: 0x181A20),
        frame: Color(hex: 0x0B0E11), frameCard: Color(hex: 0x1E2329), frameHairline: Color(hex: 0x2B3139),
        onFrame: Color(hex: 0xFFFFFF), onFrameMute: Color(hex: 0x929AA5), frameIsDark: true,
        canvas: Color(hex: 0xFFFFFF), canvasSoft: Color(hex: 0xFAFAFA), hairline: Color(hex: 0xEAECEF),
        ink: Color(hex: 0x181A20), body: Color(hex: 0x181A20), mute: Color(hex: 0x707A8A), ash: Color(hex: 0x929AA5),
        bodyIsDark: false,
        selection: Color(hex: 0x1E2329), onSelection: Color(hex: 0xFFFFFF), onSelectionMute: Color(hex: 0x929AA5),
        // Orange, not yellow, so warnings don't blend into the accent.
        warning: Color(hex: 0xF7931A), error: Color(hex: 0xF6465D), errorPressed: Color(hex: 0xD9304A), // derived
        controlRadius: 6, buttonRadius: 6, cardRadius: 12,
        textFamily: .system, headingFamily: .system, // BinanceNova is proprietary; its fallback is the system font
        cornerMark: false, uppercaseLabels: false)

    /// Palette from design-md/spotify.
    static let midnight = AppTheme(
        id: "midnight", name: "Midnight", summary: "Green on all-dark",
        accent: Color(hex: 0x1ED760), accentPressed: Color(hex: 0x1DB954), onAccent: Color(hex: 0x000000),
        frame: Color(hex: 0x121212), frameCard: Color(hex: 0x181818), frameHairline: Color(hex: 0x4D4D4D),
        onFrame: Color(hex: 0xFFFFFF), onFrameMute: Color(hex: 0xB3B3B3), frameIsDark: true,
        canvas: Color(hex: 0x181818), canvasSoft: Color(hex: 0x1F1F1F), hairline: Color(hex: 0x272727),
        ink: Color(hex: 0xFFFFFF), body: Color(hex: 0xCBCBCB), mute: Color(hex: 0xB3B3B3), ash: Color(hex: 0x7C7C7C),
        bodyIsDark: true,
        selection: Color(hex: 0x333333), onSelection: Color(hex: 0xFFFFFF), onSelectionMute: Color(hex: 0xB3B3B3), // derived
        warning: Color(hex: 0xFFA42B), error: Color(hex: 0xF3727F), errorPressed: Color(hex: 0xD9606C), // derived
        controlRadius: 6, buttonRadius: 999, cardRadius: 8,
        textFamily: .named("Helvetica Neue"), headingFamily: .named("Helvetica Neue"), // Circular's fallback
        cornerMark: false, uppercaseLabels: true)

    /// Palette from design-md/linear.app.
    static let indigo = AppTheme(
        id: "indigo", name: "Indigo", summary: "Indigo on near-black",
        accent: Color(hex: 0x5E6AD2), accentPressed: Color(hex: 0x5E69D1), onAccent: Color(hex: 0xFFFFFF),
        frame: Color(hex: 0x010102), frameCard: Color(hex: 0x0F1011), frameHairline: Color(hex: 0x23252A),
        onFrame: Color(hex: 0xF7F8F8), onFrameMute: Color(hex: 0x8A8F98), frameIsDark: true,
        canvas: Color(hex: 0x0F1011), canvasSoft: Color(hex: 0x141516), hairline: Color(hex: 0x23252A),
        ink: Color(hex: 0xF7F8F8), body: Color(hex: 0xD0D6E0), mute: Color(hex: 0x8A8F98), ash: Color(hex: 0x62666D),
        bodyIsDark: true,
        selection: Color(hex: 0x23252A), onSelection: Color(hex: 0xF7F8F8), onSelectionMute: Color(hex: 0x8A8F98),
        warning: Color(hex: 0xF2994A), error: Color(hex: 0xEB5757), errorPressed: Color(hex: 0xC94545), // derived
        controlRadius: 6, buttonRadius: 6, cardRadius: 12,
        textFamily: .system, headingFamily: .system, // Linear Text / Inter are not on macOS
        cornerMark: false, uppercaseLabels: false)

    /// Palette from design-md/vercel.
    static let mono = AppTheme(
        id: "mono", name: "Mono", summary: "Black and white, light header",
        accent: Color(hex: 0x171717), accentPressed: Color(hex: 0x000000), onAccent: Color(hex: 0xFFFFFF),
        frame: Color(hex: 0xFAFAFA), frameCard: Color(hex: 0xFFFFFF), frameHairline: Color(hex: 0xEBEBEB),
        onFrame: Color(hex: 0x171717), onFrameMute: Color(hex: 0x4D4D4D), frameIsDark: false,
        canvas: Color(hex: 0xFFFFFF), canvasSoft: Color(hex: 0xFAFAFA), hairline: Color(hex: 0xEBEBEB),
        ink: Color(hex: 0x171717), body: Color(hex: 0x4D4D4D), mute: Color(hex: 0x888888), ash: Color(hex: 0xA1A1A1),
        bodyIsDark: false,
        selection: Color(hex: 0x171717), onSelection: Color(hex: 0xF2F2F2), onSelectionMute: Color(hex: 0xA1A1A1),
        warning: Color(hex: 0xF5A623), error: Color(hex: 0xEE0000), errorPressed: Color(hex: 0xC50000),
        controlRadius: 6, buttonRadius: 100, cardRadius: 12,
        textFamily: .system, headingFamily: .system, // Geist / Inter are not on macOS
        cornerMark: false, uppercaseLabels: false)
}

/// The selected theme. Views read it through `Theme`, so changing it re-renders everything.
@MainActor
@Observable
final class ThemeStore {
    static let shared = ThemeStore()

    private static let key = "theme"

    var current: AppTheme {
        didSet { UserDefaults.standard.set(current.id, forKey: Self.key) }
    }

    private init() {
        current = AppTheme.named(UserDefaults.standard.string(forKey: Self.key))
    }
}
