import AppKit
import Observation
import ServiceManagement
import SortingHatCore

@MainActor @Observable
final class HatStore {
    var isWatching = false
    var isProcessing = false
    var status = "Ready"
    var recent: [Activity] = []
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var quickActionInstalled = false
    let inbox: URL
    let configURL: URL
    private var watchTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        inbox = home.appending(path: "SortingHat/Inbox", directoryHint: .isDirectory)
        configURL = home.appending(path: "SortingHat/sortinghat.conf")
        quickActionInstalled = Self.quickActionURL.fileExists
        bootstrap()
        start()
    }

    func start() {
        guard !isWatching else { return }
        isWatching = true
        status = "Watching Inbox"
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processNow()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func pause() {
        watchTask?.cancel(); watchTask = nil
        isWatching = false; status = "Paused"
    }

    func processNow() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        do {
            let config = try ConfigLoader.load(configURL)
            let configuredInbox = Self.expandedURL(config.inbox)
            let output = Self.expandedURL(config.output)
            let analyzer = PreferredAnalyzer(fmExecutable: Self.fmPath(), ollamaURL: config.ollamaURL, ollamaModel: config.ollamaModel,
                                             openAIModel: config.openAIModel, openAIKey: APIKeyStore.load(), provider: config.modelProvider,
                                             appleModel: config.appleModel, appleUseCase: config.appleUseCase,
                                             appleGuardrails: config.appleGuardrails, allowApplePCC: config.allowApplePCC)
            let organizer = Organizer(inbox: configuredInbox, output: output, rules: config.rules, analyzer: analyzer)
            let files = try organizer.candidates()
            if files.isEmpty { if isWatching { status = "Watching Inbox" }; return }
            status = "Reading \(files.count) file\(files.count == 1 ? "" : "s")"
            for outcome in organizer.planAll(files) {
                switch outcome {
                case .success(let move):
                    do {
                        try organizer.apply(move)
                        recent.insert(Activity(
                            sourceName: move.source.lastPathComponent,
                            filedName: move.destination.lastPathComponent,
                            destination: Self.displayPath(move.destination.deletingLastPathComponent()),
                            fileURL: move.destination,
                            tags: move.tags,
                            detail: move.reason,
                            outcome: .filed
                        ), at: 0)
                    } catch {
                        recent.insert(Activity(
                            sourceName: move.source.lastPathComponent,
                            detail: error.localizedDescription,
                            outcome: .failed
                        ), at: 0)
                    }
                case .failure(let source, let error):
                    let outcome: Activity.Outcome
                    if let hatError = error as? HatError, case .needsReview = hatError {
                        outcome = .needsReview
                    } else {
                        outcome = .failed
                    }
                    recent.insert(Activity(
                        sourceName: source.lastPathComponent,
                        detail: error.localizedDescription,
                        outcome: outcome
                    ), at: 0)
                }
                recent = Array(recent.prefix(20))
            }
            status = isWatching ? "Watching Inbox" : "Ready"
        } catch { status = error.localizedDescription }
    }

    func openInbox() { NSWorkspace.shared.open(inbox) }
    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
    func loadRules() throws -> [String] { try ConfigLoader.load(configURL).rules }

    func saveRules(_ rules: [String]) throws {
        let cleaned = rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        guard !cleaned.isEmpty else { throw HatError.invalidConfig("add at least one rule") }
        guard cleaned.allSatisfy({ !$0.contains("\n") && !$0.contains("\r") }) else {
            throw HatError.invalidConfig("each rule must fit on one line")
        }
        var config = try ConfigLoader.load(configURL)
        config.rules = cleaned
        try ConfigLoader.save(config, to: configURL)
        status = isWatching ? "Watching Inbox" : "Rules Updated"
    }

    func loadModelSettings() throws -> (provider: ModelProvider, appleModel: AppleModelSelection, appleUseCase: AppleUseCase, appleGuardrails: AppleGuardrails, allowApplePCC: Bool, url: String, ollamaModel: String, openAIModel: String, openAIKey: String) {
        let config = try ConfigLoader.load(configURL)
        return (config.modelProvider, config.appleModel, config.appleUseCase, config.appleGuardrails, config.allowApplePCC,
                config.ollamaURL, config.ollamaModel, config.openAIModel, APIKeyStore.load())
    }

    func saveModelSettings(provider: ModelProvider, appleModel: AppleModelSelection, appleUseCase: AppleUseCase,
                           appleGuardrails: AppleGuardrails, allowApplePCC: Bool, url: String,
                           ollamaModel: String, openAIModel: String, openAIKey: String) throws {
        guard URL(string: url) != nil else { throw HatError.invalidConfig("Ollama URL is not valid") }
        if appleModel == .pcc, !allowApplePCC { throw HatError.pccConsentRequired }
        var config = try ConfigLoader.load(configURL)
        config.ollamaURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        config.ollamaModel = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        config.openAIModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        config.modelProvider = provider
        config.appleModel = appleModel
        config.appleUseCase = appleUseCase
        config.appleGuardrails = appleGuardrails
        config.allowApplePCC = allowApplePCC
        try APIKeyStore.save(openAIKey.trimmingCharacters(in: .whitespacesAndNewlines))
        try ConfigLoader.save(config, to: configURL)
        status = "Model Settings Updated"
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = enabled
        } catch { status = "Launch at login: \(error.localizedDescription)"; launchAtLogin = !enabled }
    }

    func installQuickAction() {
        guard let script = Bundle.main.url(forResource: "install_quick_action", withExtension: "sh") else {
            status = "Quick Action installer is missing from this build"
            return
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path]
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                status = "Quick Action installation failed"
                return
            }
            quickActionInstalled = true
            status = "Finder Quick Action Installed"
        } catch {
            status = "Quick Action: \(error.localizedDescription)"
        }
    }

    private func bootstrap() {
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        try? Self.example.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private static func fmPath() -> String {
        ["/usr/bin/fm", "/usr/local/bin/fm", "/opt/homebrew/bin/fm"].first(where: FileManager.default.isExecutableFile(atPath:)) ?? "/usr/bin/fm"
    }

    private static func expandedURL(_ path: String) -> URL {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL
    }

    private static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path == home ? "~" : url.path.replacingOccurrences(of: home + "/", with: "~/")
    }

    private static var quickActionURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Services/Send to Sorting Hat.workflow", directoryHint: .isDirectory)
    }

    private static let example = """
    inbox: ~/SortingHat/Inbox
    output: ~/SortingHat
    settle_seconds: 2
    ollama_url: http://127.0.0.1:11434
    ollama_model:
    openai_model:
    model_provider: automatic
    apple_model: automatic
    apple_use_case: general
    apple_guardrails: default
    allow_apple_pcc: false
    rules:
      - Give every file a short, descriptive, lowercase filename. Use hyphens, never spaces.
      - Put receipts in Receipts/YYYY and tag them receipt and the merchant name.
      - Put screenshots in Screenshots/YYYY-MM and tag them screenshot.
      - Put everything else in Files/YYYY-MM and add one useful topic tag.
    """
}

private extension URL {
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
}

struct Activity: Identifiable {
    let id = UUID()
    let sourceName: String
    let filedName: String?
    let destination: String?
    let fileURL: URL?
    let tags: [String]
    let detail: String
    let outcome: Outcome
    let date: Date

    init(
        sourceName: String,
        filedName: String? = nil,
        destination: String? = nil,
        fileURL: URL? = nil,
        tags: [String] = [],
        detail: String,
        outcome: Outcome,
        date: Date = .now
    ) {
        self.sourceName = sourceName
        self.filedName = filedName
        self.destination = destination
        self.fileURL = fileURL
        self.tags = tags
        self.detail = detail
        self.outcome = outcome
        self.date = date
    }

    enum Outcome: String {
        case filed = "Filed"
        case needsReview = "Needs Review"
        case failed = "Failed"

        var symbol: String {
            switch self {
            case .filed: "checkmark.circle.fill"
            case .needsReview: "questionmark.circle.fill"
            case .failed: "exclamationmark.triangle.fill"
            }
        }

    }
}
