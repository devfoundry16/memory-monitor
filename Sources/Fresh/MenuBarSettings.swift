import Foundation

/// What the menu bar item shows. Saved in UserDefaults.
struct MenuBarSettings: Codable, Equatable {
    enum MemoryStyle: String, Codable, CaseIterable {
        case percent, size, both
    }

    enum DiskStyle: String, Codable, CaseIterable {
        /// Share of the startup disk in use.
        case percent
        /// Available space, as Finder shows it.
        case free
    }

    var showMemory = true
    var showCPU = true
    var showGPU = true
    var showIcons = true
    /// Percent by default, matching CPU and GPU; size is opt-in.
    var memoryStyle = MemoryStyle.percent
    /// Off by default: the bar is already busy with three figures.
    var showDisk = false
    var diskStyle = DiskStyle.percent

    /// Tiles at the top of the dropdown, shown in this order.
    var dropdownDisk = true
    var dropdownMemory = true
    var dropdownCPU = true
    var dropdownGPU = true

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

extension MenuBarSettings {
    /// Missing keys keep their defaults. The synthesized decoder would fail on settings saved
    /// before a field existed, and `load()` would then reset everything.
    init(from decoder: Decoder) throws {
        self.init()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        showMemory = try container.decodeIfPresent(Bool.self, forKey: .showMemory) ?? showMemory
        showCPU = try container.decodeIfPresent(Bool.self, forKey: .showCPU) ?? showCPU
        showGPU = try container.decodeIfPresent(Bool.self, forKey: .showGPU) ?? showGPU
        showIcons = try container.decodeIfPresent(Bool.self, forKey: .showIcons) ?? showIcons
        memoryStyle = try container.decodeIfPresent(MemoryStyle.self, forKey: .memoryStyle) ?? memoryStyle
        showDisk = try container.decodeIfPresent(Bool.self, forKey: .showDisk) ?? showDisk
        diskStyle = try container.decodeIfPresent(DiskStyle.self, forKey: .diskStyle) ?? diskStyle
        dropdownDisk = try container.decodeIfPresent(Bool.self, forKey: .dropdownDisk) ?? dropdownDisk
        dropdownMemory = try container.decodeIfPresent(Bool.self, forKey: .dropdownMemory) ?? dropdownMemory
        dropdownCPU = try container.decodeIfPresent(Bool.self, forKey: .dropdownCPU) ?? dropdownCPU
        dropdownGPU = try container.decodeIfPresent(Bool.self, forKey: .dropdownGPU) ?? dropdownGPU
    }

    /// How many tiles the dropdown shows.
    var dropdownTileCount: Int {
        [dropdownDisk, dropdownMemory, dropdownCPU, dropdownGPU].filter { $0 }.count
    }
}
