import Foundation

struct RulePlan: Codable, Equatable, Sendable {
    var summary: String
    var renamePolicy: String
    var routes: [RoutePlan]
    var fallback: String

    var routeRules: [String] {
        routes.map { route in
            var rule = "Put \(route.fileKinds) in \(route.folderTemplate)"
            if !route.organisation.isEmpty { rule += ", organised by \(route.organisation)" }
            if !route.tags.isEmpty { rule += ", and tag them \(route.tags.joined(separator: " and "))" }
            return rule + "."
        }
    }

    var compiledRules: [String] {
        [renamePolicy] + routeRules + [fallback]
    }
}

struct RoutePlan: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var name: String
    var fileKinds: String
    var folderTemplate: String
    var organisation: String
    var tags: [String]

    enum CodingKeys: String, CodingKey { case name, fileKinds, folderTemplate, organisation, tags }
}

enum RulePlanValidator {
    static func validate(_ plan: RulePlan) throws {
        guard !plan.renamePolicy.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RulePlanError.invalid("Add a filename policy.")
        }
        guard !plan.routes.isEmpty else { throw RulePlanError.invalid("Add at least one destination.") }
        for route in plan.routes {
            let folder = route.folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !folder.isEmpty, !folder.hasPrefix("/"), !folder.hasPrefix("~"),
                  !folder.split(separator: "/").contains(where: { $0 == "." || $0 == ".." }) else {
                throw RulePlanError.invalid("\(route.name) has an unsafe destination.")
            }
            guard folder.caseInsensitiveCompare("Inbox") != .orderedSame,
                  folder.caseInsensitiveCompare("Sorted") != .orderedSame,
                  !folder.lowercased().hasPrefix("sorted/") else {
                throw RulePlanError.invalid("Give \(route.name) a meaningful destination instead of a generic holding folder.")
            }
        }
        guard !plan.fallback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw RulePlanError.invalid("Choose what happens to uncertain files.")
        }
    }
}

enum RulePlanError: LocalizedError {
    case invalid(String)
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .unavailable(let message): message
        }
    }
}
