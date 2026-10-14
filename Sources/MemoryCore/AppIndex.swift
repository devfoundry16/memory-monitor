import Foundation

/// Installed apps, for naming cache folders and telling whose cache is whose.
public struct AppIndex: Sendable {
    public struct App: Sendable, Hashable {
        public var bundleID: String
        public var name: String
        public var url: URL
    }

    private var byBundleID: [String: App] = [:]
    private var byName: [String: App] = [:]

    /// Reads each `.app` directly inside `directories`.
    public init(scanning directories: [URL]) {
        for directory in directories {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            else { continue }
            for url in children where url.pathExtension == "app" {
                let plist = url.appendingPathComponent("Contents/Info.plist")
                guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
                      let bundleID = info["CFBundleIdentifier"] as? String else { continue }
                let fileName = url.deletingPathExtension().lastPathComponent
                let app = App(bundleID: bundleID, name: fileName, url: url)
                byBundleID[bundleID.lowercased()] = byBundleID[bundleID.lowercased()] ?? app
                for alias in [fileName, info["CFBundleName"] as? String, info["CFBundleDisplayName"] as? String,
                              info["CFBundleExecutable"] as? String].compactMap({ $0 }) {
                    byName[Self.normalized(alias)] = byName[Self.normalized(alias)] ?? app
                }
            }
        }
    }

    public func app(bundleID: String) -> App? { byBundleID[bundleID.lowercased()] }
    public func app(named name: String) -> App? { byName[Self.normalized(name)] }

    private static let bundleSuffixes = [".ShipIt", ".helper", ".installer_telemetry", ".accessibility-mac-app", ".savedState"]
    private static let nameSuffixes = ["-updater", "-update", " Updater"]

    /// The app a cache folder belongs to, from its name: "com.linear.ShipIt" → Linear,
    /// "notion-updater" → Notion, "Code" → Visual Studio Code.
    public func owner(forFolderName folder: String) -> CacheOwner? {
        if let known = CacheCatalog.knownOwners[folder] {
            let installed = known.bundleIDs.lazy.compactMap { app(bundleID: $0) }.first
            return CacheOwner(name: installed?.name ?? known.name, bundleIDs: known.bundleIDs)
        }
        var candidates = [folder]
        for suffix in Self.bundleSuffixes where folder.hasSuffix(suffix) {
            candidates.append(String(folder.dropLast(suffix.count)))
        }
        for candidate in candidates {
            if let app = app(bundleID: candidate) { return CacheOwner(name: app.name, bundleIDs: [app.bundleID]) }
        }
        var names = [folder]
        for suffix in Self.nameSuffixes where folder.lowercased().hasSuffix(suffix.lowercased()) {
            names.append(String(folder.dropLast(suffix.count)))
        }
        for name in names {
            if let app = app(named: name) { return CacheOwner(name: app.name, bundleIDs: [app.bundleID]) }
        }
        return nil
    }

    /// "Visual Studio Code" → "visualstudiocode".
    static func normalized(_ name: String) -> String {
        String(name.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(Character.init))
    }
}
