import Foundation

public struct RuleProposalOverlap: Equatable, Sendable, Identifiable {
    public let existingRuleIndex: Int
    public let message: String

    public init(existingRuleIndex: Int, message: String) {
        self.existingRuleIndex = existingRuleIndex
        self.message = message
    }

    public var id: String { "\(existingRuleIndex)-\(message)" }
}

public struct RuleProposalAssessment: Equatable, Sendable {
    public let proposedRule: String
    public let candidateRules: [String]
    public let insertionIndex: Int
    public let issues: [RuleSetIssue]
    public let overlaps: [RuleProposalOverlap]

    public init(
        proposedRule: String,
        candidateRules: [String],
        insertionIndex: Int,
        issues: [RuleSetIssue],
        overlaps: [RuleProposalOverlap]
    ) {
        self.proposedRule = proposedRule
        self.candidateRules = candidateRules
        self.insertionIndex = insertionIndex
        self.issues = issues
        self.overlaps = overlaps
    }

    public var canAdd: Bool { issues.isEmpty }
}

/// Builds and validates the exact ruleset that would result from accepting one
/// correction-derived rule. It never persists the result.
public enum RuleProposalPlanner {
    public static func assess(proposedRule: String, existingRules: [String]) -> RuleProposalAssessment {
        let rule = proposedRule.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = existingRules.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let currentDescriptors = (try? RoutingDecisionResolver.descriptors(for: current)) ?? []
        let catchAllID = currentDescriptors.first(where: \.isCatchAll)?.id
        let insertionIndex = catchAllID.flatMap { id in
            current.firstIndex { candidate in
                (try? RoutingDecisionResolver.descriptors(for: [candidate]).first?.id) == id
            }
        } ?? current.endIndex

        var candidate = current
        candidate.insert(rule, at: insertionIndex)
        var inspection = RuleSetInspector.inspect(candidate)

        let proposedDescriptors = (try? RoutingDecisionResolver.descriptors(for: [rule])) ?? []
        if rule.isEmpty {
            inspection = adding(
                RuleSetIssue(kind: .empty, ruleIndex: insertionIndex, message: "The proposed rule is empty."),
                to: inspection
            )
        } else if proposedDescriptors.count != 1 || proposedDescriptors.first?.isCatchAll == true {
            inspection = adding(
                RuleSetIssue(
                    kind: .invalid,
                    ruleIndex: insertionIndex,
                    message: "The proposal must be one specific destination rule beginning with ‘Put’."
                ),
                to: inspection
            )
        }

        let overlaps: [RuleProposalOverlap] = proposedDescriptors.first.map { proposed in
            currentDescriptors.enumerated().compactMap { descriptorIndex, existing -> RuleProposalOverlap? in
                guard !existing.isCatchAll,
                      subjectsOverlap(proposed.subject, existing.subject),
                      normalized(proposed.subject) != normalized(existing.subject) else { return nil }
                return RuleProposalOverlap(
                    existingRuleIndex: ruleIndex(for: existing.id, in: current) ?? descriptorIndex,
                    message: "This may overlap rule \((ruleIndex(for: existing.id, in: current) ?? descriptorIndex) + 1), which matches \(existing.subject). Preview both routes before adding it."
                )
            }
        } ?? []

        return RuleProposalAssessment(
            proposedRule: rule,
            candidateRules: candidate,
            insertionIndex: insertionIndex,
            issues: inspection.issues,
            overlaps: overlaps
        )
    }

    private static func adding(_ issue: RuleSetIssue, to inspection: RuleSetInspection) -> RuleSetInspection {
        guard !inspection.issues.contains(issue) else { return inspection }
        return RuleSetInspection(descriptors: inspection.descriptors, issues: inspection.issues + [issue])
    }

    private static func ruleIndex(for id: String, in rules: [String]) -> Int? {
        rules.firstIndex { rule in
            (try? RoutingDecisionResolver.descriptors(for: [rule]).first?.id) == id
        }
    }

    private static func subjectsOverlap(_ lhs: String, _ rhs: String) -> Bool {
        let left = Set(tokens(lhs))
        let right = Set(tokens(rhs))
        guard !left.isEmpty, !right.isEmpty else { return false }
        return left.isSubset(of: right) || right.isSubset(of: left)
    }

    private static func tokens(_ value: String) -> [String] {
        normalized(value).split(separator: " ").map(String.init).filter { token in
            !["file", "files", "document", "documents", "the", "a", "an"].contains(token)
        }
    }

    private static func normalized(_ value: String) -> String {
        value.precomposedStringWithCanonicalMapping.lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: " ")
    }
}
