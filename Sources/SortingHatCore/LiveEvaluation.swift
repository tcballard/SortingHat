import Foundation

public struct EvaluationManifest: Codable, Sendable {
    public let version: Int
    public let name: String
    public let rules: [String]
    public let cases: [EvaluationCase]
    public let thresholds: EvaluationThresholds?
}

public struct EvaluationCase: Codable, Sendable {
    public let id: String
    public let path: String
    public let kind: String
    public let expected: ExpectedDecision
}

public struct ExpectedDecision: Codable, Sendable {
    public let folders: [String]
    public let filenameContains: [String]
    public let tags: [String]
    public let abstain: Bool

    enum CodingKeys: String, CodingKey {
        case folders, tags, abstain
        case filenameContains = "filename_contains"
    }
}

public struct EvaluationThresholds: Codable, Sendable {
    public let minimumAccuracy: Double
    public let maximumGenerationFailureRate: Double
    public let maximumUnsafeDecisionRate: Double

    enum CodingKeys: String, CodingKey {
        case minimumAccuracy = "minimum_accuracy"
        case maximumGenerationFailureRate = "maximum_generation_failure_rate"
        case maximumUnsafeDecisionRate = "maximum_unsafe_decision_rate"
    }
}

public struct EvaluationConfiguration: Codable, Sendable {
    public let model: String
    public let useCase: String
    public let guardrails: String
    public let pccAllowed: Bool
    public let promptVersion: String
    public let operatingSystem: String
    public let routingPolicyVersion: String?

    public init(
        model: String,
        useCase: String,
        guardrails: String,
        pccAllowed: Bool,
        promptVersion: String,
        operatingSystem: String,
        routingPolicyVersion: String? = nil
    ) {
        self.model = model
        self.useCase = useCase
        self.guardrails = guardrails
        self.pccAllowed = pccAllowed
        self.promptVersion = promptVersion
        self.operatingSystem = operatingSystem
        self.routingPolicyVersion = routingPolicyVersion
    }

    enum CodingKeys: String, CodingKey {
        case model, guardrails
        case useCase = "use_case"
        case pccAllowed = "pcc_allowed"
        case promptVersion = "prompt_version"
        case operatingSystem = "operating_system"
        case routingPolicyVersion = "routing_policy_version"
    }
}

public struct EvaluationMetrics: Codable, Equatable, Sendable {
    public let total: Int
    public let correct: Int
    public let folderCorrect: Int
    public let filenameCorrect: Int
    public let tagsCorrect: Int
    public let generationFailures: Int
    public let schemaFailures: Int
    public let unsafeOrInvalidDecisions: Int
    public let abstentions: Int
    public let accuracy: Double
    public let generationFailureRate: Double
    public let unsafeDecisionRate: Double
    public let averageLatencyMilliseconds: Double

    enum CodingKeys: String, CodingKey {
        case total, correct, abstentions, accuracy
        case folderCorrect = "folder_correct"
        case filenameCorrect = "filename_correct"
        case tagsCorrect = "tags_correct"
        case generationFailures = "generation_failures"
        case schemaFailures = "schema_failures"
        case unsafeOrInvalidDecisions = "unsafe_or_invalid_decisions"
        case generationFailureRate = "generation_failure_rate"
        case unsafeDecisionRate = "unsafe_decision_rate"
        case averageLatencyMilliseconds = "average_latency_ms"
    }
}

public struct EvaluationResult: Codable, Sendable {
    public let id: String
    public let kind: String
    public let latencyMilliseconds: Double
    public let rawDecision: Decision?
    public let decision: Decision?
    public let error: String?
    public let folderCorrect: Bool
    public let filenameCorrect: Bool
    public let tagsCorrect: Bool
    public let abstained: Bool
    public let unsafeOrInvalid: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, decision, error, abstained
        case rawDecision = "raw_decision"
        case latencyMilliseconds = "latency_ms"
        case folderCorrect = "folder_correct"
        case filenameCorrect = "filename_correct"
        case tagsCorrect = "tags_correct"
        case unsafeOrInvalid = "unsafe_or_invalid"
    }
}

public struct EvaluationArtifact: Codable, Sendable {
    public let schemaVersion: Int
    public let corpusName: String
    public let createdAt: Date
    public let configuration: EvaluationConfiguration
    public let metrics: EvaluationMetrics
    public let results: [EvaluationResult]
    public let thresholdFailures: [String]
    public let regressions: [String]

    enum CodingKeys: String, CodingKey {
        case configuration, metrics, results, regressions
        case schemaVersion = "schema_version"
        case corpusName = "corpus_name"
        case createdAt = "created_at"
        case thresholdFailures = "threshold_failures"
    }
}

