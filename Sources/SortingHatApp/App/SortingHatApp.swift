import SwiftUI

@main
struct SortingHatMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HatStore()

    var body: some Scene {
        Window("Sorting Hat", id: "dashboard") {
            DashboardView(store: store)
                .frame(minWidth: 760, minHeight: 460)
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

        MenuBarExtra {
            HatMenu(store: store)
        } label: {
            Label("Sorting Hat", systemImage: store.isWatching ? "graduationcap.fill" : "graduationcap")
                .accessibilityLabel(store.isWatching ? "Sorting Hat, monitoring Inbox" : "Sorting Hat, paused")
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
}
