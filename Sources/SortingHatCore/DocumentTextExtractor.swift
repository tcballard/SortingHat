import AppKit
import Foundation
import PDFKit
import Vision

public struct ExtractedDocumentText: Equatable, Sendable {
    public enum Source: String, Equatable, Sendable {
        case embeddedPDF
        case opticalCharacterRecognition
        case plainText
        case convertedDocument
    }

    public let text: String
    public let source: Source
    public let confidence: Float?
    public let pagesProcessed: Int
}

public enum DocumentTextExtractor {
    public static let defaultCharacterLimit = 12_000
    public static let defaultPageLimit = 5
    public static let minimumOCRConfidence: Float = 0.3

    public static func extract(
        from file: URL,
        characterLimit: Int = defaultCharacterLimit,
        pageLimit: Int = defaultPageLimit
    ) -> String? {
        try? extractContent(from: file, characterLimit: characterLimit, pageLimit: pageLimit)?.text
    }

    public static func extractContent(
        from file: URL,
        characterLimit: Int = defaultCharacterLimit,
        pageLimit: Int = defaultPageLimit
    ) throws -> ExtractedDocumentText? {
        guard characterLimit > 0, pageLimit > 0 else { return nil }
        switch file.pathExtension.lowercased() {
        case "pdf":
            return try extractPDF(file, characterLimit: characterLimit, pageLimit: pageLimit)
        case "jpg", "jpeg", "png", "heic", "gif", "tiff", "webp":
            guard let image = loadCGImage(file) else { return nil }
            return try recognize([image], characterLimit: characterLimit)
        case "txt", "md", "markdown", "csv", "tsv", "json", "yaml", "yml", "xml", "html", "htm", "log":
            return result(decodeTextFile(file), source: .plainText, characterLimit: characterLimit)
        case "rtf", "rtfd", "doc", "docx", "odt":
            return result(convertDocumentToText(file), source: .convertedDocument, characterLimit: characterLimit)
        default:
            return nil
        }
    }

    private static func extractPDF(_ file: URL, characterLimit: Int, pageLimit: Int) throws -> ExtractedDocumentText? {
        guard let document = PDFDocument(url: file) else {
            throw HatError.contentExtractionFailed("could not open PDF: \(file.lastPathComponent)")
        }
        let count = min(document.pageCount, pageLimit)
        let embeddedText = (0..<count).compactMap { document.page(at: $0)?.string }.joined(separator: "\n")
        if let embedded = result(
            embeddedText,
            source: .embeddedPDF,
            characterLimit: characterLimit,
            pagesProcessed: count
        ) {
            return embedded
        }

        guard count > 0 else {
            throw HatError.contentExtractionFailed("PDF has no readable pages: \(file.lastPathComponent)")
        }
        let images = (0..<count).compactMap { index in
            document.page(at: index).flatMap(renderForOCR)
        }
        guard images.count == count else {
            throw HatError.contentExtractionFailed("could not render every PDF page selected for OCR: \(file.lastPathComponent)")
        }
        guard let recognized = try recognize(images, characterLimit: characterLimit) else {
            throw HatError.contentExtractionFailed("OCR found no readable text in the first \(count) page(s): \(file.lastPathComponent)")
        }
        return recognized
    }

    private static func recognize(_ images: [CGImage], characterLimit: Int) throws -> ExtractedDocumentText? {
        var lines: [String] = []
        var confidences: [Float] = []

        for image in images {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            let handler = VNImageRequestHandler(cgImage: image)
            do {
                try handler.perform([request])
            } catch {
                throw HatError.contentExtractionFailed("Vision OCR failed: \(error.localizedDescription)")
            }
            for observation in request.results ?? [] {
                guard let candidate = observation.topCandidates(1).first,
                      candidate.confidence >= minimumOCRConfidence else { continue }
                lines.append(candidate.string)
                confidences.append(candidate.confidence)
            }
        }

        guard let cleaned = clean(lines.joined(separator: "\n"), characterLimit: characterLimit) else { return nil }
        let confidence = confidences.isEmpty ? nil : confidences.reduce(0, +) / Float(confidences.count)
        return ExtractedDocumentText(
            text: cleaned,
            source: .opticalCharacterRecognition,
            confidence: confidence,
            pagesProcessed: images.count
        )
    }

    private static func renderForOCR(_ page: PDFPage) -> CGImage? {
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let maximumDimension: CGFloat = 2_400
        let scale = min(3, maximumDimension / max(bounds.width, bounds.height))
        let size = NSSize(width: max(1, bounds.width * scale), height: max(1, bounds.height * scale))
        let thumbnail = page.thumbnail(of: size, for: .mediaBox)
        return thumbnail.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func loadCGImage(_ file: URL) -> CGImage? {
        NSImage(contentsOf: file)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private static func result(
        _ text: String?,
        source: ExtractedDocumentText.Source,
        characterLimit: Int,
        pagesProcessed: Int = 0
    ) -> ExtractedDocumentText? {
        guard let cleaned = clean(text, characterLimit: characterLimit) else { return nil }
        return ExtractedDocumentText(text: cleaned, source: source, confidence: nil, pagesProcessed: pagesProcessed)
    }

    private static func clean(_ text: String?, characterLimit: Int) -> String? {
        guard let text else { return nil }
        let cleaned = text.replacingOccurrences(of: "\0", with: "")
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
        let converted = FileManager.default.temporaryDirectory.appending(path: "sorting-hat-\(UUID().uuidString).txt")
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
