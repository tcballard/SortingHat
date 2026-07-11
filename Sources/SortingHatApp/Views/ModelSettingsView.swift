import SwiftUI
import SortingHatCore

struct ModelSettingsView: View {
    let store: HatStore
    @Environment(\.dismiss) private var dismiss
    @State private var url = "http://127.0.0.1:11434"
    @State private var ollamaModel = ""
    @State private var openAIModel = ""
    @State private var openAIKey = ""
    @State private var provider: ModelProvider = .automatic
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Settings").font(.title2.bold())
            Text("Choose a provider, or let Sorting Hat select the first available option.")
                .foregroundStyle(.secondary)
            Form {
                Picker("Provider", selection: $provider) {
                    Text("Automatic").tag(ModelProvider.automatic)
                    Text("Apple (macOS 27)").tag(ModelProvider.apple)
                    Text("Ollama").tag(ModelProvider.ollama)
                    Text("OpenAI").tag(ModelProvider.openai)
                }
                .pickerStyle(.segmented)
                Divider()
                TextField("Ollama URL", text: $url)
                TextField("Ollama model", text: $ollamaModel, prompt: Text("For example: gemma3:4b"))
                Divider()
                TextField("OpenAI model", text: $openAIModel, prompt: Text("For example: gpt-5.4-nano"))
                SecureField("OpenAI API key", text: $openAIKey)
            }
            Text(providerHelp)
                .font(.caption).foregroundStyle(.secondary)
            if let errorMessage { Text(errorMessage).font(.caption).foregroundStyle(.red) }
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") { save() }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 500)
        .onAppear {
            do {
                let settings = try store.loadModelSettings()
                provider = settings.provider; url = settings.url; ollamaModel = settings.ollamaModel
                openAIModel = settings.openAIModel; openAIKey = settings.openAIKey
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        do { try store.saveModelSettings(provider: provider, url: url, ollamaModel: ollamaModel, openAIModel: openAIModel, openAIKey: openAIKey); dismiss() }
        catch { errorMessage = error.localizedDescription }
    }

    private var providerHelp: String {
        switch provider {
        case .automatic: "Automatic tries Apple first, then Ollama, then OpenAI. Leave a model empty to skip that provider."
        case .apple: "Uses Apple's private on-device model and requires macOS 27 with Apple Intelligence."
        case .ollama: "Uses the configured local Ollama server and never falls through to OpenAI."
        case .openai: "Uses OpenAI directly. The API key is stored in macOS Keychain; selected files may be sent to OpenAI."
        }
    }
}
