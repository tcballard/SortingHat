import Foundation

public protocol FileAnalyzing: Sendable {
    func analyze(file: URL, rules: [String]) throws -> Decision
}
