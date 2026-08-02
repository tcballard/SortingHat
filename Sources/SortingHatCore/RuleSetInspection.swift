import Foundation

public struct RuleSetIssue: Hashable, Sendable, Identifiable {
    public enum Kind: String, Hashable, Sendable {
        case empty
        case invalid
        case duplicate
        case conflicting
        case unreachable
    }

    public let kind: Kind
    public let ruleIndex: Int?
    public let message: String

    public init(kind: Kind, ruleIndex: Int?, message: String) {
        self.kind = kind
        self.ruleIndex = ruleIndex
        self.message = message
    }

    public var id: String { "\(kind.rawValue)-\(ruleIndex ?? -1)-\(message)" }
}

public struct RuleSetInspection: Equatable, Sendable {
    public let descriptors: [RoutingRuleDescriptor]
    public let issues: [RuleSetIssue]

    public init(descriptors: [RoutingRuleDescriptor], issues: [RuleSetIssue]) {
        self.descriptors = descriptors
        self.issues = issues
    }

    public var canActivate: Bool { issues.isEmpty }
}

/// Performs deterministic checks that do not need a model or representative files.
public enum RuleSetInspector {
    public static func inspect(_ rules: [String]) -> RuleSetInspection {
        let values = rules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        var issues: [RuleSetIssue] = []
        var descriptorsByIndex: [(index: Int, descriptor: RoutingRuleDescriptor)] = []
        var normalizedRuleIndexes: [String: Int] = [:]

        if values.allSatisfy(\.isEmpty) {
            issues.append(RuleSetIssue(kind: .empty, ruleIndex: nil, message: "Add at least one rule before saving."))
        }

        for (index, rule) in values.enumerated() {
            guard !rule.isEmpty else {
                issues.append(RuleSetIssue(kind: .empty, ruleIndex: index, message: "Rule \(index + 1) is empty."))
                continue
            }
            guard !rule.contains("\n"), !rule.contains("\r") else {
                issues.append(RuleSetIssue(kind: .invalid, ruleIndex: index, message: "Rule \(index + 1) must fit on one line."))
                continue
            }

            let normalized = normalize(rule)
            if let first = normalizedRuleIndexes[normalized] {
                issues.append(RuleSetIssue(
                    kind: .duplicate,
                    ruleIndex: index,
                    message: "Rule \(index + 1) duplicates rule \(first + 1)."
                ))
            } else {
                normalizedRuleIndexes[normalized] = index
            }

            guard rule.range(of: "Put ", options: [.anchored, .caseInsensitive]) != nil else { continue }
            do {
                guard let descriptor = try RoutingDecisionResolver.descriptors(for: [rule]).first else {
                    issues.append(RuleSetIssue(kind: .invalid, ruleIndex: index, message: "Rule \(index + 1) is not a complete destination rule."))
                    continue
                }
                descriptorsByIndex.append((index, descriptor))
            } catch {
                issues.append(RuleSetIssue(kind: .invalid, ruleIndex: index, message: "Rule \(index + 1): \(error.localizedDescription)"))
            }
        }

        var subjectIndexes: [String: Int] = [:]
        var firstCatchAll: (index: Int, descriptor: RoutingRuleDescriptor)?
        for entry in descriptorsByIndex {
            let subject = normalize(entry.descriptor.subject)
            if let first = subjectIndexes[subject] {
                issues.append(RuleSetIssue(
                    kind: .conflicting,
                    ruleIndex: entry.index,
                    message: "Rule \(entry.index + 1) conflicts with rule \(first + 1): both match \(entry.descriptor.subject)."
                ))
            } else {
                subjectIndexes[subject] = entry.index
            }

            if let catchAll = firstCatchAll, !entry.descriptor.isCatchAll {
                issues.append(RuleSetIssue(
                    kind: .unreachable,
                    ruleIndex: entry.index,
                    message: "Rule \(entry.index + 1) is unreachable because catch-all rule \(catchAll.index + 1) comes first."
                ))
            }
            if entry.descriptor.isCatchAll, firstCatchAll == nil {
                firstCatchAll = entry
            }
        }

        return RuleSetInspection(
            descriptors: descriptorsByIndex.map(\.descriptor),
            issues: issues.uniqued()
        )
    }

    public static func validate(_ rules: [String]) throws {
        let inspection = inspect(rules)
        guard inspection.canActivate else {
            throw HatError.invalidConfig(inspection.issues.map(\.message).joined(separator: " "))
        }
    }

    private static func normalize(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        var seen: Set<Element> = []
        return filter { seen.insert($0).inserted }
    }
}
