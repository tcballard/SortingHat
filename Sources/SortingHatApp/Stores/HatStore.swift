import AppKit
import Observation
import ServiceManagement
import SortingHatCore

@MainActor @Observable
final class HatStore {
    var isWatching = false {
        didSet { onWatchingChanged?(isWatching) }
    }
    var isProcessing = false
    var status = "Ready"
    var recent: [Activity] = []
    var inboxItems: [InboxItem] = []
    var setupRequired = false
    var launchAtLogin = SMAppService.mainApp.status == .enabled
    var activityRetention = UserDefaults.standard.object(forKey: "activityRetention") as? Int ?? 200
    var finderExtensionEmbedded = false
    var finderSharedContainerAvailable = false
    var finderPendingImports = 0
    var finderPendingRecords: [InboxPendingImportRecord] = []
    var finderIntakeFailures: [InboxIngressFailureRecord] = []
    var finderLastInvocation: InboxIngressInvocation?
    var finderDeliveryConfirmed = false
    var inboxAccessState: InboxAccessState = .missing
    var outputAccessState: InboxAccessState = .missing
    var finderQueueIssue: String?
    var legacyQuickActionInstalled = false
    var legacyQuickActionBackupURL: URL?
    var inbox: URL
    var outputRoot: URL
    let configURL: URL
    let activityURL: URL
    private var watchTask: Task<Void, Never>?
    private var intakeTask: Task<Void, Never>?
    private let importer = InboxImportService()
    private var finderIntakeRoot: URL?
    private var finderDrainInFlight = false
    private var activeInboxAccessURL: URL?
    private var activeOutputAccessURL: URL?
    @ObservationIgnored var onWatchingChanged: ((Bool) -> Void)?

    init() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        inbox = home.appending(path: "SortingHat/Inbox", directoryHint: .isDirectory)
        outputRoot = home.appending(path: "SortingHat", directoryHint: .isDirectory)
        configURL = home.appending(path: "SortingHat/sortinghat.conf")
        activityURL = home.appending(path: "SortingHat/activity-history.json")
        legacyQuickActionBackupURL = UserDefaults.standard.string(forKey: "legacyQuickActionBackupPath")
            .map { URL(fileURLWithPath: $0) }
            .flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
        setupRequired = !FileManager.default.fileExists(atPath: configURL.path)
        bootstrap()
        if let config = try? ConfigLoader.load(configURL) {
            inbox = Self.expandedURL(config.inbox)
            outputRoot = Self.expandedURL(config.output)
        }
        activateConfiguredFolderAccess()
        configureFinderIntake()
        recent = ledger.load()
        refreshInbox()
        startIntakeCoordinator()
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
        // The intake queue exposes a file only immediately before it records
        // the durable delivery receipt. Never let the sorter move that visible
        // file across this short commit boundary.
        guard !isProcessing, !finderDrainInFlight else { return }
        isProcessing = true
        defer { isProcessing = false; refreshInbox() }
        do {
            let config = try ConfigLoader.load(configURL)
            let configuredInbox = Self.expandedURL(config.inbox)
            let output = Self.expandedURL(config.output)
            let analyzer = PreferredAnalyzer(ollamaURL: config.ollamaURL, ollamaModel: config.ollamaModel,
                                             openAIModel: config.openAIModel, openAIKey: APIKeyStore.load(), provider: config.modelProvider,
                                             appleModel: config.appleModel == .pcc ? .system : config.appleModel,
                                             appleUseCase: config.appleUseCase, appleGuardrails: config.appleGuardrails)
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
        let batch = importer.importFiles(urls, to: inbox)
        refreshInbox()
        status = batch.statusSummary
        if !batch.failures.isEmpty { throw InboxImportBatchError(batch: batch) }
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
        let standardizedInbox = inbox.standardizedFileURL
        let standardizedOutput = output.standardizedFileURL
        try FileManager.default.createDirectory(at: standardizedInbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: standardizedOutput, withIntermediateDirectories: true)

        var config = try ConfigLoader.load(configURL)
        config.inbox = Self.portablePath(standardizedInbox)
        config.output = Self.portablePath(standardizedOutput)

        let inboxBookmarkStore = InboxAccessBookmarkStore(root: Self.inboxAccessRoot)
        let outputBookmarkStore = InboxAccessBookmarkStore(root: Self.outputAccessRoot, name: "Output")
        let previousInboxAccess = try inboxBookmarkStore.snapshot()
        let previousOutputAccess = try outputBookmarkStore.snapshot()
        let inboxGrant = try inboxBookmarkStore.prepare(standardizedInbox)
        let outputGrant = try outputBookmarkStore.prepare(standardizedOutput)
        do {
            // Publish both grants before config. If any write fails, restore the
            // complete prior access pair so config and permissions cannot drift.
            try inboxBookmarkStore.commit(inboxGrant)
            try outputBookmarkStore.commit(outputGrant)
            try ConfigLoader.save(config, to: configURL)
        } catch {
            try? inboxBookmarkStore.restore(previousInboxAccess)
            try? outputBookmarkStore.restore(previousOutputAccess)
            inboxAccessState = .invalid(error.localizedDescription)
            outputAccessState = .invalid(error.localizedDescription)
            throw error
        }

        self.inbox = standardizedInbox
        outputRoot = standardizedOutput
        activateConfiguredFolderAccess()
        Task { await drainFinderIntake() }
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

    func retry(_ activity: Activity) async throws {
        guard activity.outcome == .failed else { return }
        guard !isProcessing else {
            throw RulePlanError.invalid("The hat is already sorting. Try this file again when it has finished.")
        }
        guard let fileURL = activity.fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RulePlanError.invalid("The failed file is no longer available.")
        }
        removeActivity(activity)
        status = "Trying \(activity.sourceName) again"
        await processNow()
    }

