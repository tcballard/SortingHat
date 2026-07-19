import Foundation

/// Resolves model suggestions against the destinations the person actually configured.
/// The model still interprets content; this layer owns deterministic file and path contracts.
public enum RoutingDecisionResolver {
    public static let version = "routing-rules-v1"

    public static func resolve(
        file: URL,
        decision: Decision,
        rules: [String],
        referenceDate: Date = .now
    ) throws -> Decision {
        let filename = preservingOriginalExtension(in: decision.filename, for: file)
        let proposedFolder = decision.folder.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !proposedFolder.isEmpty else {
            return Decision(filename: filename, folder: "", tags: decision.tags, reason: decision.reason)
        }
        guard isSafeFolderShape(proposedFolder) else { throw HatError.unsafePath(proposedFolder) }

        let routes = rules.compactMap(CompiledRoutingRule.init)
        guard !routes.isEmpty else {
            return Decision(filename: filename, folder: proposedFolder, tags: decision.tags, reason: decision.reason)
        }

        if let route = strongestSourceMatch(for: file, in: routes) {
            let folder = try route.render(referenceDate: referenceDate, proposedFolder: proposedFolder)
            return Decision(
                filename: filename,
                folder: folder,
                tags: mergedTags(decision.tags, route.staticTags),
                reason: decision.reason
            )
        }

        guard let match = routes.lazy.compactMap({ route in
            route.canonicalFolder(for: proposedFolder).map { (route, $0) }
        }).first else {
            throw HatError.invalidDecision("folder is not one of the configured destinations: \(proposedFolder)")
        }

        if match.0.isCatchAll, shouldKeepForReview(decision) {
            return Decision(filename: filename, folder: "", tags: decision.tags, reason: decision.reason)
        }

        return Decision(filename: filename, folder: match.1, tags: decision.tags, reason: decision.reason)
    }

    private static func preservingOriginalExtension(in proposed: String, for file: URL) -> String {
        let filename = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isSafeFilenameShape(filename), !file.pathExtension.isEmpty else { return filename }

        let proposedURL = URL(fileURLWithPath: filename)
        if proposedURL.pathExtension.isEmpty { return "\(filename).\(file.pathExtension)" }
        guard proposedURL.pathExtension.caseInsensitiveCompare(file.pathExtension) != .orderedSame else { return filename }

        let stem = proposedURL.deletingPathExtension().lastPathComponent
        guard !stem.isEmpty, stem != ".", stem != ".." else { return filename }
        return "\(stem).\(file.pathExtension)"
    }

    private static func isSafeFilenameShape(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".." &&
            !value.contains("/") && !value.contains(":") && !value.hasPrefix("~")
    }

    private static func isSafeFolderShape(_ value: String) -> Bool {
        guard !value.hasPrefix("/"), !value.hasPrefix("~") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false)
        return parts.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
    }

    private static func strongestSourceMatch(for file: URL, in routes: [CompiledRoutingRule]) -> CompiledRoutingRule? {
        var best: (route: CompiledRoutingRule, score: Int)?
        for route in routes where !route.isCatchAll {
            let score = route.sourceMatchScore(for: file)
            if score > (best?.score ?? 0) { best = (route, score) }
        }
        return best?.route
    }

    private static func shouldKeepForReview(_ decision: Decision) -> Bool {
        let reason = decision.reason.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        let uncertaintyPhrases = [
            "insufficient", "not enough", "no clear", "lacks clear", "unclear", "ambiguous",
            "cannot determine", "unable to determine", "unknown", "no dates or document type",
            "no date or document type", "no dates or file-specific context",
        ]
        guard uncertaintyPhrases.contains(where: reason.contains) else { return false }

        let genericTags: Set<String> = [
            "file", "files", "document", "documents", "general", "note", "other", "review",
            "text", "uncategorized", "unknown",
        ]
        return decision.tags.allSatisfy {
            genericTags.contains($0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased())
        }
    }

    private static func mergedTags(_ proposed: [String], _ configured: [String]) -> [String] {
        var result = proposed
        for tag in configured where !result.contains(where: { $0.caseInsensitiveCompare(tag) == .orderedSame }) {
            result.append(tag)
        }
        return result
    }
}

struct CompiledRoutingRule: Equatable, Sendable {
    let subject: String
    let destinationTemplate: String
    let staticTags: [String]
    let isCatchAll: Bool