public enum LiveEvaluator {
    public static func loadManifest(at url: URL) throws -> EvaluationManifest {
        let manifest = try JSONDecoder().decode(EvaluationManifest.self, from: Data(contentsOf: url))
        guard manifest.version == 1 else { throw HatError.invalidConfig("evaluation corpus version must be 1") }
        guard !manifest.cases.isEmpty else { throw HatError.invalidConfig("evaluation corpus must contain cases") }
        let root = url.deletingLastPathComponent().standardizedFileURL
        for item in manifest.cases {
            guard !item.id.isEmpty, !item.path.isEmpty, !item.path.hasPrefix("/"), !item.path.hasPrefix("~") else {
                throw HatError.invalidConfig("evaluation case \(item.id) must use a relative path")
            }
            let file = root.appending(path: item.path).standardizedFileURL
            guard file.path.hasPrefix(root.path + "/") else { throw HatError.invalidConfig("evaluation case \(item.id) escapes the corpus") }
            guard FileManager.default.fileExists(atPath: file.path) else { throw HatError.invalidConfig("evaluation file is missing: \(item.path)") }
        }
        return manifest
    }

    public static func run(
        manifest: EvaluationManifest,
        corpusRoot: URL,
        analyzer: any FileAnalyzing,
        configuration: EvaluationConfiguration,
        baseline: EvaluationArtifact? = nil
    ) -> EvaluationArtifact {
        let root = corpusRoot.standardizedFileURL
        let results = manifest.cases.map { item -> EvaluationResult in
            let file = root.appending(path: item.path).standardizedFileURL
            let started = ContinuousClock.now
            var rawDecision: Decision?
            do {
                let raw = try analyzer.analyze(file: file, rules: manifest.rules)
                rawDecision = raw
                let decision = try RoutingDecisionResolver.resolve(file: file, decision: raw, rules: manifest.rules)
                let elapsed = milliseconds(since: started)
                let abstained = decision.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                let validationError = validate(file: file, decision: decision, rules: manifest.rules)
                let valid = validationError == nil
                let folderCorrect = valid && (item.expected.abstain ? abstained : item.expected.folders.contains(decision.folder))
                let loweredName = decision.filename.lowercased()
                let filenameCorrect = valid && item.expected.filenameContains.allSatisfy { loweredName.contains($0.lowercased()) }
                let loweredTags = Set(decision.tags.map { $0.lowercased() })
                let tagsCorrect = valid && item.expected.tags.allSatisfy { loweredTags.contains($0.lowercased()) }
                return EvaluationResult(id: item.id, kind: item.kind, latencyMilliseconds: elapsed, rawDecision: rawDecision, decision: decision,
                                        error: validationError?.localizedDescription, folderCorrect: folderCorrect, filenameCorrect: filenameCorrect,
                                        tagsCorrect: tagsCorrect, abstained: abstained, unsafeOrInvalid: !valid)
            } catch {
                return EvaluationResult(id: item.id, kind: item.kind, latencyMilliseconds: milliseconds(since: started),
                                        rawDecision: rawDecision, decision: nil, error: error.localizedDescription, folderCorrect: false,
                                        filenameCorrect: false, tagsCorrect: false, abstained: false,
                                        unsafeOrInvalid: isUnsafeOrInvalid(error))
            }
        }
        let metrics = metrics(for: results)
        return EvaluationArtifact(schemaVersion: 2, corpusName: manifest.name, createdAt: Date(), configuration: configuration,
                                  metrics: metrics, results: results,
                                  thresholdFailures: thresholdFailures(metrics, manifest.thresholds),
                                  regressions: regressions(metrics, baseline: baseline, corpusName: manifest.name, configuration: configuration))
    }

    public static func write(_ artifact: EvaluationArtifact, to outputDirectory: URL) throws {
        try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(artifact).write(to: outputDirectory.appending(path: "evaluation.json"), options: .atomic)
        try summary(artifact).write(to: outputDirectory.appending(path: "summary.md"), atomically: true, encoding: .utf8)
    }

    public static func summary(_ artifact: EvaluationArtifact) -> String {
        let status = artifact.thresholdFailures.isEmpty && artifact.regressions.isEmpty ? "PASS" : "FAIL"
        let issues = (artifact.thresholdFailures + artifact.regressions).map { "- \($0)" }.joined(separator: "\n")
        return """
        # Sorting Hat live evaluation: \(status)

        Corpus: \(artifact.corpusName)
        Model: \(artifact.configuration.model) (\(artifact.configuration.useCase))
        Prompt: \(artifact.configuration.promptVersion)
        Routing policy: \(artifact.configuration.routingPolicyVersion ?? "legacy")
        OS: \(artifact.configuration.operatingSystem)

        | Metric | Result |
        | --- | ---: |
        | Accuracy | \(percent(artifact.metrics.accuracy)) |
        | Folder correctness | \(artifact.metrics.folderCorrect)/\(artifact.metrics.total) |
        | Filename quality | \(artifact.metrics.filenameCorrect)/\(artifact.metrics.total) |
        | Tag usefulness | \(artifact.metrics.tagsCorrect)/\(artifact.metrics.total) |
        | Generation failures | \(artifact.metrics.generationFailures) |
        | Schema failures | \(artifact.metrics.schemaFailures) |
        | Unsafe/invalid decisions | \(artifact.metrics.unsafeOrInvalidDecisions) |
        | Abstentions | \(artifact.metrics.abstentions) |
        | Average latency | \(String(format: "%.1f ms", artifact.metrics.averageLatencyMilliseconds)) |

        ## Thresholds and regressions

        \(issues.isEmpty ? "None." : issues)
        """
    }

