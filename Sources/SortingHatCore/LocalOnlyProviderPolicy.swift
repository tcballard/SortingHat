import Foundation

/// Enforces the Mac App Store promise that extracted file context never leaves
/// the Mac. The Developer ID app and CLI retain their broader provider options.
public enum LocalOnlyProviderPolicy {
    public static let defaultOllamaURL = "http://127.0.0.1:11434"

    public static func isLoopbackOllamaURL(_ value: String) -> Bool {
        guard let components = URLComponents(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.user == nil,
              components.password == nil,
              let host = components.host?.lowercased()
        else { return false }
        return host == "localhost" || host == "127.0.0.1" || host == "::1" || host == "[::1]"
    }

    public static func validatedOllamaURL(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLoopbackOllamaURL(trimmed) else {
            throw HatError.invalidConfig("The Mac App Store build can connect only to Ollama running on this Mac (localhost, 127.0.0.1, or ::1).")
        }
        return trimmed
    }

    public static func normalized(_ original: Configuration) -> Configuration {
        var config = original
        config.openAIModel = ""
        config.allowApplePCC = false
        if config.appleModel == .pcc { config.appleModel = .system }
        if config.modelProvider == .openai { config.modelProvider = .automatic }
        if !isLoopbackOllamaURL(config.ollamaURL) {
            config.ollamaURL = defaultOllamaURL
            config.ollamaModel = ""
            if config.modelProvider == .ollama { config.modelProvider = .automatic }
        }
        return config
    }
}
