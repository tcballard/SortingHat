import Foundation

struct RulePlanGenerator: Sendable {
    let executable: String

    init(executable: String = "/usr/bin/fm") { self.executable = executable }

    func generate(from description: String) throws -> RulePlan {
        let request = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { throw RulePlanError.invalid("Describe how you want files organised.") }
        guard FileManager.default.isExecutableFile(atPath: executable) else {
            throw RulePlanError.unavailable("Apple Foundation Models are unavailable. You can still edit rules manually.")
        }

        let schemaURL = FileManager.default.temporaryDirectory.appending(path: "sortinghat-rule-plan-\(UUID().uuidString).json")
        try Self.schema.write(to: schemaURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: schemaURL) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = [
            "respond", "--model", "system",
            "--instructions", Self.instructions,
            "--schema", schemaURL.path,
            "--no-stream", "--greedy",
            request,
        ]
        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "Rule generation failed."
            let detail = Self.strippingTerminalFormatting(from: message)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.localizedCaseInsensitiveContains("invalid schema") {
                throw RulePlanError.unavailable("The hat couldn’t prepare the rule builder. Please try again after updating Sorting Hat.")
            }
            throw RulePlanError.unavailable(detail.isEmpty ? "The hat couldn’t build that plan. Try describing it another way." : detail)
        }
        var plan = try JSONDecoder().decode(RulePlan.self, from: output.fileHandleForReading.readDataToEndOfFile())
        plan.routes.removeAll { route in
            let folder = route.folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            return folder.caseInsensitiveCompare("Inbox") == .orderedSame
                || folder.caseInsensitiveCompare("Sorted") == .orderedSame
                || folder.lowercased().hasPrefix("sorted/")
        }
        try RulePlanValidator.validate(plan)
        return plan
    }

    private static let instructions = """
    Turn the person's filing preferences into a concise, safe Sorting Hat plan. Every route needs a human-readable name, the kinds of files it matches, a relative destination folder template, an organisation description, and useful Finder tags. Never output absolute paths, tilde paths, or dot/dot-dot components. Include a short descriptive renaming policy. The fallback must leave uncertain files in the Inbox for review. Do not use a generic Sorted folder.
    """

    private static let schema = Data(#"""
    {
      "title": "SortingHatRulePlan",
      "$defs": {
        "SortingHatRoute": {
          "additionalProperties": false,
          "type": "object",
          "title": "SortingHatRoute",
          "properties": {
            "name": { "description": "A short name for this route", "type": "string" },
            "fileKinds": { "description": "The files this route should match", "type": "string" },
            "folderTemplate": { "description": "A safe relative destination folder without a leading slash", "type": "string" },
            "organisation": { "description": "How files should be grouped inside the destination", "type": "string" },
            "tags": { "description": "Useful Finder tags", "type": "array", "items": { "type": "string" } }
          },
          "required": ["name", "fileKinds", "folderTemplate", "organisation", "tags"],
          "x-order": ["name", "fileKinds", "folderTemplate", "organisation", "tags"]
        }
      },
      "type": "object",
      "x-order": ["summary", "renamePolicy", "routes", "fallback"],
      "properties": {
        "summary": {
          "description": "A short plain-language summary of the filing plan",
          "type": "string"
        },
        "renamePolicy": {
          "description": "A concise rule for producing descriptive filenames while preserving file extensions",
          "type": "string"
        },
        "routes": {
          "description": "The specific file groups and relative folders the person requested",
          "type": "array",
          "items": {
            "$ref": "#/$defs/SortingHatRoute"
          }
        },
        "fallback": {
          "description": "A rule that leaves uncertain files in the Inbox for review",
          "type": "string"
        }
      },
      "required": ["summary", "renamePolicy", "routes", "fallback"],
      "additionalProperties": false
    }
    """#.utf8)

    private static func strippingTerminalFormatting(from value: String) -> String {
        value.replacingOccurrences(
            of: #"\u001B\[[0-9;:]*[A-Za-z]"#,
            with: "",
            options: .regularExpression
        )
    }
}
