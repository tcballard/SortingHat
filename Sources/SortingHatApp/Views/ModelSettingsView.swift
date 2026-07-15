import SortingHatCore
import SwiftUI

struct ModelSettingsView: View {
    let store: HatStore
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
    @State private var savedMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                providerPane
                    .tabItem { Label("Provider", systemImage: "point.3.connected.trianglepath.dotted") }
                applePane
                    .tabItem { Label("Apple", systemImage: "cpu") }
                localPane
                    .tabItem { Label("Ollama", systemImage: "desktopcomputer") }
                cloudPane
                    .tabItem { Label("OpenAI", systemImage: "cloud") }
            }
            .padding(16)

            Divider()

            HStack {
                Group {
                    if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    } else if let savedMessage {
                        Label(savedMessage, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
                .font(.caption)
                .lineLimit(2)

                Spacer()
                Button("Save Settings") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(14)
        }
        .frame(width: 600, height: 450)
        .onAppear(perform: load)
        .onChange(of: provider) { savedMessage = nil }
        .onChange(of: appleModel) { savedMessage = nil }
        .onChange(of: allowApplePCC) { savedMessage = nil }
    }

    private var providerPane: some View {
        SettingsPane(
            title: "Sorting intelligence",
            description: "Choose who decides how files are renamed and filed. Automatic keeps the system model first and uses only providers you configure."
        ) {
            Form {
                Picker("Provider", selection: $provider) {
                    Text("Automatic").tag(ModelProvider.automatic)
                    Text("Apple").tag(ModelProvider.apple)
                    Text("Ollama").tag(ModelProvider.ollama)
                    Text("OpenAI").tag(ModelProvider.openai)
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            Label(providerHelp, systemImage: providerSymbol)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var applePane: some View {
        SettingsPane(
            title: "Apple Foundation Models",
            description: "Use Apple Intelligence on this Mac, or explicitly permit eligible requests to use Private Cloud Compute."
        ) {
            Form {
                Picker("Model", selection: $appleModel) {
                    Text("Automatic").tag(AppleModelSelection.automatic)
                    Text("On this Mac").tag(AppleModelSelection.system)
                    Text("Private Cloud Compute").tag(AppleModelSelection.pcc)
                }
                Picker("Use case", selection: $appleUseCase) {
                    Text("General").tag(AppleUseCase.general)
                    Text("Content Tagging").tag(AppleUseCase.contentTagging)
                }
                Picker("Guardrails", selection: $appleGuardrails) {
                    Text("Default").tag(AppleGuardrails.default)
                    Text("Permit Content Transformations").tag(AppleGuardrails.permissiveContentTransformations)
                }
            }

            Divider()

            Toggle("Allow file context to be sent to Apple Private Cloud Compute", isOn: $allowApplePCC)
            Text(pccHelp)
                .font(.caption)
                .foregroundStyle(allowApplePCC ? .orange : .secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var localPane: some View {
        SettingsPane(
            title: "Local Ollama",
            description: "Connect Sorting Hat to an Ollama model running on this Mac or your local network."
        ) {
            Form {
                TextField("Server URL", text: $url)
                TextField("Model", text: $ollamaModel, prompt: Text("For example: gemma3:4b"))
            }
            Text("Files are sent only to the server address above. Automatic uses Ollama when Apple generation is unavailable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cloudPane: some View {
        SettingsPane(
            title: "OpenAI",
            description: "Configure an optional cloud fallback. The API key is stored in your macOS Keychain."
        ) {
            Form {
                TextField("Model", text: $openAIModel, prompt: Text("For example: gpt-5.4-nano"))
                SecureField("API key", text: $openAIKey)
            }
            Label("When OpenAI is selected or used as a fallback, extracted file context may be sent to OpenAI.", systemImage: "exclamationmark.shield")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func load() {
        do {
            let settings = try store.loadModelSettings()
            provider = settings.provider
            url = settings.url
            ollamaModel = settings.ollamaModel
            openAIModel = settings.openAIModel
            openAIKey = settings.openAIKey
            appleModel = settings.appleModel
            appleUseCase = settings.appleUseCase
            appleGuardrails = settings.appleGuardrails
            allowApplePCC = settings.allowApplePCC
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func save() {
        do {
            try store.saveModelSettings(
                provider: provider,
                appleModel: appleModel,
                appleUseCase: appleUseCase,
                appleGuardrails: appleGuardrails,
                allowApplePCC: allowApplePCC,
                url: url,
                ollamaModel: ollamaModel,
                openAIModel: openAIModel,
                openAIKey: openAIKey
            )
            errorMessage = nil
            savedMessage = "Settings saved"
        } catch {
            savedMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private var providerHelp: String {
        switch provider {
        case .automatic: "Tries Apple first, then configured Ollama and OpenAI fallbacks. Private Cloud Compute still requires explicit permission."
        case .apple: "Uses only the selected Apple policy. On-device processing remains local."
        case .ollama: "Uses only the configured Ollama server."
        case .openai: "Uses OpenAI directly and may send extracted file context to the service."
        }
    }

    private var providerSymbol: String {
        switch provider {
        case .automatic: "arrow.triangle.branch"
        case .apple: "cpu"
        case .ollama: "desktopcomputer"
        case .openai: "cloud"
        }
    }

    private var pccHelp: String {
        if appleModel == .pcc && !allowApplePCC {
            return "Private Cloud Compute cannot be used until this permission is enabled."
        }
        if allowApplePCC {
            return "Permission is enabled. Automatic may retry eligible on-device failures using Apple's Private Cloud Compute service."
        }
        return "Disabled. File context stays on this Mac when using Apple Foundation Models."
    }
}

private struct SettingsPane<Content: View>: View {
    let title: String
    let description: String
    @ViewBuilder let content: Content

    init(title: String, description: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.description = description
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.bold())
                Text(description)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            content
            Spacer(minLength: 0)
        }
        .padding(8)
    }
}