    func sendToReview(_ activity: Activity) throws {
        guard activity.outcome == .failed else { return }
        guard let fileURL = activity.fileURL, FileManager.default.fileExists(atPath: fileURL.path) else {
            throw RulePlanError.invalid("The failed file is no longer available.")
        }
        removeActivity(activity)
        record(Activity(
            sourceName: activity.sourceName,
            sourceURL: activity.sourceURL,
            filedName: activity.filedName,
            destination: activity.destination,
            fileURL: fileURL,
            tags: activity.tags,
            detail: "Sent to manual review after sorting failed: \(activity.detail)",
            outcome: .needsReview
        ))
        status = "Ready to review \(activity.sourceName)"
    }

    func removeActivity(_ activity: Activity) {
        recent.removeAll { $0.id == activity.id }
        try? ledger.save(recent)
        status = activity.outcome == .failed ? "Removed the error from Activity" : status
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

    func loadModelSettings() throws -> (provider: ModelProvider, appleModel: AppleModelSelection, appleUseCase: AppleUseCase, appleGuardrails: AppleGuardrails, url: String, ollamaModel: String, openAIModel: String, openAIKey: String) {
        let config = try ConfigLoader.load(configURL)
        let appModel: AppleModelSelection = config.appleModel == .pcc ? .system : config.appleModel
        return (config.modelProvider, appModel, config.appleUseCase, config.appleGuardrails,
                config.ollamaURL, config.ollamaModel, config.openAIModel, APIKeyStore.load())
    }

    func saveModelSettings(provider: ModelProvider, appleModel: AppleModelSelection, appleUseCase: AppleUseCase,
                           appleGuardrails: AppleGuardrails, url: String,
                           ollamaModel: String, openAIModel: String, openAIKey: String) throws {
        guard URL(string: url) != nil else { throw HatError.invalidConfig("Ollama URL is not valid") }
        var config = try ConfigLoader.load(configURL)
        config.ollamaURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        config.ollamaModel = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        config.openAIModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        config.modelProvider = provider
        config.appleModel = appleModel == .pcc ? .system : appleModel
        config.appleUseCase = appleUseCase
        config.appleGuardrails = appleGuardrails
        config.allowApplePCC = false
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

    func repairInboxAccess(_ selectedInbox: URL) throws {
        guard finderIntakeRoot != nil else {
            throw InboxImportIssue(
                code: .sharedContainerUnavailable,
                filename: "",
                message: "The shared Finder intake is unavailable. Reinstall a correctly signed build before repairing Inbox access."
            )
        }
        try saveLocations(inbox: selectedInbox, output: outputRoot)
        status = "Inbox access repaired"
    }

    func removeFinderIntakeFailure(_ failure: InboxIngressFailureRecord) {
        guard let finderIntakeRoot else { return }
        Task {
            let errorMessage = await Task.detached(priority: .utility) {
                do {
                    try InboxImportQueue(root: finderIntakeRoot).removeFailure(id: failure.id)
                    return nil as String?
                } catch { return error.localizedDescription }
            }.value
            finderQueueIssue = errorMessage
            await drainFinderIntake()
        }
    }

    func retryFinderPendingImport(_ item: InboxPendingImportRecord) {
        guard let finderIntakeRoot else { return }
        let configuredInbox = inbox
        Task {
            let errorMessage = await Task.detached(priority: .utility) {
                do {
                    try InboxImportQueue(root: finderIntakeRoot).retryPending(id: item.id, in: configuredInbox)
                    return nil as String?
                } catch { return error.localizedDescription }
            }.value
            finderQueueIssue = errorMessage
            await drainFinderIntake()
        }
    }

    func removeFinderPendingImport(_ item: InboxPendingImportRecord) {
        guard let finderIntakeRoot else { return }
        Task {
            let errorMessage = await Task.detached(priority: .utility) {
                do {
                    try InboxImportQueue(root: finderIntakeRoot).removePending(id: item.id)
                    return nil as String?
                } catch { return error.localizedDescription }
            }.value
            finderQueueIssue = errorMessage
            await drainFinderIntake()
        }
    }

    func openExtensionsSettings() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/System Settings.app"))
    }

    func migrateLegacyQuickAction() throws {
        guard canMigrateLegacyQuickAction else {
            throw InboxImportIssue(
                code: .sharedContainerUnavailable,
                filename: "Send to Sorting Hat.workflow",
                message: "Use the native Finder action successfully before retiring the legacy workflow."
            )
        }
        try moveLegacyQuickActionToBackup(
            status: "Legacy Quick Action moved to backup; Finder may take a moment to refresh"
        )
    }

    func prepareNativeQuickActionVerification() throws {
        guard canPrepareNativeQuickActionVerification else {
            throw InboxImportIssue(
                code: .sharedContainerUnavailable,
                filename: "Send to Sorting Hat.workflow",
                message: "Install a signed build containing the native Finder action before hiding the legacy workflow."
            )
        }
        try moveLegacyQuickActionToBackup(
            status: "Legacy Quick Action backed up; relaunch Finder to verify the native action"
        )
    }

    private func moveLegacyQuickActionToBackup(status newStatus: String) throws {
        let source = Self.legacyQuickActionURL
        guard FileManager.default.fileExists(atPath: source.path) else {
            throw InboxImportIssue(
                code: .copyFailed,
                filename: source.lastPathComponent,
                message: "The legacy workflow is no longer installed."
            )
        }
        let backupRoot = FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/SortingHat/Legacy Quick Actions", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        let formatter = ISO8601DateFormatter()
        let stamp = formatter.string(from: .now).replacingOccurrences(of: ":", with: "-")
        let destination = backupRoot.appending(path: "Send to Sorting Hat-\(stamp).workflow")
        try FileManager.default.moveItem(at: source, to: destination)
        UserDefaults.standard.set(destination.path, forKey: "legacyQuickActionBackupPath")
        legacyQuickActionBackupURL = destination
        legacyQuickActionInstalled = false
        status = newStatus
    }

    func restoreLegacyQuickAction() throws {
        guard let backup = legacyQuickActionBackupURL,
              FileManager.default.fileExists(atPath: backup.path) else {
            throw InboxImportIssue(
                code: .copyFailed,
                filename: "Send to Sorting Hat.workflow",
                message: "The legacy workflow backup is no longer available."
            )
        }
        let destination = Self.legacyQuickActionURL
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw InboxImportIssue(
                code: .copyFailed,
                filename: destination.lastPathComponent,
                message: "A legacy workflow is already installed."
            )
        }
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: backup, to: destination)
        UserDefaults.standard.removeObject(forKey: "legacyQuickActionBackupPath")
        legacyQuickActionBackupURL = nil
        legacyQuickActionInstalled = true
        status = "Legacy Quick Action restored"
    }

    var canMigrateLegacyQuickAction: Bool {
        finderExtensionEmbedded && finderDeliveryConfirmed && finderPendingImports == 0
    }

    var canPrepareNativeQuickActionVerification: Bool {
        finderExtensionEmbedded && finderSharedContainerAvailable && !finderDeliveryConfirmed && legacyQuickActionInstalled
    }

    private func bootstrap() {
        try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        guard !FileManager.default.fileExists(atPath: configURL.path) else { return }
        try? Self.example.write(to: configURL, atomically: true, encoding: .utf8)
    }

    private func configureFinderIntake() {
        finderExtensionEmbedded = Bundle.main.builtInPlugInsURL
            .map { FileManager.default.fileExists(atPath: $0.appending(path: "Send to Sorting Hat.appex").path) } ?? false
        legacyQuickActionInstalled = FileManager.default.fileExists(atPath: Self.legacyQuickActionURL.path)
        do {
            let root = try InboxImportQueue.appGroupRoot()
            finderIntakeRoot = root
            finderSharedContainerAvailable = true
        } catch {
            finderSharedContainerAvailable = false
            finderQueueIssue = error.localizedDescription
        }
    }

    private func activateConfiguredFolderAccess() {
        stopConfiguredFolderAccess()

        let inboxState = InboxAccessBookmarkStore(root: Self.inboxAccessRoot)
            .resolve(expectedInbox: inbox)
        let outputState = InboxAccessBookmarkStore(root: Self.outputAccessRoot, name: "Output")
            .resolve(expectedInbox: outputRoot)

        inboxAccessState = inboxState
        outputAccessState = outputState
        activeInboxAccessURL = activate(inboxState, label: "Inbox")
        activeOutputAccessURL = activate(outputState, label: "filed output")
    }

    private func activate(_ state: InboxAccessState, label: String) -> URL? {
        guard case .available(let url) = state else { return nil }
        guard url.startAccessingSecurityScopedResource() else {
            let message = "Saved \(label) permission could not be activated. Choose the folder again."
            if label == "Inbox" {
                inboxAccessState = .invalid(message)
            } else {
                outputAccessState = .invalid(message)
            }
            return nil
        }
        return url
    }

    private func stopConfiguredFolderAccess() {
        activeInboxAccessURL?.stopAccessingSecurityScopedResource()
        activeOutputAccessURL?.stopAccessingSecurityScopedResource()
        activeInboxAccessURL = nil
        activeOutputAccessURL = nil
    }

    private func startIntakeCoordinator() {
        guard intakeTask == nil else { return }
        intakeTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.drainFinderIntake()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    private func drainFinderIntake() async {
        guard !finderDrainInFlight else { return }
        guard let finderIntakeRoot else {
            finderSharedContainerAvailable = false
            return
        }
        finderDrainInFlight = true
        defer { finderDrainInFlight = false }

        let configuredInbox = inbox.standardizedFileURL
        let currentBuild = Self.buildNumber
        let accessRoot = Self.inboxAccessRoot
        let allowDrain = !setupRequired
        let result = await Task.detached(priority: .utility) {
            let queue = InboxImportQueue(root: finderIntakeRoot)
            let bookmarkStore = InboxAccessBookmarkStore(root: accessRoot)
            var accessState = bookmarkStore.resolve(expectedInbox: configuredInbox)
            var importedCount = 0
            var queueIssue: String?

            if allowDrain, case .available(let accessURL) = accessState {
                let accessing = accessURL.startAccessingSecurityScopedResource()
                if !accessing {
                    accessState = .invalid("Saved Inbox permission could not be activated. Choose the configured Inbox again.")
                } else {
                    defer { accessURL.stopAccessingSecurityScopedResource() }
                    do {
                        let values = try accessURL.resourceValues(forKeys: [.isDirectoryKey])
                        guard values.isDirectory == true else {
                            throw InboxImportIssue(
                                code: .inboxUnavailable,
                                filename: "",
                                message: "The configured Inbox is no longer a directory."
                            )
                        }
                        let report = queue.drain(to: accessURL)
                        importedCount = report.results.count
                        queueIssue = report.queueIssues.first?.localizedDescription
                    } catch {
                        accessState = .invalid(error.localizedDescription)
                    }
                }
            }

            let invocation = queue.lastInvocation()
            let failures = queue.failures()
            return FinderIntakePass(
                accessState: accessState,
                pending: queue.pendingImports(),
                failures: failures,
                invocation: invocation,
                queueIssue: queueIssue,
                importedCount: importedCount,
                deliveryConfirmed: failures.isEmpty
                    && queue.confirmedInvocation(to: configuredInbox, currentBuild: currentBuild) != nil
            )
        }.value

        finderSharedContainerAvailable = true
        inboxAccessState = result.accessState
        finderPendingRecords = result.pending
        finderPendingImports = result.pending.count
        finderIntakeFailures = result.failures
        finderLastInvocation = result.invocation
        finderQueueIssue = result.queueIssue
        finderDeliveryConfirmed = result.deliveryConfirmed
        legacyQuickActionInstalled = FileManager.default.fileExists(atPath: Self.legacyQuickActionURL.path)
        if result.importedCount > 0 {
            refreshInbox()
            status = "\(result.importedCount) Finder import\(result.importedCount == 1 ? "" : "s") added to the Inbox"
        }
    }

    private static var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
    }

    private static var inboxAccessRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/SortingHat/Finder Inbox Access", directoryHint: .isDirectory)
    }

    private static var outputAccessRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library/Application Support/SortingHat/Filed Output Access", directoryHint: .isDirectory)
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

    private static var legacyQuickActionURL: URL {
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

private struct FinderIntakePass: Sendable {
    let accessState: InboxAccessState
    let pending: [InboxPendingImportRecord]
    let failures: [InboxIngressFailureRecord]
    let invocation: InboxIngressInvocation?
    let queueIssue: String?
    let importedCount: Int
    let deliveryConfirmed: Bool
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
