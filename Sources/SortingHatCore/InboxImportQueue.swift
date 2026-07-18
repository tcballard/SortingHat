import Darwin
import Foundation
import SortingHatQueueLock

public struct InboxImportQueue: @unchecked Sendable {
    public static let appGroupInfoKey = "SortingHatAppGroupIdentifier"

    private let root: URL
    private let fileManager: FileManager
    private let importer: InboxImportService
    private let beforePayloadCopy: (@Sendable () -> Void)?
    private let beforeInboxCopy: (@Sendable () -> Void)?
    private let beforeReceiptWrite: (@Sendable () throws -> Void)?

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        importer = InboxImportService(fileManager: fileManager)
        beforePayloadCopy = nil
        beforeInboxCopy = nil
        beforeReceiptWrite = nil
    }

    init(
        root: URL,
        fileManager: FileManager = .default,
        beforePayloadCopy: @escaping @Sendable () -> Void
    ) {
        self.root = root
        self.fileManager = fileManager
        importer = InboxImportService(fileManager: fileManager)
        self.beforePayloadCopy = beforePayloadCopy
        beforeInboxCopy = nil
        beforeReceiptWrite = nil
    }

    init(
        root: URL,
        fileManager: FileManager = .default,
        beforeInboxCopy: @escaping @Sendable () -> Void
    ) {
        self.root = root
        self.fileManager = fileManager
        importer = InboxImportService(fileManager: fileManager)
        beforePayloadCopy = nil
        self.beforeInboxCopy = beforeInboxCopy
        beforeReceiptWrite = nil
    }

    init(
        root: URL,
        fileManager: FileManager = .default,
        beforeReceiptWrite: @escaping @Sendable () throws -> Void
    ) {
        self.root = root
        self.fileManager = fileManager
        importer = InboxImportService(fileManager: fileManager)
        beforePayloadCopy = nil
        beforeInboxCopy = nil
        self.beforeReceiptWrite = beforeReceiptWrite
    }

    public static func appGroupRoot(
        bundle: Bundle = .main,
        fileManager: FileManager = .default
    ) throws -> URL {
        guard let identifier = bundle.object(forInfoDictionaryKey: appGroupInfoKey) as? String,
              !identifier.isEmpty,
              let container = fileManager.containerURL(forSecurityApplicationGroupIdentifier: identifier) else {
            throw InboxImportIssue(
                code: .sharedContainerUnavailable,
                filename: "",
                message: "Sorting Hat’s shared Finder intake container is unavailable. Reinstall the signed app."
            )
        }
        do {
            try fileManager.createDirectory(at: container, withIntermediateDirectories: true)
            return container.appending(path: "Finder Intake", directoryHint: .isDirectory)
        } catch {
            throw InboxImportIssue(code: .sharedContainerUnavailable, filename: "", message: error.localizedDescription)
        }
    }

    @discardableResult
    public func enqueue(
        _ source: URL,
        originalFilename: String? = nil,
        id: UUID = UUID(),
        accessSecurityScope: Bool = true,
        date: Date = .now
    ) throws -> QueuedInboxImport {
        try withQueueLock {
            try enqueueWhileLocked(
                source,
                originalFilename: originalFilename,
                id: id,
                accessSecurityScope: accessSecurityScope,
                date: date
            )
        }
    }

    private func enqueueWhileLocked(
        _ source: URL,
        originalFilename: String?,
        id: UUID,
        accessSecurityScope: Bool,
        date: Date
    ) throws -> QueuedInboxImport {
        try prepareDirectories()
        try recoverInterruptedStaging()
        let accessing = accessSecurityScope && source.startAccessingSecurityScopedResource()
        defer { if accessing { source.stopAccessingSecurityScopedResource() } }
        let filename = originalFilename ?? source.lastPathComponent
        try importer.validateMaterializedFile(source)
        try InboxImportService.validateUserFacingFilename(filename)

        if let receipt = try loadReceipt(id: id) {
            let sourceFingerprint = try InboxImportService.fingerprint(of: source)
            guard receipt.id == id,
                  receipt.originalFilename == filename,
                  receipt.fingerprint == sourceFingerprint else {
                throw InboxImportIssue(
                    code: .corruptQueueItem,
                    filename: filename,
                    message: "This Finder item reused an identifier that belongs to a different delivered file. The original was not changed."
                )
            }
            return QueuedInboxImport(id: id, filename: receipt.destinationName, wasAlreadyQueued: true)
        }

        let pending = pendingDirectory(id)
        if fileManager.fileExists(atPath: pending.path) {
            let manifest = try loadManifest(from: pending)
            let sourceFingerprint = try InboxImportService.fingerprint(of: source)
            guard manifest.id == id,
                  manifest.originalFilename == filename,
                  manifest.fingerprint == sourceFingerprint else {
                throw InboxImportIssue(
                    code: .corruptQueueItem,
                    filename: filename,
                    message: "This Finder item reused an identifier that belongs to a different staged file. Both originals were left unchanged."
                )
            }
            return QueuedInboxImport(id: id, filename: manifest.originalFilename, wasAlreadyQueued: true)
        }

        let staging = stagingDirectory(id)
        var createdStaging = false
        do {
            try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
            createdStaging = true
            try write(
                StagingRecord(id: id, originalFilename: filename, enqueuedAt: date),
                to: staging.appending(path: "staging.json")
            )
            let partialPayload = staging.appending(path: "payload.partial")
            let payload = staging.appending(path: "payload")
            beforePayloadCopy?()
            try fileManager.copyItem(at: source, to: partialPayload)
            try fileManager.moveItem(at: partialPayload, to: payload)
            let fingerprint = try InboxImportService.fingerprint(of: payload)
            let manifest = QueueManifest(
                id: id,
                originalFilename: filename,
                enqueuedAt: date,
                fingerprint: fingerprint,
                state: .staged,
                temporaryName: nil,
                destinationName: nil,
                attempts: 0,
                lastError: nil,
                lastErrorCode: nil
            )
            try write(manifest, to: staging.appending(path: "manifest.json"))
            try fileManager.moveItem(at: staging, to: pending)
            return QueuedInboxImport(id: id, filename: filename, wasAlreadyQueued: false)
        } catch {
            // Never remove a same-ID staging directory created by another
            // invocation. This process owns it only after createDirectory
            // succeeds.
            if createdStaging { try? fileManager.removeItem(at: staging) }
            throw error
        }
    }

    public func drain(to inbox: URL) -> InboxQueueDrainReport {
        do {
            return try withDrainLock { try drainExclusively(to: inbox) }
        } catch let issue as InboxImportIssue {
            return InboxQueueDrainReport(results: [], queueIssues: [issue])
        } catch {
            let issue = InboxImportIssue(
                code: .sharedContainerUnavailable,
                filename: "",
                message: "Sorting Hat could not coordinate its Finder intake queue: \(error.localizedDescription)"
            )
            return InboxQueueDrainReport(results: [], queueIssues: [issue])
        }
    }

    private func drainExclusively(to inbox: URL) throws -> InboxQueueDrainReport {
        do {
            try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
        } catch {
            throw InboxImportIssue(code: .inboxUnavailable, filename: "", message: error.localizedDescription)
        }

        let directories = try withQueueLock {
            try prepareDirectories()
            try recoverInterruptedStaging()
            do {
                return try fileManager.contentsOfDirectory(
                    at: pendingRoot,
                    includingPropertiesForKeys: [.isDirectoryKey],
                    options: [.skipsHiddenFiles]
                ).sorted { $0.lastPathComponent < $1.lastPathComponent }
            } catch {
                throw InboxImportIssue(code: .sharedContainerUnavailable, filename: "", message: error.localizedDescription)
            }
        }

        var results: [InboxQueueDrainResult] = []
        var issues: [InboxImportIssue] = []
        for directory in directories {
            do {
                let existing = try loadManifest(from: directory)
                if let message = existing.lastError {
                    issues.append(InboxImportIssue(
                        code: existing.lastErrorCode ?? .corruptQueueItem,
                        filename: existing.originalFilename,
                        message: message
                    ))
                    continue
                }
                if let result = try drain(directory, to: inbox) { results.append(result) }
            } catch let issue as InboxImportIssue {
                issues.append(issue)
                try? withQueueLock { try updateFailure(issue, in: directory) }
            } catch {
                let issue = InboxImportIssue(code: .corruptQueueItem, filename: directory.lastPathComponent, message: error.localizedDescription)
                issues.append(issue)
                try? withQueueLock { try updateFailure(issue, in: directory) }
            }
        }
        return InboxQueueDrainReport(results: results, queueIssues: issues)
    }

    public func pendingCount() -> Int {
        (try? withDrainLock { try withQueueLock { pendingCountWhileLocked() } }) ?? 0
    }

    private func pendingCountWhileLocked() -> Int {
        try? prepareDirectories()
        try? recoverInterruptedStaging()
        return (try? fileManager.contentsOfDirectory(at: pendingRoot, includingPropertiesForKeys: nil).count) ?? 0
    }

    public func pendingImports() -> [InboxPendingImportRecord] {
        (try? withDrainLock { try withQueueLock { pendingImportsWhileLocked() } }) ?? []
    }

    private func pendingImportsWhileLocked() -> [InboxPendingImportRecord] {
        try? prepareDirectories()
        try? recoverInterruptedStaging()
        guard let urls = try? fileManager.contentsOfDirectory(
            at: pendingRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { url -> InboxPendingImportRecord? in
            guard let manifest = try? loadManifest(from: url) else {
                return InboxPendingImportRecord(
                    id: UUID(uuidString: url.lastPathComponent) ?? UUID(),
                    filename: url.lastPathComponent,
                    enqueuedAt: .distantPast,
                    attempts: 0,
                    lastError: "The queue manifest is unreadable. Remove this staged item and reselect the original file."
                )
            }
            return InboxPendingImportRecord(
                id: manifest.id,
                filename: manifest.originalFilename,
                enqueuedAt: manifest.enqueuedAt,
                attempts: manifest.attempts,
                lastError: manifest.lastError
            )
        }.sorted { $0.enqueuedAt < $1.enqueuedAt }
    }

    public func retryPending(id: UUID, in inbox: URL) throws {
        try withDrainLock {
            let snapshot = try withQueueLock { try loadManifest(from: pendingDirectory(id)) }
            let canResumeCommit = try readyCommitCanResume(snapshot, in: inbox)
            if !canResumeCommit {
                for name in retryCleanupNames(snapshot) {
                    let candidate = inbox.appending(path: name)
                    if fileManager.fileExists(atPath: candidate.path) {
                        try fileManager.removeItem(at: candidate)
                    }
                }
            }
            try withQueueLock {
                try preparePendingForRetryWhileQueueLocked(id: id, preservingReadyCommit: canResumeCommit)
            }
        }
    }

    private func retryCleanupNames(_ manifest: QueueManifest) -> [String] {
        let id = manifest.id
        return Set([
            manifest.temporaryName,
            ".sortinghat-import-\(id.uuidString)",
            ".sortinghat-import-\(id.uuidString).partial"
        ].compactMap { name in
            guard let name, name.hasPrefix(".sortinghat-import-\(id.uuidString)") else { return nil }
            return name
        }).sorted()
    }

    private func readyCommitCanResume(_ manifest: QueueManifest, in inbox: URL) throws -> Bool {
        if manifest.state == .deliveredPendingReceipt { return true }
        guard manifest.state == .readyToCommit else { return false }
        for name in [manifest.temporaryName, manifest.destinationName].compactMap({ $0 }) {
            let candidate = inbox.appending(path: name)
            if fileManager.fileExists(atPath: candidate.path),
               try InboxImportService.fingerprint(of: candidate) == manifest.fingerprint {
                return true
            }
        }
        return false
    }

    private func preparePendingForRetryWhileQueueLocked(id: UUID, preservingReadyCommit: Bool) throws {
        let directory = pendingDirectory(id)
        var manifest = try loadManifest(from: directory)
        if !(preservingReadyCommit && (manifest.state == .readyToCommit || manifest.state == .deliveredPendingReceipt)) {
            manifest.state = .staged
            manifest.temporaryName = nil
            manifest.destinationName = nil
        }
        manifest.lastError = nil
        manifest.lastErrorCode = nil
        try saveManifest(manifest, in: directory)
    }

    public func removePending(id: UUID) throws {
        try withDrainLock {
            try withQueueLock { try removePendingWhileLocked(id: id) }
        }
    }

    private func removePendingWhileLocked(id: UUID) throws {
        let directory = pendingDirectory(id)
        guard fileManager.fileExists(atPath: directory.path) else { return }
        try fileManager.removeItem(at: directory)
    }

    public func failures() -> [InboxIngressFailureRecord] {
        failuresWhileLocked()
    }

    private func failuresWhileLocked() -> [InboxIngressFailureRecord] {
        guard let urls = try? fileManager.contentsOfDirectory(
            at: failureRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return [] }
        return urls.compactMap { try? decode(InboxIngressFailureRecord.self, from: $0) }
            .sorted { $0.date > $1.date }
    }

    public func recordFailure(
        filename: String,
        message: String,
        code: InboxImportIssue.Code = .providerFailed,
        date: Date = .now
    ) throws {
        // Diagnostic records use unique names and atomic writes. Keeping them
        // off the ingress lock prevents Finder completion from waiting behind
        // another extension's large payload copy.
        try recordFailureWhileLocked(filename: filename, message: message, code: code, date: date)
    }

    private func recordFailureWhileLocked(
        filename: String,
        message: String,
        code: InboxImportIssue.Code,
        date: Date = .now
    ) throws {
        try prepareDirectories()
        let record = InboxIngressFailureRecord(id: UUID(), filename: filename, message: message, code: code, date: date)
        try write(record, to: failureRoot.appending(path: "\(record.id.uuidString).json"))
    }

    public func removeFailure(id: UUID) throws {
        try removeFailureWhileLocked(id: id)
    }

    private func removeFailureWhileLocked(id: UUID) throws {
        let url = failureRoot.appending(path: "\(id.uuidString).json")
        if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
    }

    public func recordInvocation(
        stagedIDs: [UUID],
        failures: Int,
        sourceBuild: String,
        date: Date = .now
    ) throws {
        try recordInvocationWhileLocked(
            stagedIDs: stagedIDs,
            failures: failures,
            sourceBuild: sourceBuild,
            date: date
        )
    }

    private func recordInvocationWhileLocked(
        stagedIDs: [UUID],
        failures: Int,
        sourceBuild: String,
        date: Date
    ) throws {
        try prepareDirectories()
        let invocation = InboxIngressInvocation(
            id: UUID(),
            date: date,
            staged: stagedIDs.count,
            stagedIDs: stagedIDs,
            failures: failures,
            sourceBuild: sourceBuild
        )
        try write(
            invocation,
            to: invocationRoot.appending(path: "\(invocation.id.uuidString).json")
        )
    }

    public func lastInvocation() -> InboxIngressInvocation? {
        lastInvocationWhileLocked()
    }

    private func lastInvocationWhileLocked() -> InboxIngressInvocation? {
        let immutable = (try? fileManager.contentsOfDirectory(
            at: invocationRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.compactMap { try? decode(InboxIngressInvocation.self, from: $0) }
            .sorted { $0.date > $1.date }
            .first
        return immutable ?? (try? decode(InboxIngressInvocation.self, from: root.appending(path: "last-invocation.json")))
    }

    public func confirmedInvocation(to inbox: URL, currentBuild: String) -> InboxIngressInvocation? {
        try? withDrainLock {
            try withQueueLock { confirmedInvocationWhileLocked(to: inbox, currentBuild: currentBuild) }
        }
    }

    private func confirmedInvocationWhileLocked(to inbox: URL, currentBuild: String) -> InboxIngressInvocation? {
        let invocations = (try? fileManager.contentsOfDirectory(
            at: invocationRoot,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ))?.compactMap { try? decode(InboxIngressInvocation.self, from: $0) }
            .sorted { $0.date > $1.date } ?? []
        return invocations.first { deliveriesConfirmedWhileLocked(for: $0, to: inbox, currentBuild: currentBuild) }
    }

    public func deliveriesConfirmed(
        for invocation: InboxIngressInvocation,
        to inbox: URL,
        currentBuild: String
    ) -> Bool {
        (try? withDrainLock {
            try withQueueLock {
                deliveriesConfirmedWhileLocked(for: invocation, to: inbox, currentBuild: currentBuild)
            }
        }) ?? false
    }

    private func deliveriesConfirmedWhileLocked(
        for invocation: InboxIngressInvocation,
        to inbox: URL,
        currentBuild: String
    ) -> Bool {
        guard invocation.failures == 0,
              invocation.sourceBuild == currentBuild,
              !invocation.stagedIDs.isEmpty,
              pendingCountWhileLocked() == 0 else { return false }
        let expectedPath = inbox.standardizedFileURL.path(percentEncoded: false)
        return invocation.stagedIDs.allSatisfy { id in
            guard let receipt = try? loadReceipt(id: id) else { return false }
            return receipt.inboxPath == expectedPath
        }
    }

    private func drain(_ directory: URL, to inbox: URL) throws -> InboxQueueDrainResult? {
        var manifest = try loadManifest(from: directory)
        if let delivered = try withQueueLock({ try finishPreviouslyDelivered(manifest, directory: directory) }) {
            return delivered
        }

        let payload = directory.appending(path: "payload")
        guard fileManager.fileExists(atPath: payload.path),
              try InboxImportService.fingerprint(of: payload) == manifest.fingerprint else {
            throw InboxImportIssue(
                code: .corruptQueueItem,
                filename: manifest.originalFilename,
                message: "The staged copy is missing or changed. It remains queued for recovery."
            )
        }

        if manifest.state == .staged {
            let temporaryName = ".sortinghat-import-\(manifest.id.uuidString)"
            let temporary = inbox.appending(path: temporaryName)
            let partial = inbox.appending(path: "\(temporaryName).partial")
            if fileManager.fileExists(atPath: partial.path) {
                try fileManager.removeItem(at: partial)
            }
            if fileManager.fileExists(atPath: temporary.path) {
                if try InboxImportService.fingerprint(of: temporary) != manifest.fingerprint {
                    // This UUID-scoped hidden name belongs only to this queue
                    // item. A mismatch is an interrupted prior copy, so the
                    // authoritative App Group payload can safely replace it.
                    try fileManager.removeItem(at: temporary)
                }
            }
            if !fileManager.fileExists(atPath: temporary.path) {
                beforeInboxCopy?()
                try fileManager.copyItem(at: payload, to: partial)
                guard try InboxImportService.fingerprint(of: partial) == manifest.fingerprint else {
                    try? fileManager.removeItem(at: partial)
                    throw InboxImportIssue(
                        code: .corruptQueueItem,
                        filename: manifest.originalFilename,
                        message: "The Inbox copy could not be verified. The staged source remains available for retry."
                    )
                }
                try fileManager.moveItem(at: partial, to: temporary)
            }
            manifest.state = .readyToCommit
            manifest.temporaryName = temporaryName
            manifest.destinationName = availableName(for: manifest.originalFilename, in: inbox)
            manifest.attempts += 1
            manifest.lastError = nil
            manifest.lastErrorCode = nil
            try saveManifest(manifest, in: directory)
        }

        guard let temporaryName = manifest.temporaryName,
              var destinationName = manifest.destinationName else {
            throw InboxImportIssue(code: .corruptQueueItem, filename: manifest.originalFilename, message: "The queue manifest is incomplete.")
        }
        let temporary = inbox.appending(path: temporaryName)

        if !fileManager.fileExists(atPath: temporary.path) {
            let destination = inbox.appending(path: destinationName)
            if manifest.state == .deliveredPendingReceipt {
                try complete(manifest, destinationName: destinationName, inbox: inbox, directory: directory)
                return .imported(id: manifest.id, destination: destination)
            }
            guard fileManager.fileExists(atPath: destination.path),
                  try InboxImportService.fingerprint(of: destination) == manifest.fingerprint else {
                throw InboxImportIssue(
                    code: .commitStateLost,
                    filename: manifest.originalFilename,
                    message: "The staged handoff could not be proven complete. Sorting Hat kept the queued copy for recovery."
                )
            }
            try complete(manifest, destinationName: destinationName, inbox: inbox, directory: directory)
            return .imported(id: manifest.id, destination: destination)
        }

        for _ in 0..<9_999 {
            let destination = inbox.appending(path: destinationName)
            do {
                try fileManager.moveItem(at: temporary, to: destination)
                manifest.state = .deliveredPendingReceipt
                manifest.destinationName = destinationName
                try saveManifest(manifest, in: directory)
                try complete(manifest, destinationName: destinationName, inbox: inbox, directory: directory)
                return .imported(id: manifest.id, destination: destination)
            } catch where InboxImportService.isFileExists(error) {
                destinationName = availableName(for: manifest.originalFilename, in: inbox, after: destinationName)
                manifest.destinationName = destinationName
                manifest.attempts += 1
                try saveManifest(manifest, in: directory)
            }
        }

        throw InboxImportIssue(
            code: .noAvailableName,
            filename: manifest.originalFilename,
            message: "Sorting Hat couldn’t reserve a collision-free Inbox filename."
        )
    }

    private func complete(_ manifest: QueueManifest, destinationName: String, inbox: URL, directory: URL) throws {
        try withQueueLock {
            try completeWhileQueueLocked(
                manifest,
                destinationName: destinationName,
                inbox: inbox,
                directory: directory
            )
        }
    }

    private func completeWhileQueueLocked(
        _ manifest: QueueManifest,
        destinationName: String,
        inbox: URL,
        directory: URL
    ) throws {
        try beforeReceiptWrite?()
        let receipt = QueueReceipt(
            id: manifest.id,
            destinationName: destinationName,
            originalFilename: manifest.originalFilename,
            inboxPath: inbox.standardizedFileURL.path(percentEncoded: false),
            deliveredAt: .now,
            fingerprint: manifest.fingerprint
        )
        try write(receipt, to: receiptURL(manifest.id))
        try fileManager.removeItem(at: directory)
    }

    private func finishPreviouslyDelivered(
        _ manifest: QueueManifest,
        directory: URL
    ) throws -> InboxQueueDrainResult? {
        guard let receipt = try loadReceipt(id: manifest.id) else { return nil }
        guard receipt.id == manifest.id,
              receipt.originalFilename == manifest.originalFilename,
              receipt.fingerprint == manifest.fingerprint else {
            throw InboxImportIssue(
                code: .corruptQueueItem,
                filename: manifest.originalFilename,
                message: "The delivery receipt does not match this staged file. Sorting Hat retained the staged copy for recovery."
            )
        }
        try fileManager.removeItem(at: directory)
        return .alreadyDelivered(
            id: manifest.id,
            destination: URL(fileURLWithPath: receipt.inboxPath, isDirectory: true)
                .appending(path: receipt.destinationName)
        )
    }

    private func availableName(for preferredName: String, in inbox: URL, after previous: String? = nil) -> String {
        let url = URL(fileURLWithPath: preferredName)
        let stem = url.deletingPathExtension().lastPathComponent
        let ext = url.pathExtension
        var start = 1
        if let previous, previous != preferredName {
            let previousStem = URL(fileURLWithPath: previous).deletingPathExtension().lastPathComponent
            if let suffix = previousStem.split(separator: "-").last.flatMap({ Int($0) }) { start = suffix + 1 }
        }
        for index in start...9_999 {
            let name = index == 1 ? preferredName : (ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)")
            if !fileManager.fileExists(atPath: inbox.appending(path: name).path) { return name }
        }
        return "\(UUID().uuidString)-\(preferredName)"
    }

    private func updateFailure(_ issue: InboxImportIssue, in directory: URL) throws {
        var manifest = try loadManifest(from: directory)
        manifest.attempts += 1
        manifest.lastError = issue.message
        manifest.lastErrorCode = issue.code
        try saveManifest(manifest, in: directory)
    }

    private func recoverInterruptedStaging() throws {
        let directories = try fileManager.contentsOfDirectory(
            at: stagingRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        for directory in directories {
            do {
                let record = try decode(StagingRecord.self, from: directory.appending(path: "staging.json"))
                let payload = directory.appending(path: "payload")
                let manifest: QueueManifest
                if let existing = try? loadManifest(from: directory) {
                    manifest = existing
                } else if fileManager.fileExists(atPath: payload.path) {
                    manifest = QueueManifest(
                        id: record.id,
                        originalFilename: record.originalFilename,
                        enqueuedAt: record.enqueuedAt,
                        fingerprint: try InboxImportService.fingerprint(of: payload),
                        state: .staged,
                        temporaryName: nil,
                        destinationName: nil,
                        attempts: 0,
                        lastError: nil,
                        lastErrorCode: nil
                    )
                    try saveManifest(manifest, in: directory)
                } else {
                    throw InboxImportIssue(
                        code: .providerFailed,
                        filename: record.originalFilename,
                        message: "Finder intake was interrupted before a complete staged copy was available. Reselect only this file; the original was not changed."
                    )
                }

                guard fileManager.fileExists(atPath: payload.path),
                      try InboxImportService.fingerprint(of: payload) == manifest.fingerprint else {
                    throw InboxImportIssue(
                        code: .corruptQueueItem,
                        filename: record.originalFilename,
                        message: "Finder intake was interrupted and the staged copy could not be verified. Reselect only this file; the original was not changed."
                    )
                }

                if let receipt = try loadReceipt(id: record.id) {
                    guard receipt.id == manifest.id,
                          receipt.originalFilename == manifest.originalFilename,
                          receipt.fingerprint == manifest.fingerprint else {
                        throw InboxImportIssue(
                            code: .corruptQueueItem,
                            filename: record.originalFilename,
                            message: "An interrupted staged file has a conflicting delivery receipt. Both records were retained for recovery."
                        )
                    }
                    try fileManager.removeItem(at: directory)
                    continue
                }

                let pending = pendingDirectory(record.id)
                if fileManager.fileExists(atPath: pending.path) {
                    let pendingManifest = try loadManifest(from: pending)
                    guard pendingManifest.fingerprint == manifest.fingerprint else {
                        throw InboxImportIssue(
                            code: .corruptQueueItem,
                            filename: record.originalFilename,
                            message: "Two staged Finder items unexpectedly shared an identifier. Both copies were retained for recovery."
                        )
                    }
                    try fileManager.removeItem(at: directory)
                } else {
                    try fileManager.moveItem(at: directory, to: pending)
                }
            } catch let issue as InboxImportIssue {
                try quarantine(directory, issue: issue)
            } catch {
                let filename = (try? decode(StagingRecord.self, from: directory.appending(path: "staging.json")))?.originalFilename
                    ?? directory.lastPathComponent
                try quarantine(directory, issue: InboxImportIssue(
                    code: .corruptQueueItem,
                    filename: filename,
                    message: "Finder intake was interrupted and needs attention: \(error.localizedDescription)"
                ))
            }
        }
    }

    private func quarantine(_ directory: URL, issue: InboxImportIssue) throws {
        let destination = quarantineRoot.appending(path: "\(directory.lastPathComponent)-\(UUID().uuidString)", directoryHint: .isDirectory)
        try fileManager.moveItem(at: directory, to: destination)
        try recordFailureWhileLocked(filename: issue.filename, message: issue.message, code: issue.code)
    }

    private func withQueueLock<T>(_ operation: () throws -> T) throws -> T {
        try withFileLock(named: ".queue.lock", operation)
    }

    private func withDrainLock<T>(_ operation: () throws -> T) throws -> T {
        try withFileLock(named: ".drain.lock", operation)
    }

    /// Kernel-released advisory locks coordinate the host and every extension
    /// process without leaving a stale lock behind after a crash.
    private func withFileLock<T>(named name: String, _ operation: () throws -> T) throws -> T {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let lockURL = root.appending(path: name)
        let descriptor = Darwin.open(
            lockURL.path,
            O_CREAT | O_RDWR,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            let code = errno
            throw InboxImportIssue(
                code: .sharedContainerUnavailable,
                filename: "",
                message: "The Finder intake lock could not be opened: \(String(cString: Darwin.strerror(code)))."
            )
        }

        let result = sortinghat_queue_lock(descriptor)

        guard result == 0 else {
            let code = errno
            Darwin.close(descriptor)
            throw InboxImportIssue(
                code: .sharedContainerUnavailable,
                filename: "",
                message: "The Finder intake lock could not be acquired: \(String(cString: Darwin.strerror(code)))."
            )
        }

        defer {
            _ = sortinghat_queue_unlock(descriptor)
            Darwin.close(descriptor)
        }
        return try operation()
    }

    private func prepareDirectories() throws {
        for directory in [root, stagingRoot, pendingRoot, receiptRoot, failureRoot, quarantineRoot, invocationRoot] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private var stagingRoot: URL { root.appending(path: ".staging", directoryHint: .isDirectory) }
    private var pendingRoot: URL { root.appending(path: "Pending", directoryHint: .isDirectory) }
    private var receiptRoot: URL { root.appending(path: "Receipts", directoryHint: .isDirectory) }
    private var failureRoot: URL { root.appending(path: "Failures", directoryHint: .isDirectory) }
    private var quarantineRoot: URL { root.appending(path: "Quarantine", directoryHint: .isDirectory) }
    private var invocationRoot: URL { root.appending(path: "Invocations", directoryHint: .isDirectory) }
    private func stagingDirectory(_ id: UUID) -> URL { stagingRoot.appending(path: id.uuidString, directoryHint: .isDirectory) }
    private func pendingDirectory(_ id: UUID) -> URL { pendingRoot.appending(path: id.uuidString, directoryHint: .isDirectory) }
    private func receiptURL(_ id: UUID) -> URL { receiptRoot.appending(path: "\(id.uuidString).json") }

    private func loadManifest(from directory: URL) throws -> QueueManifest {
        try decode(QueueManifest.self, from: directory.appending(path: "manifest.json"))
    }

    private func saveManifest(_ manifest: QueueManifest, in directory: URL) throws {
        try write(manifest, to: directory.appending(path: "manifest.json"))
    }

    private func loadReceipt(id: UUID) throws -> QueueReceipt? {
        let url = receiptURL(id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return try decode(QueueReceipt.self, from: url)
    }

    private func write<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(value).write(to: url, options: .atomic)
    }

    private func decode<T: Decodable>(_ type: T.Type, from url: URL) throws -> T {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(type, from: Data(contentsOf: url))
    }
}

public struct QueuedInboxImport: Equatable, Sendable {
    public let id: UUID
    public let filename: String
    public let wasAlreadyQueued: Bool
}

public struct InboxQueueDrainReport: Equatable, Sendable {
    public let results: [InboxQueueDrainResult]
    public let queueIssues: [InboxImportIssue]

    public init(results: [InboxQueueDrainResult], queueIssues: [InboxImportIssue]) {
        self.results = results
        self.queueIssues = queueIssues
    }
}

public enum InboxQueueDrainResult: Equatable, Sendable {
    case imported(id: UUID, destination: URL)
    case alreadyDelivered(id: UUID, destination: URL)
}

public struct InboxIngressFailureRecord: Codable, Equatable, Identifiable, Sendable {
    public let id: UUID
    public let filename: String
    public let message: String
    public let code: InboxImportIssue.Code
    public let date: Date
}

public struct InboxIngressInvocation: Codable, Equatable, Sendable {
    public let id: UUID
    public let date: Date
    public let staged: Int
    public let stagedIDs: [UUID]
    public let failures: Int
    public let sourceBuild: String

    public init(id: UUID = UUID(), date: Date, staged: Int, stagedIDs: [UUID], failures: Int, sourceBuild: String) {
        self.id = id
        self.date = date
        self.staged = staged
        self.stagedIDs = stagedIDs
        self.failures = failures
        self.sourceBuild = sourceBuild
    }

    private enum CodingKeys: String, CodingKey { case id, date, staged, stagedIDs, failures, sourceBuild }

    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        date = try values.decode(Date.self, forKey: .date)
        staged = try values.decode(Int.self, forKey: .staged)
        stagedIDs = try values.decodeIfPresent([UUID].self, forKey: .stagedIDs) ?? []
        failures = try values.decode(Int.self, forKey: .failures)
        sourceBuild = try values.decodeIfPresent(String.self, forKey: .sourceBuild) ?? "legacy"
    }
}

private struct QueueManifest: Codable {
    enum State: String, Codable { case staged, readyToCommit, deliveredPendingReceipt }

    let id: UUID
    let originalFilename: String
    let enqueuedAt: Date
    let fingerprint: FileFingerprint
    var state: State
    var temporaryName: String?
    var destinationName: String?
    var attempts: Int
    var lastError: String?
    var lastErrorCode: InboxImportIssue.Code?
}

private struct StagingRecord: Codable {
    let id: UUID
    let originalFilename: String
    let enqueuedAt: Date
}

private struct QueueReceipt: Codable {
    let id: UUID
    let destinationName: String
    let originalFilename: String
    let inboxPath: String
    let deliveredAt: Date
    let fingerprint: FileFingerprint
}

public struct InboxPendingImportRecord: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let filename: String
    public let enqueuedAt: Date
    public let attempts: Int
    public let lastError: String?

    public init(id: UUID, filename: String, enqueuedAt: Date, attempts: Int, lastError: String?) {
        self.id = id
        self.filename = filename
        self.enqueuedAt = enqueuedAt
        self.attempts = attempts
        self.lastError = lastError
    }
}
