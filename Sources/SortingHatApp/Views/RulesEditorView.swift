import SwiftUI

struct RulesEditorView: View {
    let store: HatStore
    @State private var rules: [RuleDraft] = []
    @State private var errorMessage: String?
    @State private var hasChanges = false
    @State private var showingBuilder = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Image(systemName: "sparkles")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(SortingHatTheme.amber)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text("The hat’s judgement").font(.title2.bold())
                    Text("Rules work together. Put specific destinations before the catch-all rule.")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text("\(rules.count) rules")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                Button("Describe a Plan…", systemImage: "wand.and.sparkles") { showingBuilder = true }
            }
            .padding(18)

            Divider()

            if rules.isEmpty {
                ContentUnavailableView {
                    Label("No sorting rules", systemImage: "text.badge.plus")
                } description: {
                    Text("Add at least one rule to describe how files should be renamed and filed.")
                } actions: {
                    Button("Add Rule") { addRule() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        RuleEditorRow(
                            index: index,
                            rule: binding(for: rule.id),
                            canMoveUp: index > 0,
                            canMoveDown: index < rules.count - 1,
                            moveUp: { moveRule(from: index, to: index - 1) },
                            moveDown: { moveRule(from: index, to: index + 1) },
                            remove: { removeRule(rule.id) }
                        )
                    }
                }
                .listStyle(.inset)
            }

            Divider()

            VStack(spacing: 10) {
                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Error: \(errorMessage)")
                }

                HStack {
                    Button("Add Rule", systemImage: "plus") { addRule() }
                    Spacer()
                    Button("Revert") { load() }
                        .disabled(!hasChanges)
                    Button("Save Rules") { save() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges)
                }
            }
            .padding(14)
        }
        .onAppear(perform: load)
        .sheet(isPresented: $showingBuilder) {
            RuleBuilderSheet { plan in
                rules = plan.compiledRules.map(RuleDraft.init(text:))
                hasChanges = true
                showingBuilder = false
            }
        }
    }

    private func binding(for id: RuleDraft.ID) -> Binding<String> {
        Binding(
            get: { rules.first(where: { $0.id == id })?.text ?? "" },
            set: { value in
                guard let index = rules.firstIndex(where: { $0.id == id }) else { return }
                rules[index].text = value
                hasChanges = true
                errorMessage = nil
            }
        )
    }

    private func addRule() {
        rules.append(RuleDraft(text: ""))
        hasChanges = true
    }

    private func removeRule(_ id: RuleDraft.ID) {
        rules.removeAll { $0.id == id }
        hasChanges = true
    }

    private func moveRule(from source: Int, to destination: Int) {
        let rule = rules.remove(at: source)
        rules.insert(rule, at: destination)
        hasChanges = true
    }

    private func load() {
        do {
            rules = try store.loadRules().map(RuleDraft.init(text:))
            errorMessage = nil
            hasChanges = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try store.saveRules(rules.map(\.text))
            hasChanges = false
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

private struct RuleDraft: Identifiable {
    let id = UUID()
    var text: String
}

private struct RuleEditorRow: View {
    let index: Int
    @Binding var rule: String
    let canMoveUp: Bool
    let canMoveDown: Bool
    let moveUp: () -> Void
    let moveDown: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(SortingHatTheme.amber)
                .fontWeight(.semibold)
                .frame(width: 22, alignment: .trailing)
                .padding(.top, 5)

            TextField("Describe how matching files should be renamed and filed", text: $rule, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(2...5)
                .accessibilityLabel("Rule \(index + 1)")

            if let destinationPreview {
                Label(destinationPreview, systemImage: "folder")
                    .font(.caption)
                    .foregroundStyle(SortingHatTheme.amber)
                    .frame(maxWidth: 150, alignment: .leading)
                    .lineLimit(1)
                    .help(destinationPreview)
            }

            HStack(spacing: 2) {
                Button("Move Up", systemImage: "chevron.up", action: moveUp)
                    .disabled(!canMoveUp)
                Button("Move Down", systemImage: "chevron.down", action: moveDown)
                    .disabled(!canMoveDown)
                Button("Remove", systemImage: "trash", role: .destructive, action: remove)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
        }
        .padding(.vertical, 7)
    }

    private var destinationPreview: String? {
        let text = rule
        guard let range = text.range(of: " in ", options: [.caseInsensitive]) else { return nil }
        let tail = text[range.upperBound...]
        let destination = tail.split(separator: ",", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return destination?.isEmpty == false ? destination : nil
    }
}

private struct RuleBuilderSheet: View {
    let apply: (RulePlan) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var intent = ""
    @State private var plan: RulePlan?
    @State private var isGenerating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack { WizardHatSymbol(size: 32); Text("Describe a filing plan").font(.title2.bold()); Spacer() }
            Text("The hat will propose destinations and compile them into editable rules. Existing rules change only when you apply the plan.")
                .foregroundStyle(.secondary)
            TextEditor(text: $intent)
                .frame(height: 110)
                .padding(8)
                .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 8))
            if let plan {
                Table(plan.routes) {
                    TableColumn("Files", value: \.fileKinds)
                    TableColumn("Destination", value: \.folderTemplate)
                    TableColumn("Organisation", value: \.organisation)
                }
                .frame(minHeight: 170)
                Label(plan.fallback, systemImage: "questionmark.folder").foregroundStyle(.secondary)
            }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("The plan could not be built. \(errorMessage)")
            }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                if isGenerating { ProgressView().controlSize(.small) }
                Button(plan == nil ? "Build Plan" : "Rebuild") { generate() }
                    .disabled(intent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isGenerating)
                Button("Use These Rules") { if let plan { apply(plan) } }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(plan == nil)
            }
        }
        .padding(22)
        .frame(width: 680, height: plan == nil ? 330 : 520)
    }

    private func generate() {
        isGenerating = true; errorMessage = nil
        let request = intent
        Task {
            do { plan = try await Task.detached { try RulePlanGenerator().generate(from: request) }.value }
            catch { errorMessage = error.localizedDescription }
            isGenerating = false
        }
    }
}
