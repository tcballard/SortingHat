import AppKit
import SortingHatCore
import SortingHatFinderAdapter
import UniformTypeIdentifiers

/// Finder-facing adapter only. Filesystem validation and durable staging remain
/// owned by `InboxImportQueue` in SortingHatCore.
@objc(ActionRequestHandler)
final class ActionRequestHandler: NSObject, NSExtensionRequestHandling, @unchecked Sendable {
    func beginRequest(with context: NSExtensionContext) {
        do {
            let root = try InboxImportQueue.appGroupRoot(bundle: .main)
            FinderActionRequest(context: context, queue: InboxImportQueue(root: root)).start()
        } catch {
            context.cancelRequest(withError: FinderActionError.sharedContainer(error))
        }
    }
}

private final class FinderActionRequest: @unchecked Sendable {
    private let context: NSExtensionContext
    private let originalItems: [NSExtensionItem]
    private let queue: InboxImportQueue
    private let policy: FinderActionBatchPolicy
    private let lock = NSLock()
    private let sequencingQueue = DispatchQueue(label: "com.tcballard.SortingHat.finder-action.providers", qos: .utility)
    private var providers: [NSItemProvider] = []
    private var nextProviderIndex = 0
    private var remaining = 0
    private var stagedIDs: [UUID] = []
    private var failures: [FinderActionFailure] = []
    private var didFinish = false
    private var deadline: DispatchTime?
    private var timeoutWorkItem: DispatchWorkItem?
    private var activeProviderIndex: Int?
    private var activeProgress: Progress?
    private var isHandlingItem = false
    private var expirationRequested = false
    private var acceptedBytes: Int64 = 0

    init(
        context: NSExtensionContext,
        queue: InboxImportQueue,
        policy: FinderActionBatchPolicy = .productDefault
    ) {
        self.context = context
        originalItems = context.inputItems.compactMap { $0 as? NSExtensionItem }
        self.queue = queue
        self.policy = policy
    }

