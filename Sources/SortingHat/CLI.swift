import Foundation
import SortingHatCore

@main
enum SortingHatCLI {
    static func main() {
        do { try run() }
        catch {
            FileHandle.standardError.write(Data("sorting-hat: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    static func run() throws {
        var args = Array(CommandLine.arguments.dropFirst())
        let command = args.first ?? "help"
        if !args.isEmpty { args.removeFirst() }
        let dryRun = args.contains("--dry-run")
        let configPath = value(after: "--config", in: args) ?? "sortinghat.conf"

        switch command {
        case "init": try writeExample(to: URL(fileURLWithPath: configPath))
        case "evaluate": try evaluate(args: args, configPath: configPath)
        case "once", "watch":
            let config = try ConfigLoader.load(URL(fileURLWithPath: configPath))
            let inbox = URL(fileURLWithPath: NSString(string: config.inbox).expandingTildeInPath).standardizedFileURL
            let output = URL(fileURLWithPath: NSString(string: config.output).expandingTildeInPath).standardizedFileURL
            try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let analyzer = PreferredAnalyzer(fmExecutable: fmPath(), ollamaURL: config.ollamaURL, ollamaModel: config.ollamaModel,
                                             openAIModel: config.openAIModel, openAIKey: ProcessInfo.processInfo.environment["OPENAI_API_KEY"] ?? "",
                                             provider: config.modelProvider, appleModel: config.appleModel,
                                             appleUseCase: config.appleUseCase, appleGuardrails: config.appleGuardrails,
                                             allowApplePCC: config.allowApplePCC)
            let organizer = Organizer(inbox: inbox, output: output, rules: config.rules, analyzer: analyzer)
            if command == "once" { try process(organizer, dryRun: dryRun) }
            else { try watch(organizer, interval: max(0.5, config.settleSeconds), dryRun: dryRun) }
        case "help", "--help", "-h": printHelp()
        default: throw HatError.invalidConfig("unknown command '\(command)'")
        }
    }

    static func evaluate(args: [String], configPath: String) throws {
        guard args.contains("--live") else { throw HatError.invalidConfig("evaluate requires --live because it runs the real Apple model") }
        guard let corpusPath = value(after: "--corpus", in: args) else { throw HatError.invalidConfig("evaluate requires --corpus PATH") }
        guard let outputPath = value(after: "--output", in: args) else { throw HatError.invalidConfig("evaluate requires --output PATH") }
        let corpusURL = URL(fileURLWithPath: NSString(string: corpusPath).expandingTildeInPath).standardizedFileURL
        let outputURL = URL(fileURLWithPath: NSString(string: outputPath).expandingTildeInPath).standardizedFileURL
        let corpusRoot = corpusURL.deletingLastPathComponent()
        guard outputURL.path != corpusRoot.path, !outputURL.path.hasPrefix(corpusRoot.path + "/") else {
            throw HatError.invalidConfig("evaluation output must be outside the corpus directory")
        }
        let config = try ConfigLoader.load(URL(fileURLWithPath: configPath))
        let manifest = try LiveEvaluator.loadManifest(at: corpusURL)
        let model = config.appleModel == .automatic ? AppleModelSelection.system : config.appleModel
        let analyzer = FMAnalyzer(executable: fmPath(), model: model, useCase: config.appleUseCase,
                                  guardrails: config.appleGuardrails, pccAllowed: config.allowApplePCC)
        let configuration = EvaluationConfiguration(model: model.rawValue, useCase: config.appleUseCase.rawValue,
            guardrails: config.appleGuardrails.rawValue, pccAllowed: config.allowApplePCC,
            promptVersion: FMAnalyzer.promptVersion, operatingSystem: ProcessInfo.processInfo.operatingSystemVersionString,
            routingPolicyVersion: RoutingDecisionResolver.version)
        let baseline: EvaluationArtifact?
        if let path = value(after: "--baseline", in: args) {
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            baseline = try decoder.decode(EvaluationArtifact.self, from: Data(contentsOf: URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)))
        } else { baseline = nil }
        let artifact = LiveEvaluator.run(manifest: manifest, corpusRoot: corpusRoot, analyzer: analyzer,
                                         configuration: configuration, baseline: baseline)
        try LiveEvaluator.write(artifact, to: outputURL)
        print(LiveEvaluator.summary(artifact))
        if !artifact.thresholdFailures.isEmpty || !artifact.regressions.isEmpty { exit(2) }
    }

    static func process(_ organizer: Organizer, dryRun: Bool) throws {
        for outcome in organizer.planAll(try organizer.candidates()) {
            switch outcome {
            case .success(let move):
                print("\(dryRun ? "Would file" : "Filing") \(move.source.lastPathComponent) → \(move.destination.path) [\(move.tags.joined(separator: ", "))]")
                print("  \(move.reason)")
                if !dryRun {
                    do { try organizer.apply(move) }
                    catch {
                        FileHandle.standardError.write(Data("Skipped \(move.source.lastPathComponent): \(error.localizedDescription)\n".utf8))
                    }
                }
            case .failure(let source, let error):
                FileHandle.standardError.write(Data("Skipped \(source.lastPathComponent): \(error.localizedDescription)\n".utf8))
            }
        }
    }

    static func watch(_ organizer: Organizer, interval: Double, dryRun: Bool) throws -> Never {
        print("Watching \(organizer.inbox.path) (Ctrl-C to stop)")
        while true {
            try process(organizer, dryRun: dryRun)
            Thread.sleep(forTimeInterval: interval)
        }
    }

    static func fmPath() -> String {
        let candidates = ["/usr/bin/fm", "/usr/local/bin/fm", "/opt/homebrew/bin/fm"]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)) ?? "/usr/bin/fm"
    }

    static func value(after flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), args.indices.contains(index + 1) else { return nil }
        return args[index + 1]
    }

    static func writeExample(to url: URL) throws {
        guard !FileManager.default.fileExists(atPath: url.path) else { throw CocoaError(.fileWriteFileExists) }
        try example.write(to: url, atomically: true, encoding: .utf8)
        print("Created \(url.path)")
    }

    static let example = """
    # Sorting Hat — write rules the way you'd explain them to a colleague.
    inbox: ~/SortingHat/Inbox
    output: ~/SortingHat
    settle_seconds: 2
    ollama_url: http://127.0.0.1:11434
    ollama_model:
    openai_model:
    model_provider: automatic
    apple_model: automatic
    apple_use_case: general
    apple_guardrails: default
    allow_apple_pcc: false

    rules:
      - Give every file a short, descriptive, lowercase filename. Use hyphens, never spaces.
      - Put receipts in Receipts/YYYY and tag them receipt and the merchant name.
      - Put screenshots in Screenshots/YYYY-MM and tag them screenshot.
      - Put everything else in Files/YYYY-MM and add one useful topic tag.
    """

    static func printHelp() {
        print("""
        Sorting Hat — a local-first drop folder powered by Apple's fm CLI.

        Usage:
          sorting-hat init [--config PATH]
          sorting-hat once [--config PATH] [--dry-run]
          sorting-hat watch [--config PATH] [--dry-run]
          sorting-hat evaluate --live --corpus PATH --output PATH [--baseline PATH] [--config PATH]
        """)
    }
}
