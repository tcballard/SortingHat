import Foundation

public enum FilingPreviewStatus: String, Equatable, Sendable {
    case ready = "Ready"
    case needsReview = "Needs review"
    case invalid = "Blocked"
}

public struct FilingPreview: Equatable, Sendable, Identifiable {
    public let source: URL
    public let status: FilingPreviewStatus
    public let proposedFilename: String?
    public let destination: URL?
    public let renderedFolder: String?
    public let tags: [String]
    public let reason: String
    public let matchedRuleID: String?
    public let matchedRuleSubject: String?
    public let destinationValues: [DestinationValue]

    public init(
        source: URL,
        status: FilingPreviewStatus,
        proposedFilename: String? = nil,
        destination: URL? = nil,
        renderedFolder: String? = nil,
        tags: [String] = [],
        reason: String,
        matchedRuleID: String? = nil,
        matchedRuleSubject: String? = nil,
        destinationValues: [DestinationValue] = []
    ) {
        self.source = source
        self.status = status
        self.proposedFilename = proposedFilename
        self.destination = destination
        self.renderedFolder = renderedFolder
        self.tags = tags
        self.reason = reason
        self.matchedRuleID = matchedRuleID
        self.matchedRuleSubject = matchedRuleSubject
        self.destinationValues = destinationValues
    }

    public var id: String { source.standardizedFileURL.path }
}