    init?(_ rule: String) {
        let value = rule.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let prefix = value.range(of: "Put ", options: [.anchored, .caseInsensitive]) else { return nil }
        let body = value[prefix.upperBound...]
        guard let separator = body.range(of: " in ", options: .caseInsensitive) else { return nil }

        let subject = String(body[..<separator.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        let tail = String(body[separator.upperBound...])
        let modifierMarkers = [", organised by", ", organized by", ", and tag", " and tag", ", tag", ", and add", " and add"]
        let end = modifierMarkers.compactMap { tail.range(of: $0, options: .caseInsensitive)?.lowerBound }.min() ?? tail.endIndex
        let destination = String(tail[..<end]).trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )

        guard !subject.isEmpty, Self.isSupportedTemplate(destination) else { return nil }
        self.subject = subject
        destinationTemplate = destination
        staticTags = Self.parseStaticTags(from: tail)
        isCatchAll = Self.catchAllSubjects.contains(Self.normalizedPhrase(subject))
    }

    func canonicalFolder(for proposed: String) -> String? {
        let templateParts = destinationTemplate.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        let proposedParts = proposed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard templateParts.count == proposedParts.count else { return nil }

        var canonical: [String] = []
        for (template, value) in zip(templateParts, proposedParts) {
            switch template.uppercased() {
            case "YYYY":
                guard Self.isYear(value) else { return nil }
                canonical.append(value)
            case "YYYY-MM":
                guard Self.isYearMonth(value) else { return nil }
                canonical.append(value)
            default:
                guard template.caseInsensitiveCompare(value) == .orderedSame else { return nil }
                canonical.append(template)
            }
        }
        return canonical.joined(separator: "/")
    }

    func render(referenceDate: Date, proposedFolder: String) throws -> String {
        let proposedDate = Self.folderDate(in: proposedFolder)
        let reference = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: referenceDate)
        guard let referenceYear = reference.year, let referenceMonth = reference.month else {
            throw HatError.invalidDecision("could not resolve destination date")
        }

        let components = destinationTemplate.split(separator: "/", omittingEmptySubsequences: false).map { part -> String in
            switch part.uppercased() {
            case "YYYY":
                return String(proposedDate.year ?? referenceYear)
            case "YYYY-MM":
                let year = proposedDate.year ?? referenceYear
                let month = proposedDate.month ?? referenceMonth
                return String(format: "%04d-%02d", year, month)
            default:
                return String(part)
            }
        }
        return components.joined(separator: "/")
    }

    func sourceMatchScore(for file: URL) -> Int {
        let subjectTokens = Set(Self.tokens(subject).map(Self.singular).filter { !Self.subjectStopWords.contains($0) })
        guard subjectTokens.count == 1, let subjectToken = subjectTokens.first else { return 0 }
        let filenameTokens = Set(Self.tokens(file.deletingPathExtension().lastPathComponent).map(Self.singular))
        if filenameTokens.contains(subjectToken) { return 101 }

        let fileExtension = Self.singular(file.pathExtension.lowercased())
        return !fileExtension.isEmpty && subjectToken == fileExtension ? 10 : 0
    }

    private static func isSupportedTemplate(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("~") else { return false }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return false }
        return parts.allSatisfy { part in
            !part.uppercased().contains("YYYY") || part.uppercased() == "YYYY" || part.uppercased() == "YYYY-MM"
        }
    }

    private static func parseStaticTags(from tail: String) -> [String] {
        guard let marker = tail.range(of: "tag them ", options: .caseInsensitive) else { return [] }
        let value = String(tail[marker.upperBound...]).trimmingCharacters(
            in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "."))
        )
        return value.components(separatedBy: " and ").compactMap { candidate in
            let tag = candidate.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: ",")))
            let lowered = tag.lowercased()
            guard !tag.isEmpty, !lowered.hasPrefix("the "), !lowered.hasPrefix("a "), !lowered.hasPrefix("an ") else { return nil }
            return tag
        }
    }

    private static func folderDate(in folder: String) -> (year: Int?, month: Int?) {
        for part in folder.split(separator: "/").map(String.init) {
            if isYearMonth(part) {
                let values = part.split(separator: "-").compactMap { Int($0) }
                return (values[0], values[1])
            }
        }
        for part in folder.split(separator: "/").map(String.init) where isYear(part) {
            return (Int(part), nil)
        }
        return (nil, nil)
    }

    private static func isYear(_ value: String) -> Bool {
        value.count == 4 && value.allSatisfy(\.isNumber) && (1900...2999).contains(Int(value) ?? 0)
    }

    private static func isYearMonth(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, isYear(String(parts[0])), parts[1].count == 2, let month = Int(parts[1]) else { return false }
        return (1...12).contains(month)
    }

    private static func tokens(_ value: String) -> [String] {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    private static func singular(_ value: String) -> String {
        if value.hasSuffix("ies"), value.count > 3 { return String(value.dropLast(3)) + "y" }
        if value.hasSuffix("s"), !value.hasSuffix("ss"), value.count > 1 { return String(value.dropLast()) }
        return value
    }

    private static func normalizedPhrase(_ value: String) -> String { tokens(value).map(singular).joined(separator: " ") }

    private static let catchAllSubjects: Set<String> = [
        "all file", "all other file", "anything else", "every file", "everything else", "other file",
    ]
    private static let subjectStopWords: Set<String> = [
        "a", "all", "an", "and", "any", "document", "else", "every", "file", "item", "my", "or", "other", "the",
    ]
}
