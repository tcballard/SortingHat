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
}

public enum ModelProvider: String, CaseIterable, Sendable {
    case automatic, apple, ollama, openai
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

public enum HatError: Error, LocalizedError {
    case invalidConfig(String)
    case fmUnavailable
    case invalidResponse(String)
    case invalidDecision(String)
    case unsafePath(String)
    case noModelProvider

    public var errorDescription: String? {
        switch self {
        case .invalidConfig(let message): "Invalid config: \(message)"
        case .fmUnavailable: "Apple's on-device Foundation Model is unavailable. It requires macOS 27, Apple Intelligence, and a downloaded system model."
        case .invalidResponse(let response): "fm returned an invalid decision: \(response)"
        case .invalidDecision(let message): "Invalid sorting decision: \(message)"
        case .unsafePath(let path): "Refusing unsafe path from model: \(path)"
        case .noModelProvider: "Apple's on-device Foundation Model is unavailable. Configure Ollama or OpenAI in Model Settings to sort on this Mac."
        }
    }
}
