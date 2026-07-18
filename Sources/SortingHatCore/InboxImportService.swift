import CryptoKit
import Foundation

public struct InboxImportService {
    private let fileManager: FileManager
    private let beforeCopy: ((URL, URL) throws -> Void)?

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        beforeCopy = nil
    }

    init(fileManager: FileManager = .default, beforeCopy: @escaping (URL, URL) throws -> Void) {
        self.fileManager = fileManager
        self.beforeCopy = beforeCopy
    }

    public func importFiles(
        _ sources: [URL],
        to inbox: URL,
        accessSecurityScope: Bool = true
    ) -> InboxImportBatch {
        do {
            try fileManager.createDirectory(at: inbox, withIntermediateDirectories: true)
        } catch {
            return InboxImportBatch(results: sources.map {
                .failed(source: $0, issue: .init(code: .inboxUnavailable, filename: $0.lastPathComponent, message: error.localizedDescription))
            })
        }

        return InboxImportBatch(results: sources.map { source in
            let accessing = accessSecurityScope && source.startAccessingSecurityScopedResource()
            defer { if accessing { source.stopAccessingSecurityScopedResource() } }

            do {
                try validate(source)
                if source.deletingLastPathComponent().standardizedFileURL == inbox.standardizedFileURL {
                    return .alreadyInInbox(source: source)
                }
                let destination = try copy(source, preferredName: source.lastPathComponent, to: inbox)
                return .imported(source: source, destination: destination)
            } catch let issue as InboxImportIssue {
                return .failed(source: source, issue: issue)
            } catch {
                return .failed(source: source, issue: .init(
                    code: .copyFailed,
                    filename: source.lastPathComponent,
                    message: error.localizedDescription
                ))
            }
        })
    }

    func validate(_ source: URL) throws {
        try validateMaterializedFile(source)
        try Self.validateUserFacingFilename(source.lastPathComponent)
    }

    func validateMaterializedFile(_ source: URL) throws {
        let values = try source.resourceValues(forKeys: [.isRegularFileKey])
        guard values.isRegularFile == true else {
            throw InboxImportIssue(
                code: .unsupportedItem,
                filename: source.lastPathComponent,
                message: "Only files can be sent to Sorting Hat. Folders and other items aren’t imported."
            )
        }
    }

    static func validateUserFacingFilename(_ name: String) throws {
        guard !name.hasPrefix(".") else {
            throw InboxImportIssue(
                code: .unsupportedItem,
                filename: name,
                message: "Hidden files aren’t imported because the Inbox intentionally ignores them."
            )
        }
        try validateFilename(name)
    }

    func copy(_ source: URL, preferredName: String, to inbox: URL) throws -> URL {
        try Self.validateFilename(preferredName)
        let candidate = URL(fileURLWithPath: preferredName)
        let stem = candidate.deletingPathExtension().lastPathComponent
        let ext = candidate.pathExtension

        for index in 1...9_999 {
            let name: String
            if index == 1 { name = preferredName }
            else { name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)" }
            let destination = inbox.appending(path: name)
            guard destination.standardizedFileURL != source.standardizedFileURL else { continue }

            do {
                try beforeCopy?(source, destination)
                try fileManager.copyItem(at: source, to: destination)
                return destination
            } catch where Self.isFileExists(error) {
                continue
            } catch let issue as InboxImportIssue {
                throw issue
            } catch {
                throw InboxImportIssue(code: .copyFailed, filename: preferredName, message: error.localizedDescription)
            }
        }

        throw InboxImportIssue(
            code: .noAvailableName,
            filename: preferredName,
            message: "Sorting Hat couldn’t find a collision-free Inbox filename."
        )
    }

    static func validateFilename(_ name: String) throws {
        let value = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty, value != ".", value != "..", !value.contains("/"), !value.contains(":"), !value.contains("\0") else {
            throw InboxImportIssue(code: .unsafeName, filename: name, message: "The item has an unsafe filename.")
        }
    }

    static func isFileExists(_ error: Error) -> Bool {
        let cocoa = error as NSError
        return cocoa.domain == NSCocoaErrorDomain && cocoa.code == NSFileWriteFileExistsError
    }

    static func fingerprint(of file: URL) throws -> FileFingerprint {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        var size: Int64 = 0
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            size += Int64(data.count)
            hasher.update(data: data)
        }
        return FileFingerprint(
            byteCount: size,
            sha256: hasher.finalize().map { String(format: "%02x", $0) }.joined()
        )
    }
}

/// `NSItemProvider` represents `public.file-url` as URL data on macOS. Keep
/// this conversion in the shared core so the Finder adapter's real transport
/// format is covered without coupling import policy to AppKit.
public enum FileURLRepresentationDecoder {
    public static func decode(_ data: Data) -> URL? {
        guard let url = URL(dataRepresentation: data, relativeTo: nil), url.isFileURL else { return nil }
        return url
    }
}

public struct InboxImportBatch: Equatable, Sendable {
    public let results: [InboxImportResult]

    public init(results: [InboxImportResult]) { self.results = results }

    public var imported: [URL] {
        results.compactMap { if case .imported(_, let destination) = $0 { destination } else { nil } }
    }

    public var failures: [InboxImportIssue] {
        results.compactMap { if case .failed(_, let issue) = $0 { issue } else { nil } }
    }

    public var alreadyInInboxCount: Int {
        results.filter { if case .alreadyInInbox = $0 { true } else { false } }.count
    }

    public var statusSummary: String {
        var parts: [String] = []
        if !imported.isEmpty { parts.append("\(imported.count) added") }
        if alreadyInInboxCount > 0 { parts.append("\(alreadyInInboxCount) already in the Inbox") }
        if !failures.isEmpty { parts.append("\(failures.count) failed") }
        return parts.isEmpty ? "No files were selected" : parts.joined(separator: ", ")
    }
}

public enum InboxImportResult: Equatable, Sendable {
    case imported(source: URL, destination: URL)
    case alreadyInInbox(source: URL)
    case failed(source: URL, issue: InboxImportIssue)
}

public struct InboxImportIssue: Error, Codable, Equatable, LocalizedError, Sendable {
    public enum Code: String, Codable, Sendable {
        case unsupportedItem
        case unsafeName
        case inboxUnavailable
        case copyFailed
        case noAvailableName
        case sharedContainerUnavailable
        case corruptQueueItem
        case commitStateLost
        case providerFailed
        case inboxPermissionMissing
    }

    public let code: Code
    public let filename: String
    public let message: String

    public init(code: Code, filename: String, message: String) {
        self.code = code
        self.filename = filename
        self.message = message
    }

    public var errorDescription: String? { filename.isEmpty ? message : "\(filename): \(message)" }
}

public struct InboxImportBatchError: Error, LocalizedError, Sendable {
    public let batch: InboxImportBatch

    public init(batch: InboxImportBatch) { self.batch = batch }

    public var errorDescription: String? {
        let details = batch.failures.prefix(3).map(\.localizedDescription).joined(separator: "\n")
        let remaining = max(0, batch.failures.count - 3)
        return remaining == 0 ? details : "\(details)\n…and \(remaining) more."
    }
}

struct FileFingerprint: Codable, Equatable, Sendable {
    let byteCount: Int64
    let sha256: String
}
