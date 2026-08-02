import Foundation

public struct RoutingRuleDescriptor: Equatable, Sendable {
    public let id: String
    public let subject: String
    public let destinationTemplate: String
    public let variables: [DestinationVariable]
    public let staticTags: [String]
    public let isCatchAll: Bool
}

/// Resolves model suggestions against the destinations the person actually configured.
/// The model interprets content; this layer owns rule identity, template values, and paths.
public enum RoutingDecisionResolver {
    public static let version = "routing-rules-v2"

    public static func resolve(
        file: URL,
        decision: Decision,
        rules: [String],
        referenceDate: Date = .now
    ) throws -> Decision {
        let filename = preservingOriginalExtension(in: decision.filename, for: file)
        let proposedFolder = decision.folder.trimmingCharacters(in: .whitespacesAndNewlines)
        if !proposedFolder.isEmpty, !isSafeFolderShape(proposedFolder) {
            throw HatError.unsafePath(proposedFolder)
        }

        let routes = try compiledRoutes(from: rules)
        if let matchedRuleID = decision.matchedRuleID {
            guard var route = routes.first(where: { $0.id == matchedRuleID }) else {
                throw HatError.invalidDecision("matched rule is not in the configured ruleset: \(matchedRuleID)")
            }
            if route.isCatchAll, let sourceRoute = strongestSourceMatch(for: file, in: routes) {
                route = sourceRoute
            }
            return try resolveStructured(
                filename: filename,
                decision: decision,
                route: route,
                referenceDate: referenceDate
            )
        }

        guard decision.destinationValues.isEmpty else {
            throw HatError.invalidDecision("destination values require a matched rule identifier")
        }
        guard !proposedFolder.isEmpty else {
            return preservingRoutingMetadata(
                decision,
                filename: filename,
                folder: "",
                reason: decision.reason
            )
        }
        guard !routes.isEmpty else {
            return preservingRoutingMetadata(
                decision,
                filename: filename,
                folder: proposedFolder,
                reason: decision.reason
            )
        }

        // Compatibility path for decisions produced before structured rule IDs.
        // Dynamic brace placeholders deliberately cannot use this path.
        if let route = strongestSourceMatch(for: file, in: routes) {
            let folder = try route.renderLegacy(referenceDate: referenceDate, proposedFolder: proposedFolder)
            return Decision(
                filename: filename,
                folder: folder,
                tags: mergedTags(decision.tags, route.staticTags),
                reason: decision.reason,
                matchedRuleID: route.id
            )
        }

        guard let match = routes.lazy.compactMap({ route in
            route.canonicalLegacyFolder(for: proposedFolder).map { (route, $0) }
        }).first else {
            throw HatError.invalidDecision("folder is not one of the configured destinations: \(proposedFolder)")
        }

        if match.0.isCatchAll, shouldKeepForReview(decision) {
            return Decision(
                filename: filename,
                folder: "",
                tags: decision.tags,
                reason: decision.reason,
                matchedRuleID: match.0.id
            )
        }

        return Decision(
            filename: filename,
            folder: match.1,
            tags: decision.tags,
            reason: decision.reason,
            matchedRuleID: match.0.id
        )
    }

    public static func descriptors(for rules: [String]) throws -> [RoutingRuleDescriptor] {
        try compiledRoutes(from: rules).map(\.descriptor)
    }

    public static func validateDestinationTemplate(_ value: String) throws {
        guard CompiledRoutingRule.parseTemplate(value) != nil else {
            let supported = DestinationVariable.allCases.map { "{\($0.rawValue)}" }.joined(separator: ", ")
            throw HatError.invalidConfig(
                "unsupported destination template '\(value)'; use fixed folders, YYYY, YYYY-MM, or \(supported)"
            )
        }
    }

