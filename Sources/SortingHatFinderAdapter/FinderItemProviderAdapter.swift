import AppKit
import Foundation
import SortingHatCore
import UniformTypeIdentifiers

/// The small Finder transport boundary around NSItemProvider. Import policy,
/// collision handling, and durable copying remain in SortingHatCore.
public enum FinderItemProviderAdapter {
    @discardableResult
    public static func loadFileURL(
        from provider: NSItemProvider,
        completion: @escaping @Sendable (Result<URL, FinderItemProviderError>) -> Void
    ) -> Progress {
        provider.loadDataRepresentation(forTypeIdentifier: UTType.fileURL.identifier) { data, error in
            guard let data, let url = FileURLRepresentationDecoder.decode(data) else {
                completion(.failure(FinderItemProviderError(
                    message: error?.localizedDescription
                        ?? "Finder could not make the selected file URL available."
                )))
                return
            }
            completion(.success(url))
        }
    }
}

public struct FinderActionBatchPolicy: Equatable, Sendable {
    public static let productDefault = FinderActionBatchPolicy(
        maximumItems: 256,
        maximumFileBytes: 256 * 1_024 * 1_024,
        maximumTotalBytes: 1_024 * 1_024 * 1_024,
        timeoutSeconds: 25
    )

    public let maximumItems: Int
    public let maximumFileBytes: Int64
    public let maximumTotalBytes: Int64
    public let timeoutSeconds: TimeInterval

    public init(
        maximumItems: Int,
        maximumFileBytes: Int64,
        maximumTotalBytes: Int64,
        timeoutSeconds: TimeInterval
    ) {
        self.maximumItems = maximumItems
        self.maximumFileBytes = maximumFileBytes
        self.maximumTotalBytes = maximumTotalBytes
        self.timeoutSeconds = timeoutSeconds
    }

    public func itemCountIsAllowed(_ count: Int) -> Bool {
        count > 0 && count <= maximumItems
    }

    public func limitForFile(byteCount: Int64, alreadyAccepted: Int64) -> FinderActionBatchLimit? {
        guard byteCount >= 0 else { return .unknownFileSize }
        guard byteCount <= maximumFileBytes else { return .fileTooLarge(maximumBytes: maximumFileBytes) }
        guard alreadyAccepted <= maximumTotalBytes - byteCount else {
            return .batchTooLarge(maximumBytes: maximumTotalBytes)
        }
        return nil
    }
}

public enum FinderActionBatchLimit: Equatable, Sendable {
    case unknownFileSize
    case fileTooLarge(maximumBytes: Int64)
    case batchTooLarge(maximumBytes: Int64)
}

public struct FinderItemProviderError: Error, LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
