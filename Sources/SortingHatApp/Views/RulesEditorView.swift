import SwiftUI

struct RulesEditorView: View {
    let store: HatStore
    @Environment(\.dismiss) private var dismiss
    @State private var rules: [String] = []
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Sorting Rules").font(.title2.bold())
                Text("Write each rule the way you would explain it to a colleague.")
                    .foregroundStyle(.secondary)
            }

            List {
                ForEach(rules.indices, id: \.self) { index in
                    HStack {
                        TextField("For example: Put receipts in Finance", text: $rules[index])
                        Button("Remove", systemImage: "minus.circle") { rules.remove(at: index) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .help("Remove rule")
                    }
                }
            }
            .frame(minHeight: 220)

            Button("Add Rule", systemImage: "plus") { rules.append("") }

            if let errorMessage {
                Text(errorMessage).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 560, height: 390)
        .onAppear(perform: load)
    }

    private func load() {
        do {
            rules = try store.loadRules()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try store.saveRules(rules)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
