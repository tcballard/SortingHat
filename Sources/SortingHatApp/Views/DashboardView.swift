import SwiftUI

struct DashboardView: View {
    let store: HatStore
    @State private var isEditingRules = false
    @State private var isEditingModel = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(systemName: store.isWatching ? "graduationcap.fill" : "graduationcap")
                    .font(.system(size: 38)).foregroundStyle(store.isWatching ? .purple : .secondary)
                VStack(alignment: .leading) {
                    Text("Sorting Hat").font(.title.bold())
                    Text(store.status).foregroundStyle(.secondary)
                }
                Spacer()
                Button(store.isWatching ? "Pause" : "Start") { store.isWatching ? store.pause() : store.start() }
                    .controlSize(.large)
                Button("Sort Now") { Task { await store.processNow() } }.controlSize(.large).buttonStyle(.borderedProminent)
            }

            HStack {
                Button("Open Inbox", systemImage: "folder") { store.openInbox() }
                Button("Edit Rules", systemImage: "slider.horizontal.3") { isEditingRules = true }
                Button("Model Settings", systemImage: "cpu") { isEditingModel = true }
                Button(store.quickActionInstalled ? "Reinstall Quick Action" : "Install Quick Action", systemImage: "cursorarrow.click") {
                    store.installQuickAction()
                }
                Spacer()
                Button(store.launchAtLogin ? "Disable Launch at Login" : "Launch at Login") {
                    store.setLaunchAtLogin(!store.launchAtLogin)
                }
            }

            Divider()
            Text("Recent Activity").font(.headline)
            if store.recent.isEmpty {
                ContentUnavailableView("Nothing sorted yet", systemImage: "tray", description: Text("Drop a file into the Inbox and the Hat will take it from there."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(store.recent) { item in
                    HStack(alignment: .top) {
                        Image(systemName: item.succeeded ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                            .foregroundStyle(item.succeeded ? .green : .orange)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name).fontWeight(.medium)
                            Text(item.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                        }
                    }.padding(.vertical, 3)
                }
            }
        }
        .padding(24)
        .sheet(isPresented: $isEditingRules) {
            RulesEditorView(store: store)
        }
        .sheet(isPresented: $isEditingModel) {
            ModelSettingsView(store: store)
        }
    }
}
