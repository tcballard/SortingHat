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
        settle_seconds: 1.5
        rules:
          - Put receipts in Finance.
          - Use lowercase names.
        """.write(to: url, atomically: true, encoding: .utf8)
        let config = try ConfigLoader.load(url)
        #expect(config.inbox == "~/Drop")
        #expect(config.settleSeconds == 1.5)
        #expect(config.rules == ["Put receipts in Finance.", "Use lowercase names."])
    }

    @Test func decodesJSONSurroundedByProse() throws {
        let data = Data("answer: {\"filename\":\"train.jpg\",\"folder\":\"Trips\",\"tags\":[\"travel\"],\"reason\":\"A train\"}".utf8)
        #expect(try FMAnalyzer.decode(data).filename == "train.jpg")
    }

    @Test func plansCollisionSafeMove() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appending(path: "Trips"), withIntermediateDirectories: true)
        let source = root.appending(path: "IMG_1234.jpg")
        let existing = root.appending(path: "Trips/train.jpg")
        FileManager.default.createFile(atPath: source.path, contents: Data())
        FileManager.default.createFile(atPath: existing.path, contents: Data())
        let analyzer = StubAnalyzer(decision: Decision(filename: "train.jpg", folder: "Trips", tags: ["travel"], reason: "A train"))
        let move = try Organizer(inbox: root, rules: ["Sort it"], analyzer: analyzer).plan(source)
        #expect(move.destination.lastPathComponent == "train-2.jpg")
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
