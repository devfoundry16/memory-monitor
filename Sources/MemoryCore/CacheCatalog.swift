import Foundation

/// A path under a base. A "*" component matches each existing child folder, one level at a time.
public struct PathPattern: Sendable {
    public var base: CacheBase
    public var components: [String]

    public init(_ base: CacheBase, _ components: [String]) {
        self.base = base
        self.components = components
    }
}

/// A well-known cache, with a proper name, owner and any caveats.
public struct CatalogEntry: Sendable {
    public var id: String
    public var name: String
    public var detail: String?
    public var category: CacheCategory
    public var owner: CacheOwner?
    public var patterns: [PathPattern]
    public var advisory: Advisory?
    /// Chromium's SingletonLock, which tells whether the browser is running.
    public var lock: PathPattern?

    init(id: String, name: String, detail: String? = nil, category: CacheCategory, owner: CacheOwner?,
         patterns: [PathPattern], advisory: Advisory? = nil, lock: PathPattern? = nil) {
        self.id = id
        self.name = name
        self.detail = detail
        self.category = category
        self.owner = owner
        self.patterns = patterns
        self.advisory = advisory
        self.lock = lock
    }
}

/// Known caches and owners. Anything not listed here is still found by discovery, under a
/// generic name; this adds names, owners and warnings, and takes precedence.
public enum CacheCatalog {
    public static let entries: [CatalogEntry] = browsers + developerTools

    // MARK: Browsers

    private static let profile = "*"

    /// Two items per Chromium browser: its web cache (safe) and offline web data (caution).
    private static func chromium(
        id: String, name: String, bundleIDs: [String], caches: [String], userData: [String]
    ) -> [CatalogEntry] {
        let owner = CacheOwner(name: name, bundleIDs: bundleIDs)
        let lock = PathPattern(.applicationSupport, userData + ["SingletonLock"])
        let profileLeaves = CachePathPolicy.chromiumCacheLeaves.map {
            PathPattern(.applicationSupport, userData + [profile] + $0)
        }
        let topLevel = [["GrShaderCache"], ["ShaderCache"], ["GraphiteDawnCache"]].map {
            PathPattern(.applicationSupport, userData + $0)
        }
        return [
            CatalogEntry(
                id: id, name: name, detail: "Web cache", category: .browsers, owner: owner,
                patterns: [PathPattern(.libraryCaches, caches)] + profileLeaves + topLevel, lock: lock),
            CatalogEntry(
                id: id + "#offline", name: name, detail: "Offline web data", category: .browsers, owner: owner,
                patterns: CachePathPolicy.chromiumOfflineLeaves.map { PathPattern(.applicationSupport, userData + [profile] + $0) },
                advisory: .caution("Pages and files sites saved for offline use, such as offline Google Docs. Sign-ins stay."),
                lock: lock),
        ]
    }

    static let browsers: [CatalogEntry] =
        chromium(id: "chrome", name: "Google Chrome", bundleIDs: ["com.google.Chrome"],
                 caches: ["Google", "Chrome"], userData: ["Google", "Chrome"])
        + chromium(id: "chrome-beta", name: "Google Chrome Beta", bundleIDs: ["com.google.Chrome.beta"],
                   caches: ["Google", "Chrome Beta"], userData: ["Google", "Chrome Beta"])
        + chromium(id: "chrome-canary", name: "Google Chrome Canary", bundleIDs: ["com.google.Chrome.canary"],
                   caches: ["Google", "Chrome Canary"], userData: ["Google", "Chrome Canary"])
        + chromium(id: "brave", name: "Brave", bundleIDs: ["com.brave.Browser"],
                   caches: ["BraveSoftware", "Brave-Browser"], userData: ["BraveSoftware", "Brave-Browser"])
        + chromium(id: "edge", name: "Microsoft Edge", bundleIDs: ["com.microsoft.edgemac"],
                   caches: ["Microsoft Edge"], userData: ["Microsoft Edge"])
        + chromium(id: "arc", name: "Arc", bundleIDs: ["company.thebrowser.Browser"],
                   caches: ["Arc"], userData: ["Arc", "User Data"])
        + chromium(id: "vivaldi", name: "Vivaldi", bundleIDs: ["com.vivaldi.Vivaldi"],
                   caches: ["Vivaldi"], userData: ["Vivaldi"])
        + chromium(id: "chromium", name: "Chromium", bundleIDs: ["org.chromium.Chromium"],
                   caches: ["Chromium"], userData: ["Chromium"])
        + [
            CatalogEntry(
                id: "firefox", name: "Firefox", detail: "Web cache", category: .browsers,
                owner: CacheOwner(name: "Firefox", bundleIDs: [
                    "org.mozilla.firefox", "org.mozilla.firefoxdeveloperedition", "org.mozilla.nightly",
                ]),
                patterns: [PathPattern(.libraryCaches, ["Firefox"])]),
        ]

    // MARK: Developer tools

    private static func tool(
        _ id: String, _ name: String, _ patterns: [PathPattern], process: [String] = [],
        bundleIDs: [String] = [], _ advisory: Advisory? = nil
    ) -> CatalogEntry {
        CatalogEntry(
            id: id, name: name, detail: nil, category: .developer,
            owner: CacheOwner(name: name, bundleIDs: bundleIDs, processNames: process),
            patterns: patterns, advisory: advisory)
    }

