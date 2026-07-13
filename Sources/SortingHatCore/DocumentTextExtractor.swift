import Foundation
import PDFKit

public enum DocumentTextExtractor {
    public static let defaultCharacterLimit = 12_000

    public static func extract(from file: URL, characterLimit: Int = defaultCharacterLimit) -> String? {
        guard characterLimit > 0 else { return nil }
        let extensionName = file.pathExtension.lowercased()
        let text: String?

        switch extensionName {
        case "pdf":
            text = PDFDocument(url: file)?.string
        case "txt", "md", "markdown", "csv", "tsv", "json", "yaml", "yml", "xml", "html", "htm", "log":
            text = decodeTextFile(file)
        case "rtf", "rtfd", "doc", "docx", "odt":
            text = convertDocumentToText(file)
        default:
            text = nil
        }

        guard let text else { return nil }
        let cleaned = text
            .replacingOccurrences(of: "\0", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else { return nil }
        return String(cleaned.prefix(characterLimit))
    }

    private static func decodeTextFile(_ file: URL) -> String? {
        guard let data = try? Data(contentsOf: file) else { return nil }
        for encoding in [String.Encoding.utf8, .utf16, .unicode, .isoLatin1] {
            if let text = String(data: data, encoding: encoding) { return text }
        }
        return nil
    }

    private static func convertDocumentToText(_ file: URL) -> String? {
        let executable = "/usr/bin/textutil"
        guard FileManager.default.isExecutableFile(atPath: executable) else { return nil }
        let converted = FileManager.default.temporaryDirectory
            .appending(path: "sorting-hat-\(UUID().uuidString).txt")
        defer { try? FileManager.default.removeItem(at: converted) }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-convert", "txt", "-output", converted.path, file.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return try? String(contentsOf: converted, encoding: .utf8)
        } catch {
            return nil
        }
    }
}
