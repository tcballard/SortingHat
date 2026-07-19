import SwiftUI
import UniformTypeIdentifiers

struct SetupView: View {
    let store: HatStore
    @Environment(\.colorScheme) private var colorScheme
    @State private var intent = "Put receipts into folders by year and merchant. Keep documents and PDFs together by project. Put screenshots into monthly folders. Rename everything clearly."
    @State private var plan: RulePlan?
    @State private var inbox: URL
    @State private var output: URL
    @State private var isGenerating = false
    @State private var errorMessage: String?
    @State private var choosingInbox = false
    @State private var choosingOutput = false

    init(store: HatStore) {
        self.store = store
        _inbox = State(initialValue: store.inbox)
        _output = State(initialValue: store.outputRoot)
    }

    var body: some View {
        VStack(spacing: 0) {
            setupHeader
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    locations
                    Divider()
                    intention
                    if let plan { proposal(plan) }
                }
                .frame(maxWidth: 720, alignment: .leading)
                .padding(28)
                .frame(maxWidth: .infinity)
            }
            Divider()
            footer
        }
        .background(SortingHatTheme.canvas(for: colorScheme))
        .tint(SortingHatTheme.amber)
        .fileImporter(isPresented: $choosingInbox, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { inbox = url }
        }
        .fileImporter(isPresented: $choosingOutput, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { output = url }
        }
    }

    private var setupHeader: some View {
        HStack(spacing: 14) {
            WizardHatSymbol(size: 38)
            VStack(alignment: .leading, spacing: 2) {
                Text("Teach the hat").font(.title2.bold())
                Text("Describe the filing system you want. Nothing moves until you approve it.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text(plan == nil ? "SETUP" : "REVIEW")
                .font(.caption.weight(.semibold)).tracking(1.2)
                .foregroundStyle(SortingHatTheme.amber)
        }
        .padding(20)
    }

    private var locations: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose locations").font(.headline)
            locationRow("Inbox", url: inbox, action: { choosingInbox = true })
            locationRow("Filed output", url: output, action: { choosingOutput = true })
            Text("The Inbox is intake-only. Destination folders are created under the filed output location.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func locationRow(_ title: String, url: URL, action: @escaping () -> Void) -> some View {
        HStack {
            Label(title, systemImage: title == "Inbox" ? "tray.and.arrow.down" : "folder")
                .frame(width: 120, alignment: .leading)
            Text(url.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
            Spacer()
            Button("Choose…", action: action)
        }
    }

    private var intention: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How should files be organised?").font(.headline)
            TextEditor(text: $intent)
                .font(.body)
                .frame(height: 110)
                .padding(8)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 8))
                .accessibilityLabel("Filing preferences")
            HStack {
                Text("Use ordinary language. Include destinations and how dates, projects, or clients should be grouped.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Build Rules", systemImage: "wand.and.sparkles") { generate() }
                    .buttonStyle(.borderedProminent)
                    .disabled(isGenerating || intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func proposal(_ plan: RulePlan) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Proposed filing plan").font(.headline)
                Spacer()
                Text("\(plan.routes.count) destinations").font(.caption).foregroundStyle(.secondary)
            }
            Text(plan.summary).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 18, verticalSpacing: 10) {
                GridRow { Text("FILES"); Text("DESTINATION"); Text("ORGANISATION") }
                    .font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                ForEach(plan.routes) { route in
                    GridRow {
                        Text(route.fileKinds).lineLimit(2)
                        Label(route.folderTemplate, systemImage: "folder.fill").foregroundStyle(SortingHatTheme.amber)
                        Text(route.organisation).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.22), in: RoundedRectangle(cornerRadius: 8))
            Label(plan.fallback, systemImage: "questionmark.folder")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            if isGenerating { ProgressView().controlSize(.small); Text("Considering your filing system…").foregroundStyle(.secondary) }
            if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(2) }
            Spacer()
            Button("Start Sorting") { finish() }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(plan == nil || isGenerating)
        }
        .padding(16)
    }

    private func generate() {
        isGenerating = true
        errorMessage = nil
        let request = intent
        Task {
            do {
                let generated = try await RulePlanGenerator().generate(from: request)
                plan = generated
            } catch { errorMessage = error.localizedDescription }
            isGenerating = false
        }
    }

    private func finish() {
        guard let plan else { return }
        do {
            try store.saveLocations(inbox: inbox, output: output)
            try store.completeSetup(with: plan)
        } catch { errorMessage = error.localizedDescription }
    }
}
