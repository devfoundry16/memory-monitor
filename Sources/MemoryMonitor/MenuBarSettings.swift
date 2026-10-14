import Foundation

/// What the menu bar item shows. Saved in UserDefaults.
struct MenuBarSettings: Codable, Equatable {
    enum MemoryStyle: String, Codable, CaseIterable {
        case percent, size, both
    }

    var showMemory = true
    var showCPU = true
    var showGPU = true
    var showIcons = true
    /// Percent by default, matching CPU and GPU; size is opt-in.
    var memoryStyle = MemoryStyle.percent

    private static let key = "menuBarSettings"

    static func load() -> MenuBarSettings {
        guard let data = UserDefaults.standard.data(forKey: key),
              let settings = try? JSONDecoder().decode(MenuBarSettings.self, from: data) else {
            return MenuBarSettings()
        }
        return settings
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }
}
