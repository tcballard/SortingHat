import Foundation

public struct Organizer {
    public let inbox: URL
    public let output: URL
    public let rules: [String]
    public let analyzer: any FileAnalyzing
    public let referenceDate: Date
    public var fileManager = FileManager.default
    public init(
        inbox: URL,
        output: URL? = nil,
        rules: [String],
        analyzer: any FileAnalyzing,
        referenceDate: Date = .now,
        fileManager: FileManager = .default
    ) {
        self.inbox = inbox
        self.output = output ?? inbox.deletingLastPathComponent()
        self.rules = rules
        self.analyzer = analyzer
        self.referenceDate = referenceDate
        self.fileManager = fileManager
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
        return try plannedMove(file, decision: resolve(file, decision: decision))
    }

    public func resolve(_ file: URL, decision: Decision) throws -> Decision {
        try RoutingDecisionResolver.resolve(file: file, decision: decision, rules: rules, referenceDate: referenceDate)
    }

    public func planAll(_ files: [URL]) -> [PlanningOutcome] {
        guard let batchAnalyzer = analyzer as? any BatchFileAnalyzing else {
            return files.map { file in
                do { return .success(try plan(file)) }
                catch { return .failure(source: file, error: error) }
            }
        }

        let inputs = files.enumerated().map { BatchFileInput(id: "file-\($0.offset + 1)", file: $0.element) }
        let outcomes = batchAnalyzer.analyzeBatch(files: inputs, rules: rules)
        let grouped = Dictionary(grouping: outcomes) { outcome in
            switch outcome {
            case .decision(let sourceID, _), .failure(let sourceID, _): sourceID
            }
        }

        return inputs.map { input in
            guard let matches = grouped[input.id], matches.count == 1 else {
                let detail = grouped[input.id] == nil ? "missing result for \(input.id)" : "duplicate results for \(input.id)"
                return .failure(source: input.file, error: HatError.invalidBatch(detail))
            }
            switch matches[0] {
            case .decision(_, let decision):
                do { return .success(try plannedMove(input.file, decision: resolve(input.file, decision: decision))) }
                catch { return .failure(source: input.file, error: error) }
            case .failure(_, let error):
                return .failure(source: input.file, error: error)
            }
        }
    }

    /// Runs the shipping analysis, resolver, collision naming, and validator without
    /// creating folders, moving files, or writing Finder tags.
    public func previewAll(_ files: [URL]) -> [FilingPreview] {
        guard let batchAnalyzer = analyzer as? any BatchFileAnalyzing else {
            return files.map { file in
                do { return preview(file, decision: try analyzer.analyze(file: file, rules: rules)) }
                catch { return previewFailure(file: file, decision: nil, error: error) }
            }
        }

        let inputs = files.enumerated().map { BatchFileInput(id: "file-\($0.offset + 1)", file: $0.element) }
        let outcomes = batchAnalyzer.analyzeBatch(files: inputs, rules: rules)
        let grouped = Dictionary(grouping: outcomes) { outcome in
            switch outcome {
            case .decision(let sourceID, _), .failure(let sourceID, _): sourceID
            }
        }

        return inputs.map { input in
            guard let matches = grouped[input.id], matches.count == 1 else {
                let detail = grouped[input.id] == nil ? "missing result for \(input.id)" : "duplicate results for \(input.id)"
                return previewFailure(file: input.file, decision: nil, error: HatError.invalidBatch(detail))
            }
            switch matches[0] {
            case .decision(_, let decision): return preview(input.file, decision: decision)
            case .failure(_, let error): return previewFailure(file: input.file, decision: nil, error: error)
            }
        }
    }

    private func preview(_ file: URL, decision: Decision) -> FilingPreview {
        do {
            let resolved = try resolve(file, decision: decision)
            do {
                let move = try plannedMove(file, decision: resolved)
                return FilingPreview(
                    source: file,
                    status: .ready,
                    proposedFilename: move.destination.lastPathComponent,
                    destination: move.destination,
                    renderedFolder: resolved.folder,
                    tags: move.tags,
                    reason: move.reason,
                    matchedRuleID: resolved.matchedRuleID,
                    matchedRuleSubject: matchedRuleSubject(for: resolved.matchedRuleID),
                    destinationValues: resolved.destinationValues
                )
            } catch {
                return previewFailure(file: file, decision: resolved, error: error)
            }
        } catch {
            return previewFailure(file: file, decision: decision, error: error)
        }
    }

    private func previewFailure(file: URL, decision: Decision?, error: Error) -> FilingPreview {
        let status: FilingPreviewStatus
        if let hatError = error as? HatError, case .needsReview = hatError { status = .needsReview }
        else { status = .invalid }
        return FilingPreview(
            source: file,
            status: status,
            proposedFilename: decision?.filename,
            renderedFolder: decision?.folder.nilIfEmpty,
            tags: decision?.tags ?? [],
            reason: error.localizedDescription,
            matchedRuleID: decision?.matchedRuleID,
            matchedRuleSubject: matchedRuleSubject(for: decision?.matchedRuleID),
            destinationValues: decision?.destinationValues ?? []
        )
    }

    private func matchedRuleSubject(for id: String?) -> String? {
        guard let id else { return nil }
        return try? RoutingDecisionResolver.descriptors(for: rules).first(where: { $0.id == id })?.subject
    }

    private func plannedMove(_ file: URL, decision: Decision) throws -> PlannedMove {
        let proposedFolder = decision.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposedFolder.isEmpty else {
            throw HatError.needsReview(decision.reason)
        }
        var filename = try Self.safeComponent(decision.filename, label: "filename")
        if URL(fileURLWithPath: filename).pathExtension.isEmpty, !file.pathExtension.isEmpty {
            filename += ".\(file.pathExtension)"
        }
        let proposedExtension = URL(fileURLWithPath: filename).pathExtension
        guard proposedExtension.caseInsensitiveCompare(file.pathExtension) == .orderedSame else {
            throw HatError.invalidDecision("the renamed file must preserve the .\(file.pathExtension) extension")
        }
        guard Self.normalizedFilename(filename) != Self.normalizedFilename(file.lastPathComponent) else {
            throw HatError.invalidDecision("the model returned the original filename unchanged: \(filename)")
        }
        let folder = try Self.safeFolder(proposedFolder)
        var destination = output.appending(path: folder, directoryHint: .isDirectory).appending(path: filename)
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

    private static func normalizedFilename(_ filename: String) -> String {
        filename.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func writeFinderTags(_ tags: [String], to file: URL) throws {
        let plist = try PropertyListSerialization.data(fromPropertyList: tags, format: .binary, options: 0)
        let result = plist.withUnsafeBytes { bytes in
            setxattr(file.path, "com.apple.metadata:_kMDItemUserTags", bytes.baseAddress, bytes.count, 0, 0)
        }
        if result != 0 { throw CocoaError(.fileWriteUnknown) }
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
