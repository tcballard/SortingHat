import Foundation
import Testing
@testable import SortingHatCore

struct StubAnalyzer: FileAnalyzing {
    let decision: Decision
    func analyze(file: URL, rules: [String]) throws -> Decision { decision }
}

@Suite(.serialized)
struct SortingHatTests {
    @Test func parsesHumanReadableConfig() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try """
        inbox: ~/Drop
        output: ~/Filed
        settle_seconds: 1.5
        rules:
          - Put receipts in Finance.
          - Use lowercase names.
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigLoader.load(url)
        #expect(config.inbox == "~/Drop")
        #expect(config.output == "~/Filed")
        #expect(config.settleSeconds == 1.5)
        #expect(config.rules == ["Put receipts in Finance.", "Use lowercase names."])
    }

    @Test func decodesJSONSurroundedByProse() throws {
        let data = Data("answer: {\"filename\":\"train.jpg\",\"folder\":\"Trips\",\"tags\":[\"travel\"],\"reason\":\"A train\"}".utf8)
        #expect(try FMAnalyzer.decode(data).filename == "train.jpg")
    }

    @Test func configuresAppleStructuredImageRequest() {
        let file = URL(fileURLWithPath: "/tmp/receipt.png")
        let schema = URL(fileURLWithPath: "/tmp/decision.schema.json")
        let arguments = FMAnalyzer.commandArguments(file: file, rules: ["File receipts by year."], schemaURL: schema)
        #expect(arguments.starts(with: ["respond", "--model", "system"]))
        #expect(arguments.contains("--schema"))
        #expect(arguments.contains("--no-stream"))
        #expect(arguments.contains("--greedy"))
        #expect(arguments.contains("--image"))
        #expect(arguments.contains("--text"))
        #expect(arguments.contains { $0.contains("File receipts by year.") })
    }

    @Test func plansCollisionSafeMove() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        let inbox = root.appending(path: "Inbox")
        let output = root.appending(path: "Library")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: output.appending(path: "Trips"), withIntermediateDirectories: true)
        let source = inbox.appending(path: "IMG_1234.jpg")
        let existing = output.appending(path: "Trips/train.jpg")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        FileManager.default.createFile(atPath: existing.path, contents: Data())
        let analyzer = StubAnalyzer(decision: Decision(filename: "train.jpg", folder: "Trips", tags: ["travel"], reason: "A train"))
        let move = try Organizer(inbox: inbox, output: output, rules: ["Sort it"], analyzer: analyzer).plan(source)
        #expect(move.destination.lastPathComponent == "train-2.jpg")
        #expect(move.destination.deletingLastPathComponent().standardizedFileURL.path == output.appending(path: "Trips").standardizedFileURL.path)
        try Organizer(inbox: inbox, output: output, rules: ["Sort it"], analyzer: analyzer).apply(move)
        #expect(!FileManager.default.fileExists(atPath: source.path))
        #expect(FileManager.default.fileExists(atPath: move.destination.path))
    }

    @Test func rejectsModelPathTraversal() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appending(path: "note.txt")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        let analyzer = StubAnalyzer(decision: Decision(filename: "note.txt", folder: "../Escape", tags: [], reason: "bad"))
        #expect(throws: HatError.self) { try Organizer(inbox: root, rules: ["Sort"], analyzer: analyzer).plan(source) }
    }
}
