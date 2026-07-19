import Foundation

public struct InboxAccessBookmarkStore {
    private let root: URL
    private let fileManager: FileManager
    private let resolver: (Data) throws -> (URL, Bool)

    public init(root: URL, fileManager: FileManager = .default) {
        self.root = root
        self.fileManager = fileManager
        resolver = { data in
            var stale = false
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &stale
            )
            return (url, stale)
        }
    }

    init(
        root: URL,
        fileManager: FileManager = .default,
        resolver: @escaping (Data) throws -> (URL, Bool)
    ) {
        self.root = root
        self.fileManager = fileManager
        self.resolver = resolver
    }

    public func prepare(_ inbox: URL, date: Date = .now) throws -> InboxAccessGrant {
        let standardizedInbox = inbox.standardizedFileURL
        let accessing = standardizedInbox.startAccessingSecurityScopedResource()
        defer { if accessing { standardizedInbox.stopAccessingSecurityScopedResource() } }
        let bookmark = try standardizedInbox.bookmarkData(
            options: [.withSecurityScope],
            includingResourceValuesForKeys: [.isDirectoryKey],
            relativeTo: nil
        )
        return InboxAccessGrant(
            bookmark: bookmark,
            metadata: InboxAccessMetadata(
                displayPath: standardizedInbox.path(percentEncoded: false),
                savedAt: date
            )
        )
    }

    public func commit(_ grant: InboxAccessGrant) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        // Publish metadata first and the bookmark last. A crash can therefore
        // only leave old access or a mismatched grant, which the app refuses
        // to drain until the user repairs it.
        try encoder.encode(grant.metadata).write(to: metadataURL, options: .atomic)
        try grant.bookmark.write(to: bookmarkURL, options: .atomic)
    }

    public func save(_ inbox: URL, date: Date = .now) throws {
        try commit(prepare(inbox, date: date))
    }

    public func snapshot() throws -> InboxAccessSnapshot {
        InboxAccessSnapshot(
            bookmark: fileManager.fileExists(atPath: bookmarkURL.path) ? try Data(contentsOf: bookmarkURL) : nil,
            metadata: fileManager.fileExists(atPath: metadataURL.path) ? try Data(contentsOf: metadataURL) : nil
        )
    }

    public func restore(_ snapshot: InboxAccessSnapshot) throws {
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try restore(snapshot.metadata, to: metadataURL)
        try restore(snapshot.bookmark, to: bookmarkURL)
    }

    public func resolve() -> InboxAccessState {
        guard fileManager.fileExists(atPath: bookmarkURL.path) else { return .missing }
        do {
            let (url, stale) = try resolver(Data(contentsOf: bookmarkURL))
            return stale ? .stale(url) : .available(url)
        } catch {
            return .invalid(error.localizedDescription)
        }
    }

    public func resolve(expectedInbox: URL) -> InboxAccessState {
        let expected = expectedInbox.standardizedFileURL
        switch resolve() {
        case .available(let url):
            let bookmarked = url.standardizedFileURL
            return bookmarked == expected ? .available(bookmarked) : .mismatched(bookmarked: bookmarked, expected: expected)
        case .stale(let url):
            let bookmarked = url.standardizedFileURL
            return bookmarked == expected ? .stale(bookmarked) : .mismatched(bookmarked: bookmarked, expected: expected)
        case .missing:
            return .missing
        case .invalid(let message):
            return .invalid(message)
        case .mismatched(let bookmarked, let expected):
            return .mismatched(bookmarked: bookmarked, expected: expected)
        }
    }

    public func metadata() -> InboxAccessMetadata? {
        guard let data = try? Data(contentsOf: metadataURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(InboxAccessMetadata.self, from: data)
    }

    private var bookmarkURL: URL { root.appending(path: "Inbox.bookmark") }
    private var metadataURL: URL { root.appending(path: "Inbox.json") }

    private func restore(_ data: Data?, to url: URL) throws {
        if let data {
            try data.write(to: url, options: .atomic)
        } else if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }
}

public enum InboxAccessState: Equatable, Sendable {
    case missing
    case available(URL)
    case stale(URL)
    case invalid(String)
    case mismatched(bookmarked: URL, expected: URL)

    public var needsRecovery: Bool {
        switch self {
        case .missing, .stale, .invalid, .mismatched: true
        case .available: false
        }
    }
}

public struct InboxAccessGrant: Sendable {
    public let bookmark: Data
    public let metadata: InboxAccessMetadata

    public init(bookmark: Data, metadata: InboxAccessMetadata) {
        self.bookmark = bookmark
        self.metadata = metadata
    }
}

public struct InboxAccessSnapshot: Sendable {
    public let bookmark: Data?
    public let metadata: Data?

    public init(bookmark: Data?, metadata: Data?) {
        self.bookmark = bookmark
        self.metadata = metadata
    }
}

public struct InboxAccessMetadata: Codable, Equatable, Sendable {
    public let displayPath: String
    public let savedAt: Date
}
