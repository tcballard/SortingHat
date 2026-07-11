import Foundation

public struct PreferredAnalyzer: FileAnalyzing {
    public let fm: FMAnalyzer
    public let ollama: OllamaAnalyzer?
    public let openAI: OpenAIAnalyzer?
    public let provider: ModelProvider

    public init(fmExecutable: String = "/usr/bin/fm", ollamaURL: String, ollamaModel: String, openAIModel: String = "", openAIKey: String = "", provider: ModelProvider = .automatic) {
        fm = FMAnalyzer(executable: fmExecutable)
        let model = ollamaModel.trimmingCharacters(in: .whitespacesAndNewlines)
        ollama = model.isEmpty ? nil : OllamaAnalyzer(baseURL: ollamaURL, model: model)
        let cloudModel = openAIModel.trimmingCharacters(in: .whitespacesAndNewlines)
        openAI = cloudModel.isEmpty || openAIKey.isEmpty ? nil : OpenAIAnalyzer(model: cloudModel, apiKey: openAIKey)
        self.provider = provider
    }

    public func analyze(file: URL, rules: [String]) throws -> Decision {
        let hasApple = FileManager.default.isExecutableFile(atPath: fm.executable)
        switch provider {
        case .apple:
            guard hasApple else { throw HatError.fmUnavailable }
            return try fm.analyze(file: file, rules: rules)
        case .ollama:
            guard let ollama else { throw HatError.invalidConfig("configure an Ollama model in Model Settings") }
            return try ollama.analyze(file: file, rules: rules)
        case .openai:
            guard let openAI else { throw HatError.invalidConfig("configure an OpenAI model and API key in Model Settings") }
            return try openAI.analyze(file: file, rules: rules)
        case .automatic:
            if hasApple { return try fm.analyze(file: file, rules: rules) }
            if let ollama { return try ollama.analyze(file: file, rules: rules) }
            if let openAI { return try openAI.analyze(file: file, rules: rules) }
            throw HatError.noModelProvider
        }
    }
}

public struct OllamaAnalyzer: FileAnalyzing {
    public let baseURL: String
    public let model: String

    public init(baseURL: String = "http://127.0.0.1:11434", model: String) {
        self.baseURL = baseURL
        self.model = model
    }

    public func analyze(file: URL, rules: [String]) throws -> Decision {
        guard let url = URL(string: baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + "/api/chat") else {
            throw HatError.invalidConfig("ollama_url is not a valid URL")
        }
        var message: [String: Any] = ["role": "user", "content": Self.prompt(file: file, rules: rules)]
        if Self.isImage(file), let data = try? Data(contentsOf: file) {
            message["images"] = [data.base64EncodedString()]
        }
        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "format": "json",
            "messages": [message]
        ]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Data, Error>?
        URLSession.shared.dataTask(with: request) { data, response, error in
            defer { semaphore.signal() }
            if let error { result = .failure(error); return }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode), let data else {
                let detail = data.flatMap { String(data: $0, encoding: .utf8) } ?? "Ollama did not respond"
                result = .failure(HatError.invalidResponse(detail)); return
            }
            result = .success(data)
        }.resume()
        semaphore.wait()
        let data = try result!.get()
        let envelope = try JSONDecoder().decode(ChatResponse.self, from: data)
        return try FMAnalyzer.decode(Data(envelope.message.content.utf8))
    }

    private struct ChatResponse: Decodable { let message: Message }
    private struct Message: Decodable { let content: String }

    private static func prompt(file: URL, rules: [String]) -> String {
        """
        Organize one file. Return only JSON with exactly these keys:
        {"filename":"descriptive-name.ext","folder":"relative/folder","tags":["tag"],"reason":"short explanation"}
        Rules:\n\(rules.map { "- \($0)" }.joined(separator: "\n"))
        Original filename: \(file.lastPathComponent). Preserve the extension. Folder must be relative and must not contain ...
        """
    }

    private static func isImage(_ file: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"].contains(file.pathExtension.lowercased())
    }
}
