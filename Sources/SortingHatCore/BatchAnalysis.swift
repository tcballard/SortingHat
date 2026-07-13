import Foundation

public struct BatchFileInput: Sendable {
    public let id: String
    public let file: URL

    public init(id: String, file: URL) {
        self.id = id
        self.file = file
    }
}

public struct BatchDecision: Codable, Equatable, Sendable {
    public let sourceID: String
    public let filename: String
    public let folder: String
    public let tags: [String]
    public let reason: String

    enum CodingKeys: String, CodingKey {
        case sourceID = "source_id"
        case filename, folder, tags, reason
    }

    public var decision: Decision {
        Decision(filename: filename, folder: folder, tags: tags, reason: reason)
    }
}

public enum BatchAnalysisOutcome: Sendable {
    case decision(sourceID: String, Decision)
    case failure(sourceID: String, HatError)
}

public protocol BatchFileAnalyzing: FileAnalyzing {
    func analyzeBatch(files: [BatchFileInput], rules: [String]) -> [BatchAnalysisOutcome]
}

public enum PlanningOutcome {
    case success(PlannedMove)
    case failure(source: URL, error: Error)

    public var source: URL {
        switch self {
        case .success(let move): move.source
        case .failure(let source, _): source
        }
    }
}
