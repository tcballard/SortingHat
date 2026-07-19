import Foundation
import FoundationModels

struct RulePlanGenerator: Sendable {
    func generate(from description: String) async throws -> RulePlan {
        let request = description.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !request.isEmpty else { throw RulePlanError.invalid("Describe how you want files organised.") }
        guard #available(macOS 26.0, *) else {
            throw RulePlanError.unavailable("Apple Foundation Models are unavailable. You can still edit rules manually.")
        }
        return try await generateNative(from: request)
    }

    @available(macOS 26.0, *)
    private func generateNative(from request: String) async throws -> RulePlan {
        let model = SystemLanguageModel(
            useCase: .general,
            guardrails: .permissiveContentTransformations
        )
        guard model.isAvailable else {
            throw RulePlanError.unavailable("Apple Intelligence is unavailable. Check Model Settings, or edit the rules manually.")
        }

        var lastError: Error?
        for attempt in 0..<3 {
            do {
                let session = LanguageModelSession(model: model, instructions: Self.instructions)
                let response = try await session.respond(
                    to: request,
                    schema: Self.schema,
                    options: GenerationOptions(sampling: .greedy)
                )
                var plan = try Self.plan(from: response.content)
                plan.routes.removeAll { route in
                    let folder = route.folderTemplate.trimmingCharacters(in: .whitespacesAndNewlines)
                    return folder.caseInsensitiveCompare("Inbox") == .orderedSame
                        || folder.caseInsensitiveCompare("Sorted") == .orderedSame
                        || folder.lowercased().hasPrefix("sorted/")
                }
                try RulePlanValidator.validate(plan)
                return plan
            } catch let error as RulePlanError {
                throw error
            } catch {
                lastError = error
                if attempt < 2 {
                    try? await Task.sleep(for: .milliseconds(600 * (attempt + 1)))
                }
            }
        }

        let detail = lastError?.localizedDescription ?? "The model did not return a filing plan."
        throw RulePlanError.unavailable(
            "The hat couldn’t build that plan. Try a shorter description and build it again. Your existing rules are unchanged. (\(detail))"
        )
    }

    @available(macOS 26.0, *)
    private static func plan(from content: GeneratedContent) throws -> RulePlan {
        let routeContent = try content.value([GeneratedContent].self, forProperty: "routes")
        let routes = try routeContent.map { route in
            RoutePlan(
                name: try route.value(String.self, forProperty: "name"),
                fileKinds: try route.value(String.self, forProperty: "fileKinds"),
                folderTemplate: try route.value(String.self, forProperty: "folderTemplate"),
                organisation: try route.value(String.self, forProperty: "organisation"),
                tags: try route.value([String].self, forProperty: "tags")
            )
        }
        return RulePlan(
            summary: try content.value(String.self, forProperty: "summary"),
            renamePolicy: try content.value(String.self, forProperty: "renamePolicy"),
            routes: routes,
            fallback: try content.value(String.self, forProperty: "fallback")
        )
    }

    @available(macOS 26.0, *)
    private static let schema: GenerationSchema = {
        let route = DynamicGenerationSchema(
            name: "SortingHatRoute",
            description: "One requested file group and its meaningful destination",
            properties: [
                .init(name: "name", description: "A short human-readable route name", schema: .init(type: String.self)),
                .init(name: "fileKinds", description: "The files this route should match", schema: .init(type: String.self)),
                .init(name: "folderTemplate", description: "A safe relative destination folder; placeholders such as {project} and {year} are allowed", schema: .init(type: String.self)),
                .init(name: "organisation", description: "How matching files should be grouped inside the destination", schema: .init(type: String.self)),
                .init(name: "tags", description: "A short list of useful Finder tags", schema: .init(arrayOf: .init(type: String.self), maximumElements: 8)),
            ]
        )
        let root = DynamicGenerationSchema(
            name: "SortingHatRulePlan",
            description: "A safe editable filing plan",
            properties: [
                .init(name: "summary", description: "A short plain-language summary", schema: .init(type: String.self)),
                .init(name: "renamePolicy", description: "A concise rule for descriptive filenames that preserve extensions", schema: .init(type: String.self)),
                .init(name: "routes", description: "The specific destinations requested by the person", schema: .init(arrayOf: .init(referenceTo: "SortingHatRoute"), minimumElements: 1, maximumElements: 12)),
                .init(name: "fallback", description: "A rule that leaves uncertain files in the Inbox for review", schema: .init(type: String.self)),
            ]
        )
        return try! GenerationSchema(root: root, dependencies: [route])
    }()

    private static let instructions = """
    Turn the person's filing preferences into a concise, safe Sorting Hat plan. Every route needs a human-readable name, the kinds of files it matches, a relative destination folder template, an organisation description, and useful Finder tags. Use placeholders such as {project}, {client}, {year}, or {month} when the destination depends on file contents or metadata. Never invent concrete project, client, merchant, or category names. Never output absolute paths, tilde paths, or dot/dot-dot components. Include a short descriptive renaming policy. The fallback must leave uncertain files in the Inbox for review. Do not use a generic Sorted folder.
    """
}
