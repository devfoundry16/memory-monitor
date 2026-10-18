import Foundation

/// An app or folder on the dropdown's quick list.
public struct QuickItem: Codable, Sendable, Hashable, Identifiable {
    public enum Kind: String, Codable, Sendable {
        case app, folder
    }

    public var kind: Kind
    public var path: String
    /// Lets an app be found again after it moves. `nil` for folders.
    public var bundleID: String?

    public var id: String { path }
    public var url: URL { URL(fileURLWithPath: path) }

    /// "Slack" for "/Applications/Slack.app", "Projects" for "~/Projects".
    public var name: String {
        let last = url.lastPathComponent
        return kind == .app && last.hasSuffix(".app") ? String(last.dropLast(4)) : last
    }

    public init(kind: Kind, path: String, bundleID: String? = nil) {
        self.kind = kind
        self.path = path
        self.bundleID = bundleID
    }
}
