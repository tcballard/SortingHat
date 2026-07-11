import Foundation

public struct Organizer {
    public let inbox: URL
    public let rules: [String]
    public let analyzer: any FileAnalyzing
    public var fileManager = FileManager.default
    public init(inbox: URL, rules: [String], analyzer: any FileAnalyzing, fileManager: FileManager = .default) {
        self.inbox = inbox; self.rules = rules; self.analyzer = analyzer; self.fileManager = fileManager
    }

    public func candidates() throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: inbox,
            includingPropertiesForKeys: [.isRegularFileKey, .isHiddenKey],
            options: [.skipsHiddenFiles]
        ).filter { url in
            guard url.lastPathComponent != "sortinghat.conf" else { return false }
            return (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
        }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    public func plan(_ file: URL) throws -> PlannedMove {
        let decision = try analyzer.analyze(file: file, rules: rules)
        let filename = try Self.safeComponent(decision.filename, label: "filename")
        let folder = try Self.safeFolder(decision.folder)
        var destination = inbox.appending(path: folder, directoryHint: .isDirectory).appending(path: filename)
        destination = available(destination, excluding: file)
        return PlannedMove(source: file, destination: destination, tags: decision.tags, reason: decision.reason)
    }

    public func apply(_ move: PlannedMove) throws {
        try fileManager.createDirectory(at: move.destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.moveItem(at: move.source, to: move.destination)
        if !move.tags.isEmpty { try Self.writeFinderTags(move.tags, to: move.destination) }
    }

    private func available(_ proposed: URL, excluding source: URL) -> URL {
        if proposed.standardizedFileURL == source.standardizedFileURL || !fileManager.fileExists(atPath: proposed.path) { return proposed }
        let stem = proposed.deletingPathExtension().lastPathComponent
        let ext = proposed.pathExtension
        for index in 2...9999 {
            let name = ext.isEmpty ? "\(stem)-\(index)" : "\(stem)-\(index).\(ext)"
            let candidate = proposed.deletingLastPathComponent().appending(path: name)
            if !fileManager.fileExists(atPath: candidate.path) { return candidate }
        }
        return proposed.deletingLastPathComponent().appending(path: "\(UUID().uuidString)-\(proposed.lastPathComponent)")
    }

    private static func safeComponent(_ value: String, label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != ".", trimmed != "..", !trimmed.contains("/"), !trimmed.contains(":"), !trimmed.hasPrefix("~") else {
            throw HatError.unsafePath("\(label): \(value)")
        }
        return trimmed
    }

    private static func safeFolder(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || trimmed == "." { return "" }
        guard !trimmed.hasPrefix("/"), !trimmed.hasPrefix("~") else { throw HatError.unsafePath(value) }
        let parts = trimmed.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { throw HatError.unsafePath(value) }
        return trimmed
    }

    private static func writeFinderTags(_ tags: [String], to file: URL) throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        let result = plist.withUnsafeBytes { bytes in
            setxattr(file.path, "com.apple.metadata:_kMDItemUserTags", bytes.baseAddress, bytes.count, 0, 0)
        }
        if result != 0 { throw CocoaError(.fileWriteUnknown) }
    }
}
