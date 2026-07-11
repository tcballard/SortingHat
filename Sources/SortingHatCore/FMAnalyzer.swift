import Foundation

public protocol FileAnalyzing: Sendable {
    func analyze(file: URL, rules: [String]) throws -> Decision
}

public struct FMAnalyzer: FileAnalyzing {
    public var executable = "/usr/bin/fm"
    public init(executable: String = "/usr/bin/fm") { self.executable = executable }

    public func analyze(file: URL, rules: [String]) throws -> Decision {
        guard FileManager.default.isExecutableFile(atPath: executable) else { throw HatError.fmUnavailable }
        let prompt = """
        You organize one file. Follow the user's rules and return only one JSON object with exactly these keys:
        {"filename":"descriptive-name.ext","folder":"relative/folder","tags":["tag"],"reason":"short explanation"}

        Rules:
        \(rules.map { "- \($0)" }.joined(separator: "\n"))

        The original filename is \(file.lastPathComponent). Preserve an appropriate file extension. Folder must be relative; never use .. or an absolute path.
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        var arguments = ["respond", prompt]
        if Self.isImage(file) { arguments.append(contentsOf: ["--image", file.path]) }
        process.arguments = arguments
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "unknown fm error"
            throw HatError.invalidResponse(message)
        }
        return try Self.decode(data)
    }

    public static func decode(_ data: Data) throws -> Decision {
        if let decision = try? JSONDecoder().decode(Decision.self, from: data) { return decision }
        let text = String(data: data, encoding: .utf8) ?? ""
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}") else {
            throw HatError.invalidResponse(text)
        }
        let json = Data(text[start...end].utf8)
        do { return try JSONDecoder().decode(Decision.self, from: json) }
        catch { throw HatError.invalidResponse(text) }
    }

    private static func isImage(_ file: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"].contains(file.pathExtension.lowercased())
    }
}
