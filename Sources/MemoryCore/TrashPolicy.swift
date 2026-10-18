import Foundation

/// What Move to Trash on the quick list must never touch: system locations, the home
/// folder and its standard folders, and Fresh itself.
public enum TrashPolicy {
    /// macOS's own locations. Under `/private`, only temporary folders may be trashed.
    /// Resolving a path drops `/private` (`/private/etc` → `/etc`), so both forms are listed.
    static let systemRoots = ["/System", "/Library", "/usr", "/bin", "/sbin", "/opt", "/cores", "/dev",
                              "/private", "/etc", "/var", "/tmp"]
    static let privateExceptions = ["/private/tmp", "/private/var/folders", "/tmp", "/var/folders"]
    /// Folders that hold other things; trashing one would take far more than intended.
    static let containerFolders = ["/Applications", "/Applications/Utilities", "/Volumes", "/Users"]
    static let homeFolders = ["Desktop", "Documents", "Downloads", "Library", "Applications",
                              "Movies", "Music", "Pictures", "Public"]

    /// Why `url` can't be moved to the Trash, or `nil` when it can. A symlink is judged both
    /// as itself and as what it points to.
    public static func refusal(for url: URL, home: URL, ownBundle: URL) -> String? {
        let paths = [url.standardizedFileURL.path, url.resolvingSymlinksInPath().path]
        let home = home.resolvingSymlinksInPath().path
        let own = ownBundle.resolvingSymlinksInPath().path
        for path in Set(paths) {
            if let reason = refusal(path: path, home: home, own: own) { return reason }
        }
        return nil
    }

    /// The most specific reason first, so `/Applications` says it holds apps rather than
    /// that it holds Fresh.
    private static func refusal(path: String, home: String, own: String) -> String? {
        if systemRoots.contains(where: { isSameOrInside(path, $0) }),
           !privateExceptions.contains(where: { isSameOrInside(path, $0) && path != $0 }) {
            return "Part of macOS. It can't be moved to the Trash."
        }
        if containerFolders.contains(path) { return "This folder holds other apps or users." }
        let components = path.split(separator: "/")
        if components.count == 2, components[0] == "Volumes" { return "This is a whole disk." }
        if homeFolders.contains(where: { path == home + "/" + $0 }) {
            return "One of your standard folders. macOS needs it."
        }
        if path == home { return "This is your home folder." }
        if isSameOrInside(home, path) { return "This folder holds your home folder." }
        if path == own { return "Fresh can't move itself to the Trash." }
        if isSameOrInside(own, path) { return "This folder contains Fresh." }
        return nil
    }

    /// `child` is `parent` or somewhere inside it.
    static func isSameOrInside(_ child: String, _ parent: String) -> Bool {
        child == parent || parent == "/" || child.hasPrefix(parent.hasSuffix("/") ? parent : parent + "/")
    }
}