    /// Adds stable rule IDs and the exact slot contract to prompts without changing
    /// the person's persisted plain-language rules.
    public static func modelRules(_ rules: [String]) throws -> String {
        var lines: [String] = []
        for rule in rules {
            let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            if isPutRule(trimmed) {
                guard let route = CompiledRoutingRule(trimmed) else {
                    throw HatError.invalidConfig("unsupported routing rule: \(trimmed)")
                }
                let line = """
                - RULE_ID: \(route.id)
                  MATCH: \(route.subject)
                  CATCH_ALL: \(route.isCatchAll ? "yes" : "no")
                  INSTRUCTION: \(trimmed)
                  REQUIRED_DESTINATION_VALUES: \(route.variables.isEmpty ? "none" : route.variables.map(\.rawValue).joined(separator: ", "))
                  LEGACY_DATE_FOLDER: \(route.hasLegacyDateVariables ? "yes" : "no")
                """
                lines.append(line)
            } else {
                lines.append("- \(trimmed)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func resolveStructured(
        filename: String,
        decision: Decision,
        route: CompiledRoutingRule,
        referenceDate: Date
    ) throws -> Decision {
        var supplied: [DestinationVariable: String] = [:]
        for item in decision.destinationValues {
            guard supplied[item.variable] == nil else {
                throw HatError.invalidDecision("destination value is repeated: \(item.variable.rawValue)")
            }
            guard route.variables.contains(item.variable) else {
                throw HatError.invalidDecision(
                    "destination value is not declared by matched rule: \(item.variable.rawValue)"
                )
            }
            supplied[item.variable] = item.value
        }

        var normalized: [DestinationVariable: String] = [:]
        for variable in route.variables {
            guard let raw = supplied[variable] else {
                return heldForReview(
                    filename: filename,
                    decision: decision,
                    detail: "missing destination value for {\(variable.rawValue)}"
                )
            }
            guard let value = try normalizedValue(raw, for: variable) else {
                return heldForReview(
                    filename: filename,
                    decision: decision,
                    detail: "{\(variable.rawValue)} could not be identified confidently"
                )
            }
            normalized[variable] = value
        }

        let folder: String
        if route.supportsLegacyInference {
            folder = try route.renderLegacy(referenceDate: referenceDate, proposedFolder: decision.folder)
        } else {
            folder = try route.renderStructured(values: normalized, referenceDate: referenceDate)
        }
        let normalizedValues = route.variables.compactMap { variable in
            normalized[variable].map { DestinationValue(variable: variable, value: $0) }
        }
        return Decision(
            filename: filename,
            folder: folder,
            tags: mergedTags(decision.tags, route.staticTags),
            reason: decision.reason,
            matchedRuleID: route.id,
            destinationValues: normalizedValues
        )
    }

    private static func normalizedValue(_ raw: String, for variable: DestinationVariable) throws -> String? {
        let value = raw.precomposedStringWithCanonicalMapping
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        guard !value.isEmpty else { return nil }

        switch variable {
        case .year:
            return CompiledRoutingRule.isYear(value) ? value : nil
        case .month:
            guard value.count == 2, let month = Int(value), (1...12).contains(month) else { return nil }
            return value
        case .yearMonth:
            return CompiledRoutingRule.isYearMonth(value) ? value : nil
        case .merchant, .client, .project, .sourceApp:
            if genericDestinationValues.contains(normalizedPhrase(value)) { return nil }
            guard value.count <= 80,
                  value != ".", value != "..",
                  !value.hasPrefix("."), !value.hasPrefix("~"),
                  !value.contains("/"), !value.contains("\\"), !value.contains(":"),
                  !value.contains("{"), !value.contains("}"),
                  !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
                throw HatError.unsafePath("{\(variable.rawValue)}: \(raw)")
            }
            return value
        }
    }

    private static func heldForReview(
        filename: String,
        decision: Decision,
        detail: String
    ) -> Decision {
        let reason = decision.reason.trimmingCharacters(in: .whitespacesAndNewlines)
        let combined = reason.isEmpty ? detail : "\(reason). Needs review: \(detail)."
        return preservingRoutingMetadata(decision, filename: filename, folder: "", reason: combined)
    }

    private static func preservingRoutingMetadata(
        _ decision: Decision,
        filename: String,
        folder: String,
        reason: String
    ) -> Decision {
        Decision(
            filename: filename,
            folder: folder,
            tags: decision.tags,
            reason: reason,
            matchedRuleID: decision.matchedRuleID,
            destinationValues: decision.destinationValues
        )
    }

    private static func compiledRoutes(from rules: [String]) throws -> [CompiledRoutingRule] {
        try rules.compactMap { rule in
            let trimmed = rule.trimmingCharacters(in: .whitespacesAndNewlines)
            guard isPutRule(trimmed) else { return nil }
            guard let route = CompiledRoutingRule(trimmed) else {
                throw HatError.invalidConfig("unsupported routing rule: \(trimmed)")
            }
            return route
        }
    }

    private static func isPutRule(_ value: String) -> Bool {
        value.range(of: "Put ", options: [.anchored, .caseInsensitive]) != nil
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
        for route in routes where !route.isCatchAll && route.supportsLegacyInference {
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
            "no identifiable document type", "no identifiable context", "no specific context",
            "no recognizable subject", "lacks recognizable subject", "lacks a recognizable subject",
        ]
        guard uncertaintyPhrases.contains(where: reason.contains) else { return false }

        let genericTags: Set<String> = [
            "file", "files", "document", "documents", "general", "note", "other", "review",
            "text", "uncategorized", "unknown", "follow-up", "follow up",
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

    private static func normalizedPhrase(_ value: String) -> String {
        value.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    private static let genericDestinationValues: Set<String> = [
        "unknown", "unclear", "unidentified", "not known", "not available", "n a", "none", "other",
    ]
}

struct CompiledRoutingRule: Equatable, Sendable {
    let id: String
    let subject: String
    let destinationTemplate: String
    let variables: [DestinationVariable]
    let staticTags: [String]
    let isCatchAll: Bool
    private let template: [TemplateComponent]
    private let usesStructuredPlaceholders: Bool

    var descriptor: RoutingRuleDescriptor {
        RoutingRuleDescriptor(
            id: id,
            subject: subject,
            destinationTemplate: destinationTemplate,
            variables: variables,
            staticTags: staticTags,
            isCatchAll: isCatchAll
        )
    }

    var supportsLegacyInference: Bool { !usesStructuredPlaceholders }
    var hasLegacyDateVariables: Bool {
        template.contains { component in
            if case .variable(_, true) = component { return true }
            return false
        }
    }

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

        guard !subject.isEmpty, let template = Self.parseTemplate(destination) else { return nil }
        self.id = Self.stableID(for: value)
        self.subject = subject
        destinationTemplate = destination
        self.template = template
        variables = template.compactMap { component in
            if case .variable(let variable, false) = component { return variable }
            return nil
        }.uniqued()
        staticTags = Self.parseStaticTags(from: tail)
        isCatchAll = Self.catchAllSubjects.contains(Self.normalizedPhrase(subject))
        usesStructuredPlaceholders = template.contains { component in
            if case .variable(_, let legacy) = component { return !legacy }
            return false
        }
    }

    static func parseTemplate(_ value: String) -> [TemplateComponent]? {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasPrefix("~") else { return nil }
        let parts = value.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard parts.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else { return nil }

        var result: [TemplateComponent] = []
        for part in parts {
            switch part.uppercased() {
            case "YYYY": result.append(.variable(.year, legacy: true)); continue
            case "YYYY-MM": result.append(.variable(.yearMonth, legacy: true)); continue
            default: break
            }
            if part.hasPrefix("{"), part.hasSuffix("}"), part.count > 2 {
                let name = String(part.dropFirst().dropLast()).lowercased()
                guard let variable = DestinationVariable(rawValue: name) else { return nil }
                result.append(.variable(variable, legacy: false))
                continue
            }
            guard !part.contains("{"), !part.contains("}"), !part.uppercased().contains("YYYY") else { return nil }
            result.append(.literal(part))
        }
        return result
    }

    func canonicalLegacyFolder(for proposed: String) -> String? {
        guard supportsLegacyInference else { return nil }
        let proposedParts = proposed.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
        guard template.count == proposedParts.count else { return nil }

        var canonical: [String] = []
        for (component, value) in zip(template, proposedParts) {
            switch component {
            case .literal(let literal):
                guard literal.caseInsensitiveCompare(value) == .orderedSame else { return nil }
                canonical.append(literal)
            case .variable(.year, true):
                guard Self.isYear(value) else { return nil }
                canonical.append(value)
            case .variable(.yearMonth, true):
                guard Self.isYearMonth(value) else { return nil }
                canonical.append(value)
            default:
                return nil
            }
        }
        return canonical.joined(separator: "/")
    }

    func canonicalFolder(for proposed: String) -> String? {
        canonicalLegacyFolder(for: proposed)
    }

    func renderStructured(values: [DestinationVariable: String], referenceDate: Date) throws -> String {
        let date = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: referenceDate)
        guard let year = date.year, let month = date.month else {
            throw HatError.invalidDecision("could not resolve destination date")
        }
        return try template.map { component in
            switch component {
            case .literal(let value): return value
            case .variable(.year, true): return String(year)
            case .variable(.yearMonth, true): return String(format: "%04d-%02d", year, month)
            case .variable(let variable, false):
                guard let value = values[variable] else {
                    throw HatError.invalidDecision("missing destination value for {\(variable.rawValue)}")
                }
                return value
            default:
                throw HatError.invalidDecision("unsupported legacy destination date variable")
            }
        }.joined(separator: "/")
    }

    func renderLegacy(referenceDate: Date, proposedFolder: String) throws -> String {
        let proposedDate = Self.folderDate(in: proposedFolder)
        let reference = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: referenceDate)
        guard let referenceYear = reference.year, let referenceMonth = reference.month else {
            throw HatError.invalidDecision("could not resolve destination date")
        }

        return try template.map { component in
            switch component {
            case .literal(let value): return value
            case .variable(.year, true): return String(proposedDate.year ?? referenceYear)
            case .variable(.yearMonth, true):
                return String(format: "%04d-%02d", proposedDate.year ?? referenceYear, proposedDate.month ?? referenceMonth)
            default:
                throw HatError.invalidDecision("structured destination values require a matched rule identifier")
            }
        }.joined(separator: "/")
    }

    func render(referenceDate: Date, proposedFolder: String) throws -> String {
        try renderLegacy(referenceDate: referenceDate, proposedFolder: proposedFolder)
    }

    func sourceMatchScore(for file: URL) -> Int {
        let subjectTokens = Set(Self.tokens(subject).map(Self.singular).filter { !Self.subjectStopWords.contains($0) })
        guard subjectTokens.count == 1, let subjectToken = subjectTokens.first else { return 0 }
        let filenameTokens = Set(Self.tokens(file.deletingPathExtension().lastPathComponent).map(Self.singular))
        if filenameTokens.contains(subjectToken) { return 101 }

        let fileExtension = Self.singular(file.pathExtension.lowercased())
        return !fileExtension.isEmpty && subjectToken == fileExtension ? 10 : 0
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

    static func isYear(_ value: String) -> Bool {
        value.count == 4 && value.allSatisfy(\.isNumber) && (1900...2999).contains(Int(value) ?? 0)
    }

    static func isYearMonth(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 2, isYear(String(parts[0])), parts[1].count == 2, let month = Int(parts[1]) else { return false }
        return (1...12).contains(month)
    }

    private static func stableID(for rule: String) -> String {
        let normalized = rule.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in normalized.utf8 {
            hash ^= UInt64(byte)
            hash &*= 1_099_511_628_211
        }
        let hex = String(hash, radix: 16)
        return "route-" + String(repeating: "0", count: max(0, 16 - hex.count)) + hex
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

enum TemplateComponent: Equatable, Sendable {
    case literal(String)
    case variable(DestinationVariable, legacy: Bool)

    var variable: DestinationVariable? {
        if case .variable(let value, _) = self { value } else { nil }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
