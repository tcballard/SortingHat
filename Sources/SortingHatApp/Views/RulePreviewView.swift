import SortingHatCore
import SwiftUI

struct RulePreviewRequest: Identifiable {
    let id = UUID()
    let rules: [String]
    let files: [URL]
    let output: URL
}

struct RulePreviewSheet: View {
    let store: HatStore
    let request: RulePreviewRequest
    @Environment(\.dismiss) private var dismiss
    @State private var results: [FilingPreview] = []
    @State private var selection: FilingPreview.ID?
    @State private var isRunning = true
    @State private var errorMessage: String?

    private var selectedResult: FilingPreview? {
        results.first { $0.id == selection } ?? results.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 980, height: 600)
        .tint(SortingHatTheme.amber)
        .task(id: request.id) { await runPreview() }
    }

    private var header: some View {
        HStack(spacing: 12) {
            WizardHatSymbol(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Preview filing outcomes").font(.title2.bold())
                Text("The hat will consider these files without moving, renaming, or tagging them.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !results.isEmpty { outcomeSummary }
        }
        .padding(18)
    }

    @ViewBuilder
    private var content: some View {
        if isRunning {
            VStack(spacing: 12) {
                ProgressView()
                Text("Considering \(request.files.count) representative file\(request.files.count == 1 ? "" : "s")…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Previewing filing outcomes")
        } else if let errorMessage {
            ContentUnavailableView {
                Label("Preview could not run", systemImage: "exclamationmark.triangle")
            } description: {
                Text(errorMessage)
            } actions: {
                Button("Try Again") { Task { await runPreview() } }
            }
        } else {
            VStack(spacing: 0) {
                Table(results, selection: $selection) {
                    TableColumn("Status") { result in
                        Label(result.status.rawValue, systemImage: symbol(for: result.status))
                            .foregroundStyle(color(for: result.status))
                    }
                    .width(min: 105, ideal: 120, max: 135)

                    TableColumn("Original") { result in
                        Text(result.source.lastPathComponent).lineLimit(1).help(result.source.lastPathComponent)
                    }
                    .width(min: 140, ideal: 190)

                    TableColumn("Matched Rule") { result in
                        Text(result.matchedRuleSubject ?? "No safe match")
                            .lineLimit(1)
                            .help(result.matchedRuleSubject ?? result.reason)
                    }
                    .width(min: 120, ideal: 160)

                    TableColumn("Filed As") { result in
                        Text(result.proposedFilename ?? "—")
                            .lineLimit(1)
                            .foregroundStyle(result.proposedFilename == nil ? .secondary : .primary)
                            .help(result.proposedFilename ?? "No filename proposed")
                    }
                    .width(min: 140, ideal: 190)

                    TableColumn("Destination") { result in
                        Text(result.renderedFolder ?? "Inbox · Needs review")
                            .lineLimit(1)
                            .help(result.renderedFolder ?? result.reason)
                    }
                    .width(min: 160, ideal: 230)
                }
                .accessibilityLabel("Rule preview results")

                Divider()

                if let selectedResult {
                    RulePreviewDetail(result: selectedResult)
                        .frame(height: 150, alignment: .top)
                }
            }
        }
    }

    private var footer: some View {
        HStack {
            Label("Preview only — your files and saved rules are unchanged.", systemImage: "eye")
                .font(.callout)
                .foregroundStyle(.secondary)
            Spacer()
            Button("Run Again") { Task { await runPreview() } }
                .disabled(isRunning)
            Button("Close") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(14)
    }

    private var outcomeSummary: some View {
        let ready = results.filter { $0.status == .ready }.count
        let review = results.filter { $0.status == .needsReview }.count
        let blocked = results.filter { $0.status == .invalid }.count
        return HStack(spacing: 10) {
            Label("\(ready) ready", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
            if review > 0 {
                Label("\(review) review", systemImage: "questionmark.circle")
                    .foregroundStyle(SortingHatTheme.amber)
            }
            if blocked > 0 {
                Label("\(blocked) blocked", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }
        }
        .font(.caption.weight(.semibold))
        .monospacedDigit()
        .accessibilityElement(children: .combine)
    }

    private func runPreview() async {
        isRunning = true
        errorMessage = nil
        do {
            let preview = try await store.preview(
                rules: request.rules,
                files: request.files,
                output: request.output
            )
            results = preview
            selection = preview.first?.id
        } catch {
            results = []
            selection = nil
            errorMessage = error.localizedDescription
        }
        isRunning = false
    }

    private func symbol(for status: FilingPreviewStatus) -> String {
        switch status {
        case .ready: "checkmark.circle.fill"
        case .needsReview: "questionmark.circle"
        case .invalid: "xmark.octagon.fill"
        }
    }

    private func color(for status: FilingPreviewStatus) -> Color {
        switch status {
        case .ready: .green
        case .needsReview: SortingHatTheme.amber
        case .invalid: .red
        }
    }
}

private struct RulePreviewDetail: View {
    let result: FilingPreview

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Label(result.source.lastPathComponent, systemImage: "doc")
                    .lineLimit(1)
                    .help(result.source.lastPathComponent)
                flowArrow
                Label(result.matchedRuleSubject ?? "Needs review", systemImage: "text.badge.checkmark")
                    .lineLimit(1)
                flowArrow
                Label(result.proposedFilename ?? "No rename", systemImage: "wand.and.sparkles")
                    .lineLimit(1)
                flowArrow
                Label(result.renderedFolder ?? "Remains in Inbox", systemImage: "folder.fill")
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .font(.headline)

            Text(result.reason)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 14) {
                if !result.destinationValues.isEmpty {
                    LabeledContent("Values") {
                        Text(result.destinationValues.map { "\($0.variable.rawValue)=\($0.value)" }.joined(separator: " · "))
                            .lineLimit(1)
                    }
                }
                if !result.tags.isEmpty {
                    LabeledContent("Tags") { Text(result.tags.joined(separator: ", ")).lineLimit(1) }
                }
                Spacer()
                if let id = result.matchedRuleID {
                    Text(id).font(.caption.monospaced()).foregroundStyle(.tertiary).help("Compiled rule identifier")
                }
            }
            .font(.caption)
        }
        .padding(16)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilitySummary)
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SortingHatTheme.amber)
            .accessibilityHidden(true)
    }

    private var accessibilitySummary: String {
        "\(result.source.lastPathComponent), \(result.status.rawValue), matched rule \(result.matchedRuleSubject ?? "none"), proposed filename \(result.proposedFilename ?? "none"), destination \(result.renderedFolder ?? "Inbox"). \(result.reason)"
    }
}
