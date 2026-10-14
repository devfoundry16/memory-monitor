import AppKit
import MemoryCore
import SwiftUI

@main
struct FreshApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    // The menu bar item and the monitor window are AppKit-managed (see AppDelegate),
    // so SwiftUI only needs a placeholder scene. A never-inserted MenuBarExtra shows
    // nothing; a lone Settings scene would open an empty window at launch.
    var body: some Scene {
        MenuBarExtra("Fresh", isInserted: .constant(false)) { EmptyView() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let store = MonitorStore()
    private let cleaner = CleanerStore()
    private lazy var mainWindow = MainWindowController(store: store, cleaner: cleaner)
    private var statusItem: StatusItemController?

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Menu bar app: no Dock icon, even when run unbundled with `swift run`.
        NSApp.setActivationPolicy(.accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        store.start()
        statusItem = StatusItemController(
            store: store,
            onOpenMonitor: { [weak self] in
                self?.statusItem?.closePopover()
                self?.mainWindow.show()
            },
            onOpenSettings: { [weak self] in
                self?.statusItem?.closePopover()
                self?.mainWindow.show()
                self?.store.showingSettings = true
            })
        mainWindow.show()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

/// The menu bar item and its dropdown. SwiftUI's MenuBarExtra has no way to close its
/// panel from code, so this uses NSStatusItem + NSPopover, which "Open Monitor" can close.
@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private let popover = NSPopover()
    private let store: MonitorStore
    private let onOpenMonitor: () -> Void
    private let onOpenSettings: () -> Void

    init(store: MonitorStore, onOpenMonitor: @escaping () -> Void, onOpenSettings: @escaping () -> Void) {
        self.store = store
        self.onOpenMonitor = onOpenMonitor
        self.onOpenSettings = onOpenSettings
        super.init()

        popover.behavior = .transient // closes when you click anywhere else
        popover.delegate = self

        if let button = item.button {
            button.imagePosition = .imageOnly
            button.target = self
            button.action = #selector(togglePopover(_:))
        }
        updateLabel()
    }

    @objc func togglePopover(_ sender: Any?) {
        if popover.isShown {
            popover.performClose(sender)
        } else if let button = item.button {
            // The dropdown's view exists only while it is open, so a closed dropdown
            // doesn't re-render on every sample.
            let content = NSHostingController(
                rootView: MenuBarView(onOpenMonitor: onOpenMonitor, onOpenSettings: onOpenSettings)
                    .environment(store))
            content.sizingOptions = .preferredContentSize
            popover.contentViewController = content
            popover.appearance = NSAppearance(named: Theme.current.frameIsDark ? .darkAqua : .aqua)
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    func closePopover() {
        popover.performClose(nil)
    }

    /// Re-renders the label whenever a figure it shows, or the menu bar settings, change.
    private func updateLabel() {
        withObservationTracking {
            let image = StatusLabel.image(for: store)
            item.button?.image = image
            item.button?.title = ""
            item.button?.setAccessibilityLabel(
                StatusLabel.segments(for: store).map(\.text).joined(separator: ", "))
        } onChange: { [weak self] in
            Task { @MainActor in self?.updateLabel() }
        }
    }
}

/// The monitor window: black hidden-title-bar chrome hosting MainWindowView.
@MainActor
final class MainWindowController {
    private let store: MonitorStore
    private let cleaner: CleanerStore
    private var window: NSWindow?

    init(store: MonitorStore, cleaner: CleanerStore) {
        self.store = store
        self.cleaner = cleaner
    }

    func show() {
        let window = window ?? makeWindow()
        if self.window == nil {
            self.window = window
            applyTheme()
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1240, height: 880),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.title = "Fresh"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        let hosting = NSHostingView(rootView: MainWindowView().environment(store).environment(cleaner))
        hosting.sizingOptions = [.minSize]
        window.contentView = hosting
        window.center()
        window.setFrameAutosaveName("MonitorWindow")
        return window
    }

    /// Window chrome (title bar area, traffic lights) follows the theme's frame.
    private func applyTheme() {
        withObservationTracking {
            window?.backgroundColor = NSColor(Theme.Palette.frame)
            window?.appearance = NSAppearance(named: Theme.current.frameIsDark ? .darkAqua : .aqua)
        } onChange: { [weak self] in
            Task { @MainActor in self?.applyTheme() }
        }
    }
}
