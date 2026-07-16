import SwiftUI

struct ReviewQueueView: View {
    let store: HatStore
    @State private var selection: Activity.ID?
    @State private var filedName = ""
    @State private var destination = ""
    @State private var teachingRule = ""
    @State private var errorMessage: String?

    private var items: [Activity] { store.recent.filter { $0.outcome == .needsReview } }
    private var selected: Activity? { items.first { $0.id == selection } ?? items.first }

    var body: some View {
        HSplitView {
            List(items, selection: $selection) { activity in
                VStack(alignment: .leading, spacing: 3) {
                    Label(activity.sourceName, systemImage: activity.outcome.symbol).lineLimit(1)
                    Text(activity.detail).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                }
                .padding(.vertical, 4)
                .tag(activity.id)
            }
            .frame(minWidth: 240, idealWidth: 290)

            if let selected {
                Form {
                    Section("The hat needs your judgement") {
                        LabeledContent("Original", value: selected.sourceName)
                        Text(selected.detail).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Section("Correct the decision") {
                        TextField("Filed name", text: $filedName, prompt: Text(selected.sourceName))
                        TextField("Destination", text: $destination, prompt: Text("Documents/2026"))
                        TextField("Teach the hat (optional)", text: $teachingRule,
                                  prompt: Text("Put bank statements in Finance/Statements/YYYY"), axis: .vertical)
                    }
                    if let errorMessage { Label(errorMessage, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red) }
                    HStack {
                        Button("Open File") { if let url = selected.fileURL { store.open(url) } }
                        Spacer()
                        Button("File Correctly") { resolve(selected) }
                            .buttonStyle(.borderedProminent)
                            .disabled(filedName.isEmpty || destination.isEmpty)
                    }
                }
                .formStyle(.grouped)
                .onAppear { prepare(selected) }
                .onChange(of: selection) { if let activity = self.selected { prepare(activity) } }
            } else {
                ContentUnavailableView("Nothing needs review", systemImage: "checkmark.seal",
                                       description: Text("Uncertain files will appear here instead of being moved."))
            }
        }
    }

    private func prepare(_ activity: Activity) {
        filedName = activity.sourceName
        destination = ""
        teachingRule = ""
        errorMessage = nil
    }

    private func resolve(_ activity: Activity) {
        do { try store.resolve(activity, filedName: filedName, destination: destination, teachingRule: teachingRule); selection = nil }
        catch { errorMessage = error.localizedDescription }
    }
}
