import Foundation
import FoundationModels
import SortingHatCore

struct CorrectionProposalGenerator: Sendable {
    func generate(for correction: CorrectionContext) async throws -> CorrectionRuleProposal {
        guard #available(macOS 26.0, *) else {
            throw RulePlanError.unavailable("Apple Foundation Models are unavailable. The correction is filed, and no rule was changed.")
        }

        let excerpt = await Task.detached(priority: .userInitiated) {
            DocumentTextExtractor.extract(from: correction.fileURL, characterLimit: 2_000, pageLimit: 2)
        }.value
        return try await generateNative(for: correction, excerpt: excerpt)
    }

    @available(macOS 26.0, *)
    private func generateNative(for correction: CorrectionContext, excerpt: String?) async throws -> CorrectionRuleProposal {
        let model = SystemLanguageModel(useCase: .general, guardrails: .permissiveContentTransformations)
        guard model.isAvailable else {
            throw RulePlanError.unavailable("Apple Intelligence is unavailable. The correction is filed, and no rule was changed.")
        }

        let prompt = """
        ORIGINAL NAME: \(correction.originalName)
        CORRECTED NAME: \(correction.correctedName)
        CORRECT DESTINATION: \(correction.destination)
        WHY REVIEW WAS NEEDED: \(correction.reviewReason)
        LOCAL CONTENT EXCERPT: \(excerpt ?? "No readable text was available.")
        """

        var lastError: Error?
        var feedback = ""
        for attempt in 0..<3 {
            do {
                let session = LanguageModelSession(model: model, instructions: Self.instructions)
                let response = try await session.respond(
                    to: prompt + feedback,
                    schema: Self.schema,
                    options: GenerationOptions(sampling: .greedy)
                )
                let content = response.content
                let proposal = CorrectionRuleProposal(
                    fileKinds: try content.value(String.self, forProperty: "fileKinds"),
                    destinationTemplate: try content.value(String.self, forProperty: "destinationTemplate"),
                    renamePolicy: try content.value(String.self, forProperty: "renamePolicy"),
                    tags: try content.value([String].self, forProperty: "tags"),
                    reason: try content.value(String.self, forProperty: "reason")
                )
                try RoutingDecisionResolver.validateDestinationTemplate(proposal.destinationTemplate)
                try Self.validateReusableDestination(proposal.destinationTemplate)
                let assessment = RuleProposalPlanner.assess(proposedRule: proposal.ruleText, existingRules: [])
                guard assessment.canAdd else {
                    throw RulePlanError.invalid(assessment.issues.map { $0.message }.joined(separator: " "))
                }
                return proposal
            } catch {
                lastError = error
                feedback = """

                CORRECTION REQUIRED: The previous proposal was invalid: \(error.localizedDescription)
                Return a new proposal. A variable must occupy an entire slash-separated component. The only exact variable names are {merchant}, {client}, {project}, {source-app}, {year}, {month}, and {year-month}. Never output {vendor}, {category}, or combine variables such as {year}-{month}.
                """
                if attempt < 2 { try? await Task.sleep(for: .milliseconds(400 * (attempt + 1))) }
            }
        }

        throw RulePlanError.unavailable(
            "The correction is filed, but the hat couldn’t produce a safe reusable rule. Your existing rules are unchanged. (\(lastError?.localizedDescription ?? "Invalid proposal"))"
        )
    }

    @available(macOS 26.0, *)
    private static let schema: GenerationSchema = {
        let root = DynamicGenerationSchema(
            name: "SortingHatCorrectionRuleProposal",
            description: "One reusable filing rule inferred from a person's correction",
            properties: [
                .init(name: "fileKinds", description: "A concise plural description of files sharing durable content traits; never a single filename or concrete merchant, client, or project", schema: .init(type: String.self)),
                .init(name: "destinationTemplate", description: "A safe relative destination generalized from the correction, using fixed components or only {merchant}, {client}, {project}, {source-app}, {year}, {month}, or {year-month} as whole path components", schema: .init(type: String.self)),
                .init(name: "renamePolicy", description: "A concise reusable filename pattern that preserves the original extension and does not contain a concrete corrected filename", schema: .init(type: String.self)),
                .init(name: "tags", description: "Zero to four reusable Finder tags, excluding concrete names unless the rule intentionally matches that fixed identity", schema: .init(arrayOf: .init(type: String.self), maximumElements: 4)),
                .init(name: "reason", description: "One sentence explaining the evidence and which destination values are variable versus fixed", schema: .init(type: String.self)),
            ]
        )
        return try! GenerationSchema(root: root, dependencies: [])
    }()

    private static let instructions = """
    Propose one narrow, reusable Sorting Hat route from a manual correction. Generalize only what the evidence supports. Do not claim that one example proves a broad category. Use a controlled destination variable only when the corrected destination or content clearly supplies that concept; otherwise retain a meaningful fixed folder component. Never use absolute paths, tilde paths, dot components, unknown placeholders, a generic Sorted folder, or the Inbox. The proposal is advisory and must remain understandable and editable. All processing is local to this Mac.
    """

    private static func validateReusableDestination(_ template: String) throws {
        for component in template.split(separator: "/").map(String.init) {
            if let year = Int(component), (1900...2200).contains(year) {
                throw RulePlanError.invalid("Replace the fixed year \(component) with {year}.")
            }
            let parts = component.split(separator: "-")
            if parts.count == 2,
               let year = Int(parts[0]), (1900...2200).contains(year),
               let month = Int(parts[1]), (1...12).contains(month) {
                throw RulePlanError.invalid("Replace the fixed date \(component) with {year-month}.")
            }
        }
    }
}
