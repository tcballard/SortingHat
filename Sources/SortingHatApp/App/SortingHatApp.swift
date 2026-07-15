import SwiftUI

@main
struct SortingHatMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HatStore()

    var body: some Scene {
        Window("Sorting Hat", id: "dashboard") {
            DashboardView(store: store)
                .frame(minWidth: 760, minHeight: 460)
                .background(AppActionBridge(appDelegate: appDelegate, store: store))
        }
        .defaultSize(width: 980, height: 620)

        Window("Sorting Rules", id: "rules") {
            RulesEditorView(store: store)
                .frame(minWidth: 620, minHeight: 420)
        }
        .defaultSize(width: 720, height: 540)

        Settings {
            ModelSettingsView(store: store)
        }

        .commands { SortingHatCommands(store: store) }
    }
}

private struct SortingHatCommands: Commands {
    let store: HatStore
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Show Inbox in Finder") { store.openInbox() }
                .keyboardShortcut("i", modifiers: [.command, .shift])
            Button("Show Sorting Rules") { openWindow(id: "rules") }
                .keyboardShortcut("r", modifiers: [.command, .option])
            Divider()
            Button("Sort Now") { Task { await store.processNow() } }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.isProcessing)
            Button(store.isWatching ? "Pause Monitoring" : "Resume Monitoring") {
                store.isWatching ? store.pause() : store.start()
            }
        }
    }
}

private struct AppActionBridge: View {
    let appDelegate: AppDelegate
    let store: HatStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                appDelegate.configure(store: store, openWindow: openWindow)
            }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private weak var store: HatStore?
    private var openWindow: OpenWindowAction?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
        installStatusItem()
    }

    func configure(store: HatStore, openWindow: OpenWindowAction) {
        self.store = store
        self.openWindow = openWindow
        updateStatusItem()
    }

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = item.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusItem()
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let isWatching = store?.isWatching ?? true
        button.image = wizardHatImage()
        button.alphaValue = isWatching ? 1 : 0.58
        button.toolTip = isWatching ? "Sorting Hat — monitoring Inbox" : "Sorting Hat — paused"
        button.setAccessibilityLabel(isWatching ? "Sorting Hat, monitoring Inbox" : "Sorting Hat, paused")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        updateStatusItem()
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(relativeTo: sender)
        } else {
            showWindow("dashboard")
        }
    }

    private func showStatusMenu(relativeTo button: NSStatusBarButton) {
        let menu = NSMenu()
        let status = NSMenuItem(title: store?.isProcessing == true ? "Sorting files…" : (store?.status ?? "Sorting Hat"), action: nil, keyEquivalent: "")
        status.image = wizardHatImage()
        menu.addItem(status)

        let reviewCount = store?.recent.filter { $0.outcome == .needsReview }.count ?? 0
        if reviewCount > 0 {
            menu.addItem(NSMenuItem(title: "\(reviewCount) file\(reviewCount == 1 ? "" : "s") need review", action: nil, keyEquivalent: ""))
        }

        menu.addItem(.separator())
        menu.addItem(item(store?.isWatching == false ? "Start Sorting" : "Pause Sorting", action: #selector(toggleMonitoring)))
        let sortNow = item("Sort Now", action: #selector(sortNow), key: "s", modifiers: [.command, .shift])
        sortNow.isEnabled = store?.isProcessing != true
        menu.addItem(sortNow)
        menu.addItem(.separator())
        menu.addItem(item("Open Inbox", action: #selector(openInboxWindow)))
        menu.addItem(item("Show Sorting Rules", action: #selector(openRulesWindow)))
        menu.addItem(item("Show Inbox in Finder", action: #selector(showInboxInFinder)))
        menu.addItem(item("Settings…", action: #selector(showSettings), key: ",", modifiers: [.command]))
        menu.addItem(.separator())
        menu.addItem(item("Quit Sorting Hat", action: #selector(quit)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    private func item(
        _ title: String,
        action: Selector,
        key: String = "",
        modifiers: NSEvent.ModifierFlags = []
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        item.keyEquivalentModifierMask = modifiers
        return item
    }

    private func wizardHatImage() -> NSImage? {
        let renderer = ImageRenderer(content: WizardHatSymbol(size: 18))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.size = NSSize(width: 18, height: 16)
        image.isTemplate = true
        image.accessibilityDescription = "Sorting Hat"
        return image
    }

    private func showWindow(_ id: String) {
        openWindow?(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func toggleMonitoring() {
        guard let store else { return }
        store.isWatching ? store.pause() : store.start()
        updateStatusItem()
    }

    @objc private func sortNow() {
        guard let store else { return }
        Task { await store.processNow() }
    }

    @objc private func openInboxWindow() { showWindow("dashboard") }
    @objc private func openRulesWindow() { showWindow("rules") }
    @objc private func showInboxInFinder() { store?.openInbox() }
    @objc private func showSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc private func quit() { NSApp.terminate(nil) }
}