    private static func validate(file: URL, decision: Decision, rules: [String]) -> Error? {
        if decision.folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
        struct FixedAnalyzer: FileAnalyzing {
            let decision: Decision
            func analyze(file: URL, rules: [String]) throws -> Decision { decision }
        }
        do { _ = try Organizer(inbox: file.deletingLastPathComponent(), rules: rules, analyzer: FixedAnalyzer(decision: decision)).plan(file); return nil }
        catch { return error }
    }

    private static func metrics(for results: [EvaluationResult]) -> EvaluationMetrics {
        let total = results.count
        let correct = results.filter { $0.folderCorrect && $0.filenameCorrect && $0.tagsCorrect && !$0.unsafeOrInvalid }.count
        let failures = results.filter { $0.decision == nil && !$0.unsafeOrInvalid }.count
        let schemaFailures = results.filter { $0.error?.contains("fm returned an invalid decision") == true }.count
        let unsafe = results.filter(\.unsafeOrInvalid).count
        let denominator = Double(max(total, 1))
        return EvaluationMetrics(total: total, correct: correct, folderCorrect: results.filter(\.folderCorrect).count,
                                 filenameCorrect: results.filter(\.filenameCorrect).count, tagsCorrect: results.filter(\.tagsCorrect).count,
                                 generationFailures: failures, schemaFailures: schemaFailures, unsafeOrInvalidDecisions: unsafe,
                                 abstentions: results.filter(\.abstained).count, accuracy: Double(correct) / denominator,
                                 generationFailureRate: Double(failures) / denominator, unsafeDecisionRate: Double(unsafe) / denominator,
                                 averageLatencyMilliseconds: results.map(\.latencyMilliseconds).reduce(0, +) / denominator)
    }

    private static func thresholdFailures(_ metrics: EvaluationMetrics, _ thresholds: EvaluationThresholds?) -> [String] {
        guard let thresholds else { return [] }
        var failures: [String] = []
        if metrics.accuracy < thresholds.minimumAccuracy { failures.append("accuracy \(percent(metrics.accuracy)) is below \(percent(thresholds.minimumAccuracy))") }
        if metrics.generationFailureRate > thresholds.maximumGenerationFailureRate { failures.append("generation failure rate exceeds \(percent(thresholds.maximumGenerationFailureRate))") }
        if metrics.unsafeDecisionRate > thresholds.maximumUnsafeDecisionRate { failures.append("unsafe/invalid decision rate exceeds \(percent(thresholds.maximumUnsafeDecisionRate))") }
        return failures
    }

    private static func regressions(
        _ metrics: EvaluationMetrics,
        baseline: EvaluationArtifact?,
        corpusName: String,
        configuration: EvaluationConfiguration
    ) -> [String] {
        guard let baseline else { return [] }
        guard baseline.schemaVersion == 2 else {
            return ["baseline artifact schema \(baseline.schemaVersion) is not comparable with schema 2"]
        }
        guard baseline.corpusName == corpusName, baseline.metrics.total == metrics.total else {
            return ["baseline corpus does not match this evaluation"]
        }
        let baselineConfiguration = baseline.configuration
        guard baselineConfiguration.model == configuration.model,
              baselineConfiguration.useCase == configuration.useCase,
              baselineConfiguration.guardrails == configuration.guardrails,
              baselineConfiguration.pccAllowed == configuration.pccAllowed,
              baselineConfiguration.operatingSystem == configuration.operatingSystem else {
            return ["baseline model environment does not match this evaluation"]
        }

        var values: [String] = []
        let baselineMetrics = baseline.metrics
        if metrics.accuracy < baselineMetrics.accuracy { values.append("accuracy regressed from \(percent(baselineMetrics.accuracy)) to \(percent(metrics.accuracy))") }
        if metrics.generationFailureRate > baselineMetrics.generationFailureRate { values.append("generation failure rate regressed") }
        if metrics.unsafeDecisionRate > baselineMetrics.unsafeDecisionRate { values.append("unsafe/invalid decision rate regressed") }
        return values
    }

    private static func isUnsafeOrInvalid(_ error: Error) -> Bool {
        guard let error = error as? HatError else { return false }
        switch error { case .unsafePath, .invalidDecision, .invalidBatch: return true; default: return false }
    }

    private static func milliseconds(since start: ContinuousClock.Instant) -> Double {
        let duration = start.duration(to: .now)
        return Double(duration.components.seconds) * 1_000 + Double(duration.components.attoseconds) / 1e15
    }

    private static func percent(_ value: Double) -> String { String(format: "%.1f%%", value * 100) }
}
