import SwiftUI

struct DashboardView: View {
    let store: HatStore
    @Environment(\.openWindow) private var openWindow
    @State private var selection: Activity.ID?

    private var selectedActivity: Activity? {
        store.recent.first { $0.id == selection }
    }

    var body: some View {
        VStack(spacing: 0) {
            statusStrip
            Divider()
            activityContent
        }
        .navigationTitle("Sorting Hat")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Show Inbox in Finder", systemImage: "folder") { store.openInbox() }
                    .help("Show Inbox in Finder (⇧⌘I)")
                Button("Rules", systemImage: "text.badge.checkmark") { openWindow(id: "rules") }
                    .help("Show Sorting Rules (⌥⌘R)")
            }
            ToolbarItemGroup(placement: .primaryAction) {
                Button(store.isWatching ? "Pause" : "Resume", systemImage: store.isWatching ? "pause.fill" : "play.fill") {
                    store.isWatching ? store.pause() : store.start()
                }
                Button("Sort Now", systemImage: "arrow.triangle.2.circlepath") {
                    Task { await store.processNow() }
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(store.isProcessing)
                .help("Sort Now (⇧⌘S)")
            }
        }
    }

    private var statusStrip: some View {
        HStack(spacing: 16) {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(store.isProcessing ? "Sorting files" : store.status)
                        .fontWeight(.medium)
                    Text(store.isWatching ? "Inbox monitoring is active" : "Inbox monitoring is paused")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: statusSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(statusColor)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(store.isProcessing ? "Sorting files" : store.status)

            Spacer()

            if store.isProcessing {
                ProgressView()
                    .controlSize(.small)
                    .accessibilityLabel("Sorting files")
            }

            if reviewCount > 0 {
                Label("\(reviewCount) to review", systemImage: "questionmark.circle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(reviewCount) files need review")
            }

            Text("\(store.recent.count) recent")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var activityContent: some View {
        if store.recent.isEmpty {
            ContentUnavailableView {
                Label("Inbox is ready", systemImage: "tray.and.arrow.down")
            } description: {
                Text("Add files to the Inbox. Sorting Hat will rename and file them using your rules.")
            } actions: {
                HStack {
                    Button("Show Inbox in Finder") { store.openInbox() }
                    Button("Review Rules") { openWindow(id: "rules") }
                }
            }
            .frame(maxWidth: 520, maxHeight: .infinity)
            .frame(maxWidth: .infinity)
        } else {
            VSplitView {
                Table(store.recent, selection: $selection) {
                    TableColumn("Status") { activity in
                        Label(activity.outcome.rawValue, systemImage: activity.outcome.symbol)
                            .foregroundStyle(color(for: activity.outcome))
                            .labelStyle(.titleAndIcon)
                    }
                    .width(min: 96, ideal: 112, max: 132)

                    TableColumn("Original") { activity in
                        Text(activity.sourceName).lineLimit(1).help(activity.sourceName)
                    }
                    .width(min: 130, ideal: 190)

                    TableColumn("Filed As") { activity in
                        Text(activity.filedName ?? "—")
                            .lineLimit(1)
                            .foregroundStyle(activity.filedName == nil ? .secondary : .primary)
                            .help(activity.filedName ?? "Not filed")
                    }
                    .width(min: 130, ideal: 190)

                    TableColumn("Destination") { activity in
                        Text(activity.destination ?? "Inbox")
                            .lineLimit(1)
                            .help(activity.destination ?? "Remains in Inbox")
                    }
                    .width(min: 150, ideal: 230)

                    TableColumn("When") { activity in
                        Text(activity.date, style: .time).monospacedDigit()
                    }
                    .width(72)
                }
                .accessibilityLabel("Recent filing activity")

                ActivityDetailView(activity: selectedActivity ?? store.recent.first!, store: store)
                    .frame(minHeight: 118, idealHeight: 142, maxHeight: 190)
            }
        }
    }

    private var reviewCount: Int { store.recent.filter { $0.outcome == .needsReview }.count }

    private var statusSymbol: String {
        if store.isProcessing { return "arrow.triangle.2.circlepath" }
        return store.isWatching ? "graduationcap.fill" : "pause.circle.fill"
    }

    private var statusColor: Color {
        store.isProcessing ? .accentColor : (store.isWatching ? .accentColor : .secondary)
    }

    private func color(for outcome: Activity.Outcome) -> Color {
        switch outcome {
        case .filed: .green
        case .needsReview: .orange
        case .failed: .red
        }
    }
}

private struct ActivityDetailView: View {
    let activity: Activity
    let store: HatStore

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(activity.sourceName).fontWeight(.medium).lineLimit(1)
                Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                Text(activity.filedName ?? "Kept in Inbox")
                    .fontWeight(.medium)
                    .lineLimit(1)
                if let destination = activity.destination {
                    Image(systemName: "arrow.right").foregroundStyle(.tertiary)
                    Label(destination, systemImage: "folder")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .accessibilityElement(children: .combine)

            Text(activity.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

            HStack(spacing: 6) {
                if !activity.tags.isEmpty {
                    Text("Tags").font(.caption).foregroundStyle(.secondary)
                    ForEach(activity.tags, id: \.self) { tag in
                        Text(tag)
                            .font(.caption)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary, in: Capsule())
                    }
                }
                Spacer()
                if let fileURL = activity.fileURL {
                    Button("Show in Finder", systemImage: "magnifyingglass") { store.reveal(fileURL) }
                        .controlSize(.small)
                } else {
                    Button("Show Inbox in Finder", systemImage: "folder") { store.openInbox() }
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.background)
    }
}
