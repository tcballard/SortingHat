import AppKit
import SwiftUI

struct HatMenu: View {
    let store: HatStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Label(store.isProcessing ? "Sorting files…" : store.status, systemImage: store.isWatching ? "graduationcap.fill" : "pause.circle")
        if reviewCount > 0 {
            Text("\(reviewCount) file\(reviewCount == 1 ? "" : "s") need review")
                .foregroundStyle(.secondary)
        }
        Divider()
        Button(store.isWatching ? "Pause Sorting" : "Start Sorting") {
            store.isWatching ? store.pause() : store.start()
        }
        Button("Sort Now") { Task { await store.processNow() } }
            .keyboardShortcut("s", modifiers: [.command, .shift])
            .disabled(store.isProcessing)
        Divider()
        Button("Open Inbox") { store.openInbox() }
        Button("Show Sorting Rules") { showWindow("rules") }
        Button("Open Sorting Hat") { showWindow("dashboard") }
        SettingsLink { Text("Settings…") }
        Divider()
        Button("Quit Sorting Hat") { NSApplication.shared.terminate(nil) }
    }

    private var reviewCount: Int { store.recent.filter { $0.outcome == .needsReview }.count }

    private func showWindow(_ id: String) {
        openWindow(id: id)
        NSApp.activate(ignoringOtherApps: true)
    }
}
