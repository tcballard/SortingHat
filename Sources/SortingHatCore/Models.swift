import Foundation

public struct Configuration: Equatable, Sendable {
    public var inbox: String = "~/SortingHat/Inbox"
    public var output: String = "~/SortingHat"
    public var rules: [String] = []
    public var settleSeconds: Double = 2
    public var ollamaURL: String = "http://127.0.0.1:11434"
    public var ollamaModel: String = ""
    public var openAIModel: String = ""
    public var modelProvider: ModelProvider = .automatic
    public var appleModel: AppleModelSelection = .automatic
    public var appleUseCase: AppleUseCase = .general
    public var appleGuardrails: AppleGuardrails = .default
    public var allowApplePCC = false
}

public enum ModelProvider: String, CaseIterable, Sendable {
    case automatic, apple, ollama, openai
}

public enum AppleModelSelection: String, CaseIterable, Sendable {
    case automatic
    case system
    case pcc
}

public enum AppleUseCase: String, CaseIterable, Sendable {
    case general
    case contentTagging = "content-tagging"
}

public enum AppleGuardrails: String, CaseIterable, Sendable {
    case `default`
    case permissiveContentTransformations = "permissive-content-transformations"
}

public struct Decision: Codable, Equatable, Sendable {
    public let filename: String
    public let folder: String
    public let tags: [String]
    public let reason: String
    public init(filename: String, folder: String, tags: [String], reason: String) {
        self.filename = filename; self.folder = folder; self.tags = tags; self.reason = reason
    }
}

public struct PlannedMove: Equatable, Sendable {
    public let source: URL
    public let destination: URL
    public let tags: [String]
    public let reason: String
}

public enum HatError: Error, LocalizedError, Sendable {
    case invalidConfig(String)
    case fmUnavailable
    case pccConsentRequired
    case pccUnavailable(String)
    case pccLimitReached(String)
    case invalidResponse(String)
    case invalidDecision(String)
    case needsReview(String)
    case contentExtractionFailed(String)
    case unsafePath(String)
    case noModelProvider
    case invalidBatch(String)

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let message): "Invalid config: \(message)"
        case .fmUnavailable: "Apple's on-device Foundation Model is unavailable. It requires macOS 27, Apple Intelligence, and a downloaded system model."
        case .pccConsentRequired: "Private Cloud Compute requires explicit permission in Model Settings before files can be sent to Apple."
        case .pccUnavailable(let message): "Apple Private Cloud Compute is unavailable: \(message)"
        case .pccLimitReached(let message): "Apple Private Cloud Compute usage limit was reached: \(message)"
        case .invalidResponse(let response): "fm returned an invalid decision: \(response)"
        case .invalidDecision(let message): "Invalid sorting decision: \(message)"
        case .needsReview(let message): "Needs review: \(message)"
        case .contentExtractionFailed(let message): "Could not read file content: \(message)"
        case .unsafePath(let path): "Refusing unsafe path from model: \(path)"
        case .noModelProvider: "Apple's on-device Foundation Model is unavailable. Configure Ollama or OpenAI in Model Settings to sort on this Mac."
        case .invalidBatch(let message): "Invalid batch decision: \(message)"
        }
    }
}