    static let developerTools: [CatalogEntry] = [
        tool("npm", "npm", [PathPattern(.home, [".npm", "_cacache"])], process: ["npm", "npx", "pnpm"]),
        tool("npx", "npx packages", [PathPattern(.home, [".npm", "_npx"])],
             process: ["npx", RunningProbe.npxPackageRunning],
             .caution("Packages started with npx, including MCP servers that may be running now.")),
        tool("npm-logs", "npm logs", [PathPattern(.home, [".npm", "_logs"])]),
        tool("homebrew", "Homebrew", [PathPattern(.libraryCaches, ["Homebrew"])], process: ["brew"],
             .info("Downloaded packages; the same as brew cleanup --prune=all.")),
        tool("cocoapods", "CocoaPods", [PathPattern(.libraryCaches, ["CocoaPods"])], process: ["pod"]),
        tool("pip", "pip", [PathPattern(.libraryCaches, ["pip"])], process: ["pip", "pip3"]),
        tool("yarn", "Yarn", [PathPattern(.libraryCaches, ["Yarn"]), PathPattern(.home, [".yarn", "berry", "cache"])],
             process: ["yarn"]),
        tool("go-build", "Go build cache", [PathPattern(.libraryCaches, ["go-build"])], process: ["go"]),
        tool("uv", "uv", [PathPattern(.dotCache, ["uv"])], process: ["uv"],
             .info("May free less than shown: uv shares these files with virtual environments.")),
        tool("cargo", "Cargo", [PathPattern(.home, [".cargo", "registry", "cache"]),
                                PathPattern(.home, [".cargo", "registry", "src"])], process: ["cargo"]),
        tool("bun", "Bun", [PathPattern(.home, [".bun", "install", "cache"])], process: ["bun"]),
        tool("gradle", "Gradle", [PathPattern(.home, [".gradle", "caches"])], process: ["gradle"]),
        tool("xcode", "Xcode", [PathPattern(.home, ["Library", "Developer", "Xcode", "DerivedData"]),
                                PathPattern(.home, ["Library", "Developer", "CoreSimulator", "Caches"])],
             bundleIDs: ["com.apple.dt.Xcode"], .info("Build products; projects rebuild from scratch next time.")),
        tool("playwright", "Playwright browsers", [PathPattern(.libraryCaches, ["ms-playwright"])],
             .caution("Browsers Playwright downloaded. Reinstall with npx playwright install.")),
        tool("playwright-mcp", "Playwright MCP", [PathPattern(.libraryCaches, ["ms-playwright-mcp"])],
             .caution("Browser profiles the Playwright MCP server uses, including sign-ins.")),
        tool("puppeteer", "Puppeteer browsers", [PathPattern(.dotCache, ["puppeteer"])],
             .caution("Browsers Puppeteer downloaded. Reinstall with npx puppeteer browsers install chrome.")),
        tool("chrome-devtools-mcp", "Chrome DevTools MCP", [PathPattern(.dotCache, ["chrome-devtools-mcp"])],
             .caution("A browser profile the Chrome DevTools MCP server uses, including sign-ins.")),
        tool("codex-runtimes", "Codex runtimes", [PathPattern(.dotCache, ["codex-runtimes"])],
             bundleIDs: ["com.openai.codex"], .caution("Runtimes Codex uses; downloaded again the next time it starts.")),
        tool("pre-commit", "pre-commit", [PathPattern(.dotCache, ["pre-commit"])], process: ["pre-commit"],
             .info("Hook environments; rebuilt on the next commit.")),
        tool("prisma", "Prisma", [PathPattern(.dotCache, ["prisma"])], .info("Engines; downloaded again when needed.")),
        tool("claude-code", "Claude Code MCP logs", [PathPattern(.libraryCaches, ["claude-cli-nodejs"])],
             .info("Logs from the MCP servers Claude Code runs, one folder per project.")),
        tool("electron", "Electron downloads", [PathPattern(.libraryCaches, ["electron"]),
                                                PathPattern(.libraryCaches, ["electron-builder"])]),
        tool("node-gyp", "node-gyp", [PathPattern(.libraryCaches, ["node-gyp"])]),
        tool("typescript", "TypeScript", [PathPattern(.libraryCaches, ["typescript"])]),
    ]

    // MARK: Owners and names

    /// Folder names that don't match their app's name or bundle ID.
    public static let knownOwners: [String: CacheOwner] = [
        "Code": CacheOwner(name: "Visual Studio Code", bundleIDs: ["com.microsoft.VSCode"]),
        "Cursor": CacheOwner(name: "Cursor", bundleIDs: ["com.todesktop.230313mzl4w4u92"]),
        "Slack": CacheOwner(name: "Slack", bundleIDs: ["com.tinyspeck.slackmacgap"]),
        "discord": CacheOwner(name: "Discord", bundleIDs: ["com.hnc.Discord"]),
        "Microsoft Teams": CacheOwner(name: "Microsoft Teams", bundleIDs: ["com.microsoft.teams2", "com.microsoft.teams"]),
        "Notion": CacheOwner(name: "Notion", bundleIDs: ["notion.id"]),
        "notion-updater": CacheOwner(name: "Notion", bundleIDs: ["notion.id"]),
        "Linear": CacheOwner(name: "Linear", bundleIDs: ["com.linear"]),
        "ClickUp": CacheOwner(name: "ClickUp", bundleIDs: ["com.clickup.desktop-app"]),
        "Claude": CacheOwner(name: "Claude", bundleIDs: ["com.anthropic.claudefordesktop"]),
        "Wispr Flow": CacheOwner(name: "Wispr Flow", bundleIDs: ["com.electron.wispr-flow"]),
        "com.microsoft.VSCode.ShipIt": CacheOwner(name: "Visual Studio Code", bundleIDs: ["com.microsoft.VSCode"]),
    ]

    /// Apple caches whose names don't start with "com.apple.".
    public static let appleCacheNames: Set<String> = [
        "GeoServices", "GameKit", "Animoji", "AMSDataMigratorTool", "askpermissiond",
    ]

    static func isApple(_ name: String) -> Bool {
        name.hasPrefix("com.apple.") || appleCacheNames.contains(name)
    }
}
