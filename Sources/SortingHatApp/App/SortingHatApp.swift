import SwiftUI

@main
struct SortingHatMenuApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = HatStore()

    var body: some Scene {
        WindowGroup("Sorting Hat", id: "dashboard") {
            DashboardView(store: store)
                .frame(minWidth: 560, minHeight: 420)
        }
        .defaultSize(width: 680, height: 520)

        MenuBarExtra {
            HatMenu(store: store)
        } label: {
            Label("Sorting Hat", systemImage: store.isWatching ? "graduationcap.fill" : "graduationcap")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
}
