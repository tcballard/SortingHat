import SwiftUI

struct DashboardView: View {
    let store: HatStore
    @Environment(\.openWindow) private var openWindow
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
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
        .background(SortingHatTheme.canvas(for: colorScheme))
        .tint(SortingHatTheme.amber)
        .navigationTitle("Sorting Hat")
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button("Show in Finder", systemImage: "folder") { store.openInbox() }
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
                        .fontWeight(.semibold)
                        .foregroundStyle(.white)
                    Text(store.isWatching ? "Listening for files to rename and file" : "Inbox monitoring is paused")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.68))
                }
            } icon: {
                Image(systemName: statusSymbol)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(SortingHatTheme.amberBright)
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
                    .foregroundStyle(SortingHatTheme.amberBright)
                    .accessibilityLabel("\(reviewCount) files need review")
            }

            Text("\(store.recent.count) recent")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.68))
                .monospacedDigit()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(
            SortingHatTheme.statusSurface(
                for: colorScheme,
                increasedContrast: colorSchemeContrast == .increased
            )
        )
    }

    @ViewBuilder
    private var activityContent: some View {
        if store.recent.isEmpty {
            EmptySortingView(
                showInbox: store.openInbox,
                reviewRules: { openWindow(id: "rules") }
            )
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

                ActivityDetailView(
                    activity: selectedActivity ?? store.recent.first!,
                    store: store,
                    differentiateWithoutColor: differentiateWithoutColor,
                    reduceMotion: reduceMotion
                )
                    .frame(minHeight: 118, idealHeight: 142, maxHeight: 190)
            }
        }
    }

    private var reviewCount: Int { store.recent.filter { $0.outcome == .needsReview }.count }

    private var statusSymbol: String {
        if store.isProcessing { return "arrow.triangle.2.circlepath" }
        return store.isWatching ? "graduationcap.fill" : "pause.circle.fill"
    }

    private func color(for outcome: Activity.Outcome) -> Color {
        switch outcome {
        case .filed: .green
        case .needsReview: .orange
        case .failed: .red
        }
    }
}

private struct EmptySortingView: View {
    let showInbox: () -> Void
    let reviewRules: () -> Void

    var body: some View {
        VStack(spacing: 20) {
            SortingTrailGraphic()

            VStack(spacing: 6) {
                Text("The hat is listening")
                    .font(.title2.weight(.semibold))
                Text("Drop files into the Inbox. They’ll be renamed and filed by your rules.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 430)
            }

            HStack {
                Button("Show Inbox") { showInbox() }
                    .buttonStyle(.borderedProminent)
                Button("Review Rules") { reviewRules() }
            }
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SortingTrailGraphic: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .foregroundStyle(.secondary)
            trail
            Image(systemName: "sparkles")
                .foregroundStyle(SortingHatTheme.amberBright)
            trail
            Image(systemName: "folder.fill")
                .foregroundStyle(SortingHatTheme.amber)
        }
        .font(.system(size: 28, weight: .medium))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Files are renamed and routed into destination folders")
    }

    private var trail: some View {
        Capsule()
            .fill(SortingHatTheme.amber.opacity(0.55))
            .frame(width: 42, height: 2)
            .overlay(alignment: .trailing) {
                Circle().fill(SortingHatTheme.amberBright).frame(width: 5, height: 5)
            }
    }
}

private struct ActivityDetailView: View {
    let activity: Activity
    let store: HatStore
    let differentiateWithoutColor: Bool
    let reduceMotion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            SortingTrail(
                activity: activity,
                differentiateWithoutColor: differentiateWithoutColor,
                reduceMotion: reduceMotion
            )
            .id(activity.id)

            Text(activity.detail)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
                .help(activity.detail)

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
                    Button("Show in Finder", systemImage: "folder") { store.openInbox() }
                        .controlSize(.small)
                }
            }
        }
        .padding(14)
        .background(.background.opacity(0.94))
    }
}

private struct SortingTrail: View {
    let activity: Activity
    let differentiateWithoutColor: Bool
    let reduceMotion: Bool
    @State private var revealed = false

    var body: some View {
        HStack(spacing: 9) {
            trailNode(activity.sourceName, symbol: "doc", emphasis: false)
            connector
            trailNode(activity.filedName ?? "Kept in Inbox", symbol: "wand.and.sparkles", emphasis: true)
            connector
            trailNode(activity.destination ?? "Needs your judgement", symbol: destinationSymbol, emphasis: activity.outcome == .filed)
            Spacer(minLength: 0)
            outcomeLabel
                .font(.caption.weight(.medium))
                .foregroundStyle(outcomeColor)
        }
        .opacity(revealed ? 1 : 0.35)
        .offset(x: revealed ? 0 : -5)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.22), value: revealed)
        .onAppear { revealed = true }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(activity.sourceName), renamed to \(activity.filedName ?? "unchanged"), destination \(activity.destination ?? "Inbox"), \(activity.outcome.rawValue)")
    }

    private func trailNode(_ title: String, symbol: String, emphasis: Bool) -> some View {
        Label {
            Text(title).lineLimit(1).help(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(emphasis ? SortingHatTheme.amber : .secondary)
        }
        .fontWeight(emphasis ? .semibold : .regular)
        .frame(maxWidth: 230, alignment: .leading)
    }

    private var connector: some View {
        HStack(spacing: 2) {
            Rectangle().fill(SortingHatTheme.amber.opacity(0.5)).frame(width: 18, height: 1)
            Image(systemName: "chevron.right")
                .font(.system(size: 8, weight: .bold))
                .foregroundStyle(SortingHatTheme.amber)
        }
        .accessibilityHidden(true)
    }

    private var destinationSymbol: String {
        activity.outcome == .filed ? "folder.fill" : "questionmark.folder"
    }

    @ViewBuilder
    private var outcomeLabel: some View {
        if differentiateWithoutColor {
            Label(activity.outcome.rawValue, systemImage: activity.outcome.symbol)
                .labelStyle(.titleAndIcon)
        } else {
            Label(activity.outcome.rawValue, systemImage: activity.outcome.symbol)
                .labelStyle(.iconOnly)
                .help(activity.outcome.rawValue)
        }
    }

    private var outcomeColor: Color {
        switch activity.outcome {
        case .filed: .green
        case .needsReview: .orange
        case .failed: .red
        }
    }
}
