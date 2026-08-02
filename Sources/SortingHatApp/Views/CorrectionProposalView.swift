import SortingHatCore
import SwiftUI
import UniformTypeIdentifiers

struct CorrectionProposalSheet: View {
    let store: HatStore
    let correction: CorrectionContext
    @Environment(\.dismiss) private var dismiss
    @State private var proposal: CorrectionRuleProposal?
    @State private var generatedRule = ""
    @State private var editedRule = ""
    @State private var isGenerating = true
    @State private var errorMessage: String?
    @State private var choosingPreviewFiles = false
    @State private var previewRequest: RulePreviewRequest?
    @State private var finished = false

    private var assessment: RuleProposalAssessment? {
        try? store.assessProposal(editedRule)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 780, height: 510)
        .tint(SortingHatTheme.amber)
        .task { await generate() }
        .fileImporter(
            isPresented: $choosingPreviewFiles,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let files):
                guard !files.isEmpty, files.count <= 8, let assessment else {
                    errorMessage = "Choose between 1 and 8 representative files."
                    return
                }
                previewRequest = RulePreviewRequest(
                    rules: assessment.candidateRules,
                    files: files,
                    output: store.outputRoot
                )
            case .failure(let error):
                errorMessage = error.localizedDescription
            }
        }
        .sheet(item: $previewRequest) { request in
            RulePreviewSheet(store: store, request: request)
        }
        .onDisappear {
            if !finished { store.discardCorrectionProposal(for: correction) }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            WizardHatSymbol(size: 34)
            VStack(alignment: .leading, spacing: 2) {
                Text("Teach the hat—only if you agree").font(.title2.bold())
                Text("Your file is already corrected. No rule changes until you choose Add Rule.")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(18)
    }

    @ViewBuilder
    private var content: some View {
        if isGenerating {
            VStack(spacing: 12) {
                ProgressView()
                Text("Looking for a reusable pattern in this correction…")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Building a correction rule proposal")
        } else if proposal == nil {
            ContentUnavailableView {
                Label("No rule was proposed", systemImage: "text.badge.xmark")
            } description: {
                Text(errorMessage ?? "The correction is complete and your existing rules remain unchanged.")
            } actions: {
                Button("Try Again") { Task { await generate() } }
            }
        } else {
            VStack(alignment: .leading, spacing: 16) {
                correctionTrail

                if let proposal {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Why this was inferred").font(.headline)
                        Text(proposal.reason)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                VStack(alignment: .leading, spacing: 7) {
                    Text("Proposed rule").font(.headline)
                    TextField("One specific destination rule", text: $editedRule, axis: .vertical)
                        .lineLimit(2...4)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityHint("Edit the proposed rule before previewing or adding it")
                    Text("The rule will be inserted before your catch-all. All other rules keep their current order and wording.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                proposalMessages
                Spacer(minLength: 0)
            }
            .padding(20)
        }
    }

    private var correctionTrail: some View {
        HStack(spacing: 9) {
            Label(correction.originalName, systemImage: "doc")
                .lineLimit(1).help(correction.originalName)
            flowArrow
            Label(correction.correctedName, systemImage: "wand.and.sparkles")
                .lineLimit(1).help(correction.correctedName)
            flowArrow
            Label(correction.destination, systemImage: "folder.fill")
                .lineLimit(1).help(correction.destination)
            Spacer(minLength: 0)
            Label("Filed", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        }
        .font(.headline)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Corrected \(correction.originalName) to \(correction.correctedName) in \(correction.destination)")
    }

    @ViewBuilder
    private var proposalMessages: some View {
        if let issue = assessment?.issues.first {
            Label(issue.message, systemImage: "xmark.octagon.fill")
                .foregroundStyle(.red)
                .accessibilityLabel("Rule cannot be added. \(issue.message)")
        } else if let overlap = assessment?.overlaps.first {
            Label(overlap.message, systemImage: "arrow.triangle.branch")
                .foregroundStyle(SortingHatTheme.amber)
                .accessibilityLabel("Possible rule overlap. \(overlap.message)")
        } else {
            Label("No duplicate, ordering, or catch-all conflict detected.", systemImage: "checkmark.seal")
                .foregroundStyle(.secondary)
        }
        if let errorMessage {
            Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        }
    }

    private var footer: some View {
        HStack {
            Button("Discard Proposal") { discard() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            if proposal != nil {
                Menu("Preview") {
                    Button("Preview Corrected File") { preview(files: [correction.fileURL]) }
                    Button("Choose Other Files…") { choosingPreviewFiles = true }
                }
                .disabled(assessment?.canAdd != true)
                Button("Add Rule") { addRule() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(assessment?.canAdd != true)
            }
        }
        .padding(14)
    }

    private var flowArrow: some View {
        Image(systemName: "arrow.right")
            .font(.caption.weight(.semibold))
            .foregroundStyle(SortingHatTheme.amber)
            .accessibilityHidden(true)
    }

    private func generate() async {
        isGenerating = true
        errorMessage = nil
        do {
            let result = try await CorrectionProposalGenerator().generate(for: correction)
            proposal = result
            generatedRule = result.ruleText
            editedRule = result.ruleText
        } catch {
            proposal = nil
            errorMessage = error.localizedDescription
        }
        isGenerating = false
    }

    private func preview(files: [URL]) {
        guard let assessment else { return }
        previewRequest = RulePreviewRequest(
            rules: assessment.candidateRules,
            files: files,
            output: store.outputRoot
        )
    }

    private func addRule() {
        do {
            try store.addCorrectionProposal(editedRule, generatedRule: generatedRule, for: correction)
            finished = true
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discard() {
        store.discardCorrectionProposal(for: correction)
        finished = true
        dismiss()
    }
}
