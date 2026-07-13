import Foundation

public protocol FileAnalyzing: Sendable {
    func analyze(file: URL, rules: [String]) throws -> Decision
}

/// Analyzes files with the on-device Apple Foundation Model exposed by macOS's
/// `fm` command-line interface.
public struct FMAnalyzer: FileAnalyzing {
    public let executable: String

    public init(executable: String = "/usr/bin/fm") {
        self.executable = executable
    }

    /// Checks that the system model is ready, rather than merely checking that
    /// the `fm` executable exists.
    public var isAvailable: Bool {
        guard FileManager.default.isExecutableFile(atPath: executable) else { return false }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["available", "--model", "system"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }

    public func analyze(file: URL, rules: [String]) throws -> Decision {
        guard isAvailable else { throw HatError.fmUnavailable }

        let schemaURL = FileManager.default.temporaryDirectory
            .appending(path: "sorting-hat-\(UUID().uuidString).schema.json")
        try Self.schema.write(to: schemaURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: schemaURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = Self.commandArguments(file: file, rules: rules, schemaURL: schemaURL)
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()

        let data = output.fileHandleForReading.readDataToEndOfFile()
        if process.terminationStatus != 0 {
            let errorData = errors.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: errorData, encoding: .utf8) ?? "unknown fm error"
            throw HatError.invalidResponse(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return try Self.decode(data)
    }

    static func commandArguments(file: URL, rules: [String], schemaURL: URL) -> [String] {
        var arguments = [
            "respond",
            "--model", "system",
            "--instructions", Self.instructions,
            "--schema", schemaURL.path,
            "--no-stream",
            "--greedy",
        ]
        let prompt = Self.prompt(file: file, rules: rules)
        if Self.isImage(file) {
            arguments.append(contentsOf: ["--image", file.path, "--text", prompt])
        } else {
            arguments.append(prompt)
        }
        return arguments
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

    private static let instructions = """
    You organize one file at a time according to the person's rules. Choose a safe relative destination folder, a descriptive filename, useful Finder tags, and a concise reason. Never use an absolute path, a tilde, or dot/dot-dot path components. Preserve an appropriate file extension.
    """

    private static func prompt(file: URL, rules: [String]) -> String {
        """
        Organize the file named "\(file.lastPathComponent)".

        Rules:
        \(rules.map { "- \($0)" }.joined(separator: "\n"))
        """
    }

    private static let schema = Data(#"""
    {
      "required": ["filename", "folder", "tags", "reason"],
      "additionalProperties": false,
      "x-order": ["filename", "folder", "tags", "reason"],
      "type": "object",
      "title": "SortingDecision",
      "properties": {
        "filename": {
          "description": "A descriptive filename with the original file extension",
          "type": "string"
        },
        "folder": {
          "description": "A relative folder path without dot or dot-dot components",
          "type": "string"
        },
        "tags": {
          "description": "A short list of useful Finder tags",
          "items": { "type": "string" },
          "type": "array"
        },
        "reason": {
          "description": "A concise explanation of the decision",
          "type": "string"
        }
      }
    }
    """#.utf8)

    private static func isImage(_ file: URL) -> Bool {
        ["jpg", "jpeg", "png", "heic", "gif", "tiff", "webp"].contains(file.pathExtension.lowercased())
    }
}
