import AppKit
import SwiftUI

struct HatMenu: View {
    let store: HatStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(store.status).foregroundStyle(.secondary)
        Divider()
        Button(store.isWatching ? "Pause Sorting" : "Start Sorting") {
            store.isWatching ? store.pause() : store.start()
        }
        Button("Sort Now") { Task { await store.processNow() } }
        Divider()
        Button("Open Inbox") { store.openInbox() }
        Button("Manage Rules") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
        Button("Open Dashboard") { openWindow(id: "dashboard"); NSApp.activate(ignoringOtherApps: true) }
        Divider()
        Button("Quit Sorting Hat") { NSApplication.shared.terminate(nil) }
    }
}