    func start() {
        var providers: [NSItemProvider] = []
        var inputFailures: [FinderActionFailure] = []
        for (index, item) in context.inputItems.enumerated() {
            guard let extensionItem = item as? NSExtensionItem else {
                inputFailures.append(FinderActionFailure(
                    filename: "Finder item \(index + 1)",
                    message: "Finder supplied an unsupported input item. Reselect only this item and try again.",
                    code: .unsupportedItem
                ))
                continue
            }
            guard let attachments = extensionItem.attachments, !attachments.isEmpty else {
                inputFailures.append(FinderActionFailure(
                    filename: extensionItem.attributedTitle?.string ?? "Finder item \(index + 1)",
                    message: "Finder supplied an item without a file attachment. Reselect only this item and try again.",
                    code: .unsupportedItem
                ))
                continue
            }
            providers.append(contentsOf: attachments)
        }

        if providers.count > policy.maximumItems {
            inputFailures.append(FinderActionFailure(
                filename: "Finder selection",
                message: "Send at most \(policy.maximumItems) files at a time. No files from this selection were queued.",
                code: .unsupportedItem
            ))
            providers.removeAll()
        }

        inputFailures.forEach(persist)
        guard !providers.isEmpty else {
            if inputFailures.isEmpty {
                let failure = FinderActionFailure(
                    filename: "Finder selection",
                    message: "Finder didn’t provide any files to send to Sorting Hat.",
                    code: .unsupportedItem
                )
                persist(failure)
                inputFailures.append(failure)
            }
            finish(stagedIDs: [], failures: inputFailures)
            return
        }

        lock.lock()
        self.providers = providers
        remaining = providers.count
        failures = inputFailures
        let requestDeadline = DispatchTime.now() + policy.timeoutSeconds
        deadline = requestDeadline
        let timeout = DispatchWorkItem { [weak self] in self?.expireRequest() }
        timeoutWorkItem = timeout
        lock.unlock()
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: requestDeadline, execute: timeout)
        scheduleNextProvider()
    }

    private func scheduleNextProvider() {
        sequencingQueue.async { [self] in
            lock.lock()
            guard nextProviderIndex < providers.count, !didFinish else {
                lock.unlock()
                return
            }
            let provider = providers[nextProviderIndex]
            let providerIndex = nextProviderIndex
            nextProviderIndex += 1
            activeProviderIndex = providerIndex
            lock.unlock()
            load(provider, at: providerIndex)
        }
    }

    private func load(_ provider: NSItemProvider, at index: Int) {
        let displayName = provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines)
        let filename = displayName?.isEmpty == false ? displayName! : "Selected item"

        if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            loadFileURLData(provider, at: index, displayName: displayName, fallbackName: filename)
            return
        }

        guard let type = preferredFileType(from: provider.registeredTypeIdentifiers) else {
            handleProviderFailure(FinderActionFailure(
                filename: filename,
                message: "Finder provided an item that isn’t a file. Select regular files and try again.",
                code: .unsupportedItem
            ))
            return
        }

        let progress = provider.loadFileRepresentation(for: type, openInPlace: false) { [self] url, _, error in
            guard let url else {
                handleProviderFailure(FinderActionFailure(
                    filename: filename,
                    message: error?.localizedDescription ?? "Finder couldn’t make the selected file available.",
                    code: .providerFailed
                ))
                return
            }
            stage(url, originalFilename: materializedFilename(displayName, from: url, type: type))
        }
        register(progress, for: index)
    }

    private func loadFileURLData(_ provider: NSItemProvider, at index: Int, displayName: String?, fallbackName: String) {
        let progress = FinderItemProviderAdapter.loadFileURL(from: provider) { [self] result in
            switch result {
            case .success(let url):
                stage(url, originalFilename: materializedFilename(displayName, from: url, type: nil))
            case .failure(let error):
                handleProviderFailure(FinderActionFailure(
                    filename: fallbackName,
                    message: error.localizedDescription,
                    code: .providerFailed
                ))
            }
        }
        register(progress, for: index)
    }

    private func materializedFilename(_ suggestedName: String?, from url: URL, type: UTType?) -> String {
        guard let suggestedName, !suggestedName.isEmpty else { return url.lastPathComponent }
        guard URL(fileURLWithPath: suggestedName).pathExtension.isEmpty else { return suggestedName }
        let ext = type?.preferredFilenameExtension ?? url.pathExtension
        return ext.isEmpty ? suggestedName : "\(suggestedName).\(ext)"
    }

    private func preferredFileType(from identifiers: [String]) -> UTType? {
        identifiers.compactMap(UTType.init).first { type in
            type != .fileURL && type.conforms(to: .data) && !type.conforms(to: .directory)
        } ?? identifiers.compactMap(UTType.init).first { type in
            type != .fileURL && type.conforms(to: .item) && !type.conforms(to: .directory)
        }
    }

    private func stage(_ source: URL, originalFilename: String?) {
        guard beginCurrentItemWork() else { return }
        let accessing = source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }

        do {
            let values = try source.resourceValues(forKeys: [.fileSizeKey])
            guard let fileSize = values.fileSize else {
                finishProviderFailure(FinderActionFailure(
                    filename: originalFilename ?? source.lastPathComponent,
                    message: "Finder could not determine this file’s size, so it was not queued. The original was not changed.",
                    code: .providerFailed
                ))
                return
            }
            if let limit = reserve(byteCount: Int64(fileSize)) {
                finishProviderFailure(FinderActionFailure(
                    filename: originalFilename ?? source.lastPathComponent,
                    message: limitMessage(limit),
                    code: .unsupportedItem
                ))
                return
            }
        } catch {
            finishProviderFailure(FinderActionFailure(
                filename: originalFilename ?? source.lastPathComponent,
                message: "Finder could not inspect this file before import: \(error.localizedDescription). The original was not changed.",
                code: .providerFailed
            ))
            return
        }

        var coordinationError: NSError?
        var stagingError: Error?
        var wasStaged = false
        let coordinator = NSFileCoordinator()
        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { coordinatedURL in
            do {
                let queued = try queue.enqueue(
                    coordinatedURL,
                    originalFilename: originalFilename,
                    accessSecurityScope: false
                )
                completeItem(stagedID: queued.id, failure: nil)
                wasStaged = true
            } catch {
                stagingError = error
            }
        }

        if wasStaged { return }

        let error = stagingError ?? coordinationError ?? CocoaError(.fileReadUnknown)
        let issue = error as? InboxImportIssue
        finishProviderFailure(FinderActionFailure(
            filename: originalFilename ?? source.lastPathComponent,
            message: issue?.message ?? error.localizedDescription,
            code: issue?.code ?? .providerFailed
        ))
    }

    private func handleProviderFailure(_ failure: FinderActionFailure) {
        guard beginCurrentItemWork() else { return }
        finishProviderFailure(failure)
    }

    private func finishProviderFailure(_ failure: FinderActionFailure) {
        persist(failure)
        completeItem(stagedID: nil, failure: failure)
    }

    private func persist(_ failure: FinderActionFailure) {
        try? queue.recordFailure(
            filename: failure.filename,
            message: failure.message,
            code: failure.code
        )
    }

    private func completeItem(stagedID: UUID?, failure: FinderActionFailure?) {
        lock.lock()
        if let stagedID { stagedIDs.append(stagedID) }
        if let failure { failures.append(failure) }
        remaining -= 1
        isHandlingItem = false
        activeProgress = nil
        activeProviderIndex = nil
        let shouldFinish = remaining == 0 && !didFinish
        if shouldFinish { didFinish = true }
        let shouldExpire = !shouldFinish && !didFinish && (
            expirationRequested || deadline.map { DispatchTime.now() >= $0 } == true
        )
        let completedIDs = stagedIDs
        let recordedFailures = failures
        lock.unlock()

        if shouldFinish { finish(stagedIDs: completedIDs, failures: recordedFailures) }
        else if shouldExpire { expireRequest() }
        else { scheduleNextProvider() }
    }

    private func beginCurrentItemWork() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !didFinish else { return false }
        isHandlingItem = true
        activeProgress = nil
        return true
    }

    private func register(_ progress: Progress, for index: Int) {
        lock.lock()
        let shouldKeep = !didFinish && !isHandlingItem && activeProviderIndex == index
        if shouldKeep { activeProgress = progress }
        lock.unlock()
        if !shouldKeep { progress.cancel() }
    }

    private func reserve(byteCount: Int64) -> FinderActionBatchLimit? {
        lock.lock()
        defer { lock.unlock() }
        if let limit = policy.limitForFile(byteCount: byteCount, alreadyAccepted: acceptedBytes) {
            return limit
        }
        acceptedBytes += byteCount
        return nil
    }

    private func expireRequest() {
        lock.lock()
        guard !didFinish else {
            lock.unlock()
            return
        }
        if isHandlingItem {
            expirationRequested = true
            lock.unlock()
            return
        }

        didFinish = true
        let firstOutstanding = activeProviderIndex ?? nextProviderIndex
        let unfinishedIndices = firstOutstanding < providers.count
            ? Array(firstOutstanding..<providers.count)
            : []
        let progress = activeProgress
        activeProgress = nil
        activeProviderIndex = nil
        remaining = 0
        let timeoutFailures = unfinishedIndices.map { index in
            let provider = providers[index]
            return FinderActionFailure(
                filename: provider.suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines).nonEmpty
                    ?? "Selected item \(index + 1)",
                message: "Finder’s time limit was reached before this file could be queued. Reselect only this named file; already queued files are safe and originals were not changed.",
                code: .providerFailed
            )
        }
        failures.append(contentsOf: timeoutFailures)
        let completedIDs = stagedIDs
        let recordedFailures = failures
        lock.unlock()

        progress?.cancel()
        timeoutFailures.forEach(persist)
        finish(stagedIDs: completedIDs, failures: recordedFailures)
    }

    private func limitMessage(_ limit: FinderActionBatchLimit) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        switch limit {
        case .unknownFileSize:
            return "Finder could not determine this file’s size, so it was not queued. The original was not changed."
        case .fileTooLarge(let maximumBytes):
            return "This file exceeds the Finder action’s \(formatter.string(fromByteCount: maximumBytes)) per-file safety limit. Add it from inside Sorting Hat instead; the original was not changed."
        case .batchTooLarge(let maximumBytes):
            return "This selection exceeds the Finder action’s \(formatter.string(fromByteCount: maximumBytes)) safety limit. Reselect this file in a smaller batch; already queued files are safe and originals were not changed."
        }
    }

    private func finish(stagedIDs: [UUID], failures: [FinderActionFailure]) {
        timeoutWorkItem?.cancel()
        let build = Bundle.main.object(forInfoDictionaryKey: kCFBundleVersionKey as String) as? String ?? "unknown"
        // Invocation metadata is diagnostic only. Once a payload is durably
        // queued, telemetry failure must not make Finder invite a duplicate
        // retry of an otherwise successful selection.
        try? queue.recordInvocation(stagedIDs: stagedIDs, failures: failures.count, sourceBuild: build)

        if failures.isEmpty {
            // Returning the original extension items tells Finder that this
            // copy-only action did not replace or consume its input files.
            context.completeRequest(returningItems: originalItems, completionHandler: nil)
        } else {
            context.cancelRequest(withError: FinderActionError.partialFailure(failures, staged: stagedIDs.count))
        }
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}

