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
    var inboxItems: [InboxItem] = []
    var setupRequired = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var activityRetention = UserDefaults.standard.object(forKey: "activityRetention") as? Int ?? 200
    var inbox: URL
    var outputRoot: URL
    let configURL: URL
    let activityURL: URL
    private var watchTask: Task<Void, Never>?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        inbox = home.appending(path: "SortingHat/Inbox", directoryHint: .isDirectory)
        outputRoot = home.appending(path: "SortingHat", directoryHint: .isDirectory)
        configURL = home.appending(path: "SortingHat/sortinghat.conf")
        activityURL = home.appending(path: "SortingHat/activity-history.json")
        setupRequired = !FileManager.default.fileExists(atPath: configURL.path)
        bootstrap()
        if let config = try? ConfigLoader.load(configURL) {
            inbox = Self.expandedURL(config.inbox)
            outputRoot = Self.expandedURL(config.output)
        }
        recent = ledger.load()
        refreshInbox()
        if !setupRequired { start() }
    }

    func start() {
        guard !isWatching else { return }
        isWatching = true
        status = "Watching the Inbox"
        watchTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.processNow()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    func pause() {
        watchTask?.cancel(); watchTask = nil
        isWatching = false; status = "The hat is resting"
    }

    func processNow() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false; refreshInbox() }
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
            if files.isEmpty { if isWatching { status = "Watching the Inbox" }; return }
            status = "Considering \(files.count) file\(files.count == 1 ? "" : "s")"
            for outcome in organizer.planAll(files) {
                switch outcome {
                case .success(let move):
                    do {
                        try organizer.apply(move)
                        record(Activity(
                            sourceName: move.source.lastPathComponent,
                            sourceURL: move.source,
                            filedName: move.destination.lastPathComponent,
                            destination: Self.displayPath(move.destination.deletingLastPathComponent()),
                            fileURL: move.destination,
                            tags: move.tags,
                            detail: move.reason,
                            outcome: .filed
                        ))
                    } catch {
                        record(Activity(
                            sourceName: move.source.lastPathComponent,
                            sourceURL: move.source,
                            fileURL: move.source,
                            detail: error.localizedDescription,
                            outcome: .failed
                        ))
                    }
                case .failure(let source, let error):
                    let outcome: Activity.Outcome
                    if let hatError = error as? HatError, case .needsReview = hatError {
                        outcome = .needsReview
                    } else {
                        outcome = .failed
                    }
                    record(Activity(
                        sourceName: source.lastPathComponent,
                        sourceURL: source,
                        fileURL: source,
                        detail: error.localizedDescription,
                        outcome: outcome
                    ))
                }
            }
            status = isWatching ? "Watching the Inbox" : "Ready"
        } catch { status = error.localizedDescription }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }
    func addToInbox(_ urls: [URL]) throws {
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        for source in urls {
            let accessing = source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }
            let values = try source.resourceValues(forKeys: [.isRegularFileKey])
            guard values.isRegularFile == true else { continue }
            var destination = inbox.appending(path: source.lastPathComponent)
            if destination.standardizedFileURL == source.standardizedFileURL { continue }
            let stem = destination.deletingPathExtension().lastPathComponent
            let ext = destination.pathExtension
            var copy = 2
            while FileManager.default.fileExists(atPath: destination.path) {
                let name = ext.isEmpty ? "\(stem)-\(copy)" : "\(stem)-\(copy).\(ext)"
                destination = inbox.appending(path: name)
                copy += 1
            }
            try FileManager.default.copyItem(at: source, to: destination)
        }
        refreshInbox()
        status = "Files added to the Inbox"
    }
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
        status = isWatching ? "Watching the Inbox" : "Rules Updated"
    }

    func completeSetup(with plan: RulePlan) throws {
        try RulePlanValidator.validate(plan)
        try saveRules(plan.compiledRules)
        setupRequired = false
        start()
    }

    func saveLocations(inbox: URL, output: URL) throws {
        var config = try ConfigLoader.load(configURL)
        config.inbox = Self.portablePath(inbox)
        config.output = Self.portablePath(output)
        try ConfigLoader.save(config, to: configURL)
        self.inbox = inbox.standardizedFileURL
        outputRoot = output.standardizedFileURL
        try FileManager.default.createDirectory(at: self.inbox, withIntermediateDirectories: true)
        refreshInbox()
    }

    func restartSetup() {
        pause()
        setupRequired = true
    }

    func setActivityRetention(_ limit: Int) {
        activityRetention = min(max(limit, 25), 1000)
        UserDefaults.standard.set(activityRetention, forKey: "activityRetention")
        recent = Array(recent.prefix(activityRetention))
        try? ledger.save(recent)
    }

    func undo(_ activity: Activity) throws {
        guard activity.outcome == .filed, let filedURL = activity.fileURL, let sourceURL = activity.sourceURL else { return }
        guard FileManager.default.fileExists(atPath: filedURL.path) else {
            throw RulePlanError.invalid("The filed item is no longer at its recorded destination.")
        }
        try FileManager.default.createDirectory(at: sourceURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw RulePlanError.invalid("A file named \(sourceURL.lastPathComponent) already exists in the Inbox.")
        }
        try FileManager.default.moveItem(at: filedURL, to: sourceURL)
        recent.removeAll { $0.id == activity.id }
        try? ledger.save(recent)
        status = "Returned \(sourceURL.lastPathComponent) to the Inbox"
    }

    func resolve(_ activity: Activity, filedName: String, destination: String, teachingRule: String?) throws {
        guard let source = activity.fileURL, FileManager.default.fileExists(atPath: source.path) else {
            throw RulePlanError.invalid("The review file is no longer in the Inbox.")
        }
        let name = filedName.trimmingCharacters(in: .whitespacesAndNewlines)
        let folder = destination.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !name.contains("/"), !name.contains(":"), URL(fileURLWithPath: name).pathExtension == source.pathExtension else {
            throw RulePlanError.invalid("Use a safe filename and preserve the .\(source.pathExtension) extension.")
        }
        guard !folder.isEmpty, !folder.hasPrefix("/"), !folder.hasPrefix("~"),
              !folder.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
            throw RulePlanError.invalid("Choose a safe destination under the output folder.")
        }
        let destinationURL = outputRoot.appending(path: folder, directoryHint: .isDirectory).appending(path: name)
        guard !FileManager.default.fileExists(atPath: destinationURL.path) else {
            throw RulePlanError.invalid("A file with that name already exists at the destination.")
        }
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: source, to: destinationURL)
        recent.removeAll { $0.id == activity.id }
        record(Activity(sourceName: activity.sourceName, sourceURL: source, filedName: name, destination: folder,
                        fileURL: destinationURL, detail: "Corrected during review", outcome: .filed))
        if let teachingRule, !teachingRule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var rules = try loadRules()
            rules.insert(teachingRule.trimmingCharacters(in: .whitespacesAndNewlines), at: max(1, rules.count - 1))
            try saveRules(rules)
        }
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

    private func record(_ activity: Activity) {
        if activity.outcome != .filed {
            recent.removeAll { $0.sourceName == activity.sourceName && $0.outcome != .filed }
        }
        recent.insert(activity, at: 0)
        recent = Array(recent.prefix(ledger.retentionLimit))
        try? ledger.save(recent)
    }

    private var ledger: ActivityLedger { ActivityLedger(url: activityURL, retentionLimit: activityRetention) }

    private func refreshInbox() {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isHiddenKey, .contentModificationDateKey, .fileSizeKey, .contentTypeKey]
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles]
        )) ?? []
        inboxItems = urls.compactMap { url in
            guard url.lastPathComponent != "sortinghat.conf",
                  let values = try? url.resourceValues(forKeys: keys),
                  values.isRegularFile == true else { return nil }
            return InboxItem(
                url: url,
                modified: values.contentModificationDate,
                size: values.fileSize.map(Int64.init),
                kind: values.contentType?.localizedDescription ?? url.pathExtension.uppercased()
            )
        }
        .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path == home ? "~" : url.path.replacingOccurrences(of: home + "/", with: "~/")
    }

    private static func portablePath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.standardizedFileURL.path
        return path == home ? "~" : path.replacingOccurrences(of: home + "/", with: "~/")
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

struct InboxItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let modified: Date?
    let size: Int64?
    let kind: String

    var name: String { url.lastPathComponent }
}

private extension URL {
    var fileExists: Bool { FileManager.default.fileExists(atPath: path) }
}

struct Activity: Identifiable, Codable {
    let id: UUID
    let sourceName: String
    let sourceURL: URL?
    let filedName: String?
    let destination: String?
    let fileURL: URL?
    let tags: [String]
    let detail: String
    let outcome: Outcome
    let date: Date

    init(
        sourceName: String,
        sourceURL: URL? = nil,
        filedName: String? = nil,
        destination: String? = nil,
        fileURL: URL? = nil,
        tags: [String] = [],
        detail: String,
        outcome: Outcome,
        date: Date = .now
    ) {
        self.id = UUID()
        self.sourceName = sourceName
        self.sourceURL = sourceURL
        self.filedName = filedName
        self.destination = destination
        self.fileURL = fileURL
        self.tags = tags
        self.detail = detail.replacingOccurrences(
            of: "\u{001B}\\[[0-9;:]*[A-Za-z]",
            with: "",
            options: .regularExpression
        )
        self.outcome = outcome
        self.date = date
    }

    enum Outcome: String, Codable {
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
