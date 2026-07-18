import SortingHatCore
import SwiftUI
import UniformTypeIdentifiers

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
    @State private var inboxURL: URL
    @State private var outputURL: URL
    @State private var choosingInbox = false
    @State private var choosingOutput = false
    @State private var repairingInboxAccess = false
    @State private var confirmingLegacyMigration = false
    @State private var pendingRemoval: InboxPendingImportRecord?

    init(store: HatStore) {
        self.store = store
        _inboxURL = State(initialValue: store.inbox)
        _outputURL = State(initialValue: store.outputRoot)
    }

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                generalPane
                    .tabItem { Label("General", systemImage: "folder.badge.gearshape") }
                finderPane
                    .tabItem { Label("Finder", systemImage: "puzzlepiece.extension") }
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
        .frame(width: 640, height: 500)
        .onAppear(perform: load)
        .onChange(of: provider) { savedMessage = nil }
        .onChange(of: appleModel) { savedMessage = nil }
        .onChange(of: allowApplePCC) { savedMessage = nil }
        .fileImporter(isPresented: $choosingInbox, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { inboxURL = url; saveLocations() }
        }
        .fileImporter(isPresented: $choosingOutput, allowedContentTypes: [.folder]) { result in
            if case .success(let url) = result { outputURL = url; saveLocations() }
        }
        .fileImporter(isPresented: $repairingInboxAccess, allowedContentTypes: [.folder]) { result in
            guard case .success(let url) = result else { return }
            do {
                try store.repairInboxAccess(url)
                inboxURL = store.inbox
                errorMessage = nil
                savedMessage = "Inbox access repaired"
            } catch {
                savedMessage = nil
                errorMessage = error.localizedDescription
            }
        }
        .confirmationDialog(
            "Retire the legacy Quick Action?",
            isPresented: $confirmingLegacyMigration,
            titleVisibility: .visible
        ) {
            Button("Move Legacy Workflow to Backup", role: .destructive) { migrateLegacyAction() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Sorting Hat moves the Automator workflow into its Application Support backup. It never changes any source files.")
        }
        .confirmationDialog(
            "Remove this staged import?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }
            ),
            titleVisibility: .visible,
            presenting: pendingRemoval
        ) { item in
            Button("Remove Staged Copy", role: .destructive) {
                store.removeFinderPendingImport(item)
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { item in
            Text("This removes Sorting Hat’s staged copy of “\(item.filename)”. The original Finder file is not changed; reselect it in Finder if you still want to import it.")
        }
    }

    private var generalPane: some View {
        SettingsPane(title: "Files and automation", description: "Choose where files arrive, where the hat files them, and how long activity remains visible.") {
            Form {
                LabeledContent("Inbox") {
                    HStack { Text(inboxURL.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle); Button("Choose…") { choosingInbox = true } }
                }
                LabeledContent("Filed output") {
                    HStack { Text(outputURL.path(percentEncoded: false)).lineLimit(1).truncationMode(.middle); Button("Choose…") { choosingOutput = true } }
                }
                Toggle("Launch Sorting Hat at login", isOn: Binding(
                    get: { store.launchAtLogin },
                    set: { enabled in store.setLaunchAtLogin(enabled) }
                ))
                Stepper("Keep \(store.activityRetention) activity records", value: Binding(
                    get: { store.activityRetention },
                    set: { limit in store.setActivityRetention(limit) }
                ), in: 25...1000, step: 25)
            }
            HStack {
                Text("Want to redesign the filing plan?").foregroundStyle(.secondary)
                Spacer()
                Button("Run Setup Again…") { store.restartSetup() }
            }
        }
    }

    private var providerPane: some View {
        SettingsPane(
            title: "Sorting intelligence",
            description: "Choose who decides how files are renamed and filed. Automatic is recommended and prefers private processing on this Mac."
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
            Label(privacySummary, systemImage: provider == .openai ? "network" : "lock.shield")
                .font(.caption)
                .foregroundStyle(provider == .openai ? .orange : .secondary)
        }
    }

    private var finderPane: some View {
        ScrollView {
            SettingsPane(
                title: "Send to Sorting Hat",
                description: "Use Finder as a quiet intake surface. Rules, activity, review, and recovery stay inside Sorting Hat."
            ) {
                VStack(alignment: .leading, spacing: 12) {
                    integrationRow(
                        title: "Finder Quick Action",
                        detail: finderActionDetail,
                        symbol: store.finderExtensionEmbedded ? (store.finderDeliveryConfirmed ? "checkmark.circle.fill" : "puzzlepiece.extension.fill") : "exclamationmark.triangle.fill",
                        color: store.finderExtensionEmbedded ? (store.finderDeliveryConfirmed ? .green : Color.secondary) : .red
                    )
                    integrationRow(
                        title: "Shared intake",
                        detail: sharedIntakeDetail,
                        symbol: store.finderSharedContainerAvailable ? "shippingbox.fill" : "exclamationmark.icloud.fill",
                        color: store.finderSharedContainerAvailable ? Color.secondary : .red
                    )
                    integrationRow(
                        title: "Inbox access",
                        detail: inboxAccessDetail,
                        symbol: store.inboxAccessState.needsRecovery ? "lock.trianglebadge.exclamationmark" : "lock.open.fill",
                        color: store.inboxAccessState.needsRecovery ? .orange : .green
                    )
                }

                HStack {
                    Button("Open System Settings…") { store.openExtensionsSettings() }
                    if store.inboxAccessState.needsRecovery {
                        Button("Repair Inbox Access…") { repairingInboxAccess = true }
                            .disabled(!store.finderSharedContainerAvailable)
                    }
                    Spacer()
                    if store.finderPendingImports > 0 {
                        Label("\(store.finderPendingImports) waiting", systemImage: "clock")
                            .foregroundStyle(.orange)
                    }
                }

                Text("macOS disables new Quick Actions by default. In System Settings, open General → Login Items & Extensions → Finder and enable “Send to Sorting Hat”. Send up to 256 files at a time (256 MB per file, 1 GB total); larger files can use Add Files here. If the app is closed, Finder keeps a durable staged copy and Sorting Hat imports it on the next launch. Pausing stops sorting, not intake.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let issue = store.finderQueueIssue {
                    Label(issue, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if !store.finderPendingRecords.isEmpty {
                    Divider()
                    DisclosureGroup("Staged Finder imports (\(store.finderPendingRecords.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.finderPendingRecords, id: \.id) { (item: InboxPendingImportRecord) in
                                HStack(alignment: .firstTextBaseline, spacing: 10) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.filename).lineLimit(1)
                                        Text(item.lastError ?? "Waiting for valid access to the configured Inbox.")
                                            .font(.caption)
                                            .foregroundStyle(item.lastError == nil ? Color.secondary : Color.red)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button("Retry") { store.retryFinderPendingImport(item) }
                                        .controlSize(.small)
                                        .disabled(store.inboxAccessState.needsRecovery)
                                    Button("Remove", role: .destructive) { pendingRemoval = item }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                if !store.finderIntakeFailures.isEmpty {
                    Divider()
                    DisclosureGroup("Recent intake failures (\(store.finderIntakeFailures.count))") {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(store.finderIntakeFailures) { failure in
                                HStack(alignment: .firstTextBaseline) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(failure.filename).lineLimit(1)
                                        Text(failure.message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                                        Text("Reselect only this failed file in Finder. Dismiss removes this notice, not the original file.")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Button("Dismiss") { store.removeFinderIntakeFailure(failure) }
                                        .controlSize(.small)
                                }
                            }
                        }
                    }
                }

                if store.legacyQuickActionInstalled {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Legacy Automator action detected")
                            Text(store.canMigrateLegacyQuickAction
                                 ? "This installed build delivered its last native Finder import to the configured Inbox. The old workflow can be backed up."
                                 : "Complete and deliver a native Finder import with this installed build before retiring the old workflow.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Retire Legacy Action…") { confirmingLegacyMigration = true }
                            .disabled(!store.canMigrateLegacyQuickAction)
                    }
                } else if let backup = store.legacyQuickActionBackupURL {
                    Divider()
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Legacy Automator action backed up")
                            Text(backup.path(percentEncoded: false))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                                .truncationMode(.middle)
                            Text("If Finder still shows the old Service, relaunch Finder. Restore is available here if you need to roll back.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Restore Legacy Action") { restoreLegacyAction() }
                    }
                }
            }
            .padding(.trailing, 6)
        }
    }

    private func integrationRow(title: String, detail: String, symbol: String, color: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 18)
            Text(title).fontWeight(.medium)
            Spacer()
            Text(detail).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private var finderActionDetail: String {
        guard store.finderExtensionEmbedded else { return "Missing from this app installation" }
        return store.finderDeliveryConfirmed
            ? "Bundled and used successfully"
            : "Bundled — enable it in System Settings"
    }

    private var sharedIntakeDetail: String {
        guard store.finderSharedContainerAvailable else { return "Unavailable — reinstall a correctly signed build" }
        if let invocation = store.finderLastInvocation {
            if invocation.failures > 0 {
                return "Last action reported \(invocation.failures) failure\(invocation.failures == 1 ? "" : "s")"
            }
            return store.finderDeliveryConfirmed
                ? "Last delivery verified \(invocation.date.formatted(date: .abbreviated, time: .shortened))"
                : "Last action staged \(invocation.staged) file\(invocation.staged == 1 ? "" : "s"); delivery not yet verified"
        }
        return "No Finder invocation recorded yet"
    }

    private var inboxAccessDetail: String {
        switch store.inboxAccessState {
        case .available(let url): url.path(percentEncoded: false)
        case .stale: "Permission is stale — choose the Inbox again"
        case .missing: "Choose the Inbox to persist permission"
        case .invalid(let message): "Permission needs repair: \(message)"
        case .mismatched(let bookmarked, let expected):
            "Saved access points to \(bookmarked.lastPathComponent), not \(expected.lastPathComponent) — repair required"
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

    private func saveLocations() {
        do { try store.saveLocations(inbox: inboxURL, output: outputURL); errorMessage = nil; savedMessage = "Locations saved" }
        catch { savedMessage = nil; errorMessage = error.localizedDescription }
    }

    private func migrateLegacyAction() {
        do {
            try store.migrateLegacyQuickAction()
            errorMessage = nil
            savedMessage = "Legacy Quick Action moved to backup"
        } catch {
            savedMessage = nil
            errorMessage = error.localizedDescription
        }
    }

    private func restoreLegacyAction() {
        do {
            try store.restoreLegacyQuickAction()
            errorMessage = nil
            savedMessage = "Legacy Quick Action restored"
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

    private var privacySummary: String {
        switch provider {
        case .automatic: "Uses on-device Apple Intelligence first. Network providers are used only when configured."
        case .apple: allowApplePCC ? "Apple processing may use Private Cloud Compute with your permission." : "Apple processing remains on this Mac."
        case .ollama: "File context is sent only to the Ollama server address you configure."
        case .openai: "Extracted file context may be sent to OpenAI."
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