private struct FinderActionFailure: Sendable {
    let filename: String
    let message: String
    let code: InboxImportIssue.Code
}

private struct FinderActionError: LocalizedError, CustomNSError, Sendable {
    static let errorDomain = "com.tcballard.SortingHat.SendToSortingHatAction"

    let errorDescription: String?
    let failureReason: String?
    let recoverySuggestion: String?

    static func sharedContainer(_ error: Error) -> FinderActionError {
        FinderActionError(
            errorDescription: "Send to Sorting Hat isn’t available",
            failureReason: error.localizedDescription,
            recoverySuggestion: "Open Sorting Hat, check Finder Action under Settings > Finder, then try again. Your files were not changed."
        )
    }

    static func partialFailure(_ failures: [FinderActionFailure], staged: Int) -> FinderActionError {
        let details = failures.prefix(3).map { "\($0.filename): \($0.message)" }.joined(separator: "\n")
        let remaining = failures.count - min(failures.count, 3)
        let suffix = remaining > 0 ? "\n…and \(remaining) more." : ""
        return FinderActionError(
            errorDescription: failures.count == 1 ? "A file couldn’t be sent to Sorting Hat" : "Some files couldn’t be sent to Sorting Hat",
            failureReason: details + suffix,
            recoverySuggestion: staged > 0
                ? "\(staged) file\(staged == 1 ? " was" : "s were") safely queued. Reselect only the named failed file\(failures.count == 1 ? "" : "s"); selecting the whole batch again would duplicate successful imports. Your originals were not changed."
                : "Reselect only the named failed file\(failures.count == 1 ? "" : "s") after checking Finder Action in Sorting Hat Settings. Your originals were not changed."
        )
    }
}
