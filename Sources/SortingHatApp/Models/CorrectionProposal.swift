import Foundation

struct CorrectionContext: Identifiable, Sendable {
    let id: UUID
    let originalName: String
    let correctedName: String
    let destination: String
    let fileURL: URL
    let reviewReason: String
}

struct CorrectionRuleProposal: Equatable, Sendable {
    var fileKinds: String
    var destinationTemplate: String
    var renamePolicy: String
    var tags: [String]
    var reason: String

    var ruleText: String {
        var value = "Put \(fileKinds) in \(destinationTemplate)"
        let rename = renamePolicy.trimmingCharacters(in: .whitespacesAndNewlines)
        if !rename.isEmpty { value += ", rename them \(rename)" }
        let cleanTags = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        if !cleanTags.isEmpty { value += ", and tag them \(cleanTags.joined(separator: " and "))" }
        return value + "."
    }
}

enum CorrectionProposalDisposition: String, Codable, Sendable {
    case pending
    case accepted
    case edited
    case discarded
}

struct CorrectionProposalHistory: Codable, Sendable {
    let disposition: CorrectionProposalDisposition
    let rule: String?

    var summary: String {
        switch disposition {
        case .pending: "Reusable rule proposal awaiting a decision"
        case .accepted: "Reusable rule proposal accepted"
        case .edited: "Reusable rule proposal edited and accepted"
        case .discarded: "Reusable rule proposal discarded; saved rules unchanged"
        }
    }
}
