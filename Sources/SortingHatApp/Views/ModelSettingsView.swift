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
    @State private var appleModel: AppleModelSelection = .automatic
    @State private var appleUseCase: AppleUseCase = .general
    @State private var appleGuardrails: AppleGuardrails = .default
    @State private var allowApplePCC = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Model Settings").font(.title2.bold())
            Text("Choose a provider, or let Sorting Hat select the first available option.")
                .foregroundStyle(.secondary)
            Form {
                Picker("Provider", selection: $provider) {
                    Text("Automatic").tag(ModelProvider.automatic)
                    Text("Apple (On-Device)").tag(ModelProvider.apple)
                    Text("Ollama").tag(ModelProvider.ollama)
                    Text("OpenAI").tag(ModelProvider.openai)
                }
                .pickerStyle(.segmented)
                Divider()
                Section("Apple Foundation Models") {
                    Picker("Apple model", selection: $appleModel) {
                        Text("Automatic").tag(AppleModelSelection.automatic)
                        Text("On-Device").tag(AppleModelSelection.system)
                        Text("Private Cloud").tag(AppleModelSelection.pcc)
                    }
                    Picker("Use case", selection: $appleUseCase) {
                        Text("General").tag(AppleUseCase.general)
                        Text("Content Tagging").tag(AppleUseCase.contentTagging)
                    }
                    Picker("Guardrails", selection: $appleGuardrails) {
                        Text("Default").tag(AppleGuardrails.default)
                        Text("Permit Content Transformations").tag(AppleGuardrails.permissiveContentTransformations)
                    }
                    Toggle("Allow files to be sent to Apple Private Cloud Compute", isOn: $allowApplePCC)
                    if appleModel == .pcc && !allowApplePCC {
                        Text("Private Cloud Compute cannot be selected until permission is enabled.")
                            .font(.caption).foregroundStyle(.red)
                    } else if allowApplePCC {
                        Text("Cloud permission is enabled. Automatic may retry eligible on-device failures using Apple's Private Cloud Compute service.")
                            .font(.caption).foregroundStyle(.orange)
                    }
                }
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
                appleModel = settings.appleModel; appleUseCase = settings.appleUseCase
                appleGuardrails = settings.appleGuardrails; allowApplePCC = settings.allowApplePCC
            } catch { errorMessage = error.localizedDescription }
        }
    }

    private func save() {
        do {
            try store.saveModelSettings(provider: provider, appleModel: appleModel, appleUseCase: appleUseCase,
                                        appleGuardrails: appleGuardrails, allowApplePCC: allowApplePCC,
                                        url: url, ollamaModel: ollamaModel, openAIModel: openAIModel, openAIKey: openAIKey)
            dismiss()
        }
        catch { errorMessage = error.localizedDescription }
    }

    private var providerHelp: String {
        switch provider {
        case .automatic: "Automatic tries the configured Apple policy first, then Ollama and OpenAI. Apple PCC is never used without the permission above."
        case .apple: "Uses the selected Apple policy. On-device stays local; Private Cloud Compute sends file context to Apple and requires permission."
        case .ollama: "Uses the configured local Ollama server and never falls through to OpenAI."
        case .openai: "Uses OpenAI directly. The API key is stored in macOS Keychain; selected files may be sent to OpenAI."
        }
    }
}
