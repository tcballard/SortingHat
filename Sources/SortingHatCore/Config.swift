import Foundation

public enum ConfigLoader {
    public static func load(_ url: URL) throws -> Configuration {
        let text = try String(contentsOf: url, encoding: .utf8)
        var config = Configuration()
        var inRules = false

        for (index, rawLine) in text.components(separatedBy: .newlines).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            if line == "rules:" { inRules = true; continue }
            if inRules, line.hasPrefix("-") {
                let rule = line.dropFirst().trimmingCharacters(in: .whitespaces)
                guard !rule.isEmpty else { throw HatError.invalidConfig("empty rule on line \(index + 1)") }
                config.rules.append(rule)
                continue
            }
            inRules = false
            guard let colon = line.firstIndex(of: ":") else {
                throw HatError.invalidConfig("expected 'key: value' on line \(index + 1)")
            }
            let key = String(line[..<colon])
            let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
            switch key {
            case "inbox": config.inbox = value
            case "settle_seconds":
                guard let seconds = Double(value), seconds >= 0 else {
                    throw HatError.invalidConfig("settle_seconds must be zero or greater")
                }
                config.settleSeconds = seconds
            case "ollama_url": config.ollamaURL = value
            case "ollama_model": config.ollamaModel = value
            case "openai_model": config.openAIModel = value
            case "model_provider":
                guard let provider = ModelProvider(rawValue: value.lowercased()) else {
                    throw HatError.invalidConfig("model_provider must be automatic, apple, ollama, or openai")
                }
                config.modelProvider = provider
            default: throw HatError.invalidConfig("unknown key '\(key)' on line \(index + 1)")
            }
        }
        guard !config.rules.isEmpty else { throw HatError.invalidConfig("add at least one rule") }
        return config
    }

    public static func save(_ config: Configuration, to url: URL) throws {
        let rules = config.rules.map { "  - \($0)" }.joined(separator: "\n")
        let text = """
        inbox: \(config.inbox)
        settle_seconds: \(config.settleSeconds.formatted(.number.precision(.fractionLength(0...3))))
        ollama_url: \(config.ollamaURL)
        ollama_model: \(config.ollamaModel)
        openai_model: \(config.openAIModel)
        model_provider: \(config.modelProvider.rawValue)
        rules:
        \(rules)
        """
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
