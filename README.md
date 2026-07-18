# Sorting Hat

**A drop folder with opinions.** Sorting Hat is a native macOS filing assistant for people who want a clean Inbox without writing automation: it uses plain-language rules and Apple’s on-device Foundation Model to inspect, rename, Finder-tag, and route files, while deterministic Swift code validates every filesystem action.

```sh
./script/build_and_run.sh
```

[See exactly how the product extends Apple’s WWDC26 file-sorting demo, including the reproducible negative benchmark results.](docs/wwdc26-comparison.md)

> [!WARNING]
> The current `v0.1.0` build is an experimental pre-release. Its app bundle is ad-hoc signed, not signed with an Apple Developer ID, and it is not notarized. Gatekeeper may block the first launch; managed Macs may prohibit it entirely. Homebrew installation confirms the archive and cask are valid, but does not bypass these macOS security checks.

## Requirements

- macOS 14 or later for the menu-bar app
- macOS 27 plus Apple Intelligence for Apple's built-in `fm` model, or [Ollama](https://ollama.com/) with a local model on earlier macOS versions
- Swift 6.2+ to build from source

## Try it

```sh
swift build -c release
.build/release/sorting-hat init
mkdir -p ~/SortingHat/Inbox
.build/release/sorting-hat once --dry-run
.build/release/sorting-hat watch
```

## Menu-bar app

The packaged app is currently intended for testing, not polished public distribution. If Gatekeeper blocks it, macOS may offer **System Settings → Privacy & Security → Open Anyway**. Only override Gatekeeper if you understand and accept the risk; the Finder Quick Action may produce additional trust prompts.

Build and open the native companion with:

```sh
./script/build_and_run.sh
```

It watches automatically, shows recent filing activity, opens the Inbox and rules file, can pause or sort immediately, and uses macOS's native launch-at-login service. The dashboard appears at launch and the graduation-cap menu remains available for quick actions.

Drag files into `~/SortingHat/Inbox`. Keep `sortinghat.conf` in the directory where you launch the command, or pass `--config /path/to/sortinghat.conf`.

```yaml
inbox: ~/SortingHat/Inbox
output: ~/SortingHat
settle_seconds: 2
ollama_url: http://127.0.0.1:11434
ollama_model: gemma3:4b
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
```

Choose **Automatic**, **Apple**, **Ollama**, or **OpenAI** under **Model Settings**. Apple can use the local `system` model, Private Cloud Compute (`pcc`), or an automatic policy. Automatic always tries on-device first and retries PCC only after an availability or generation failure. Content extraction, unsafe paths, and invalid filing decisions never trigger cloud escalation. PCC is disabled until `allow_apple_pcc: true` is explicitly saved; enabling it means file context may be sent to Apple's Private Cloud Compute service. Overall provider selection then falls back to configured Ollama and OpenAI providers when Apple is unavailable.

For the on-device system model, `apple_use_case: content-tagging` opts into the `fm` content-tagging specialization. `apple_guardrails: permissive-content-transformations` relaxes the system model's content-transformation guardrails for filing material that the default policy refuses; use the default unless your rules require that behavior. These system-only options are omitted from PCC requests. Apple requests continue using guided JSON output, deterministic generation, and native multimodal input for supported images. The app stores the OpenAI API key in macOS Keychain; the CLI reads `OPENAI_API_KEY`.

Sorting Hat reads searchable PDFs, plain-text formats, RTF, Word, and OpenDocument files. For scanned PDFs and receipt images, it uses Apple's local Vision framework to recognize text before asking the selected model to name and file the document. Embedded PDF text is preferred, so searchable PDFs avoid unnecessary OCR. Extraction is limited to the first 5 pages and 12,000 characters; the source file is never modified. If a scanned PDF cannot be rendered or contains no sufficiently confident text, Sorting Hat leaves it in the Inbox and reports the extraction failure.

When Apple `fm` is selected, compatible non-image files are analyzed in batches of at most 8 files and 24,000 extracted characters. Each file is identified by an opaque request-local ID, and every returned decision is independently validated before any move. Missing, duplicate, unexpected, or unsafe decisions cannot be applied. Images remain on the individual multimodal path, and a failed batch does not prevent files in other batches from being processed. A deterministic process benchmark verifies that 8 compatible files use 1 `fm respond` invocation instead of 8.

The Inbox is intake-only. Sorting Hat renames each file and moves it to a rule-specific folder under `output` (for example, `~/SortingHat/Receipts/2026`). It creates those destination folders as needed, rejects absolute paths and traversal, preserves existing files with numbered names, and writes tags as Finder metadata.

If a model returns the uploaded filename unchanged, Sorting Hat leaves the source in the Inbox and reports an invalid sorting decision instead of silently skipping the requested rename.

If the model cannot classify a file confidently, it can return an empty destination. Sorting Hat treats that as **Needs review** and leaves the source in the Inbox rather than guessing. Automatic provider selection also falls through to a configured Ollama or OpenAI provider when Apple reports the system model as available but generation fails.

## Commands

```text
sorting-hat init [--config PATH]
sorting-hat once [--config PATH] [--dry-run]
sorting-hat watch [--config PATH] [--dry-run]
sorting-hat evaluate --live --corpus PATH --output PATH [--baseline PATH] [--config PATH]
```

## Live Foundation Models evaluation

Live quality checks are deliberately opt-in and read-only. Create a private, anonymized corpus outside the repository, copy the format in `Tests/SortingHatTests/Fixtures/live-evaluation-corpus.example.json`, then run:

```sh
.build/debug/sorting-hat evaluate --live \
  --corpus ~/SortingHat-Evaluation/corpus/corpus.json \
  --output ~/SortingHat-Evaluation/results/run-001 \
  --config sortinghat.conf
```

The manifest is versioned and contains rules plus cases with a relative source path, content kind (`receipt`, `scan`, `screenshot`, `pdf`, `office_document`, or `ambiguous`), accepted folders, required filename terms, required tags, and whether an empty-folder abstention is expected. The checked-in template defines all six required classes but deliberately includes no documents. Corpus files must sit beside or below the manifest; output inside that corpus directory is rejected. The evaluator calls Apple `fm` but never calls `Organizer.apply`, so sources are not renamed, tagged, or moved.

Each run writes `evaluation.json` and `summary.md`. The artifact records model, OS, prompt version, use case, guardrails, per-case decisions and latency, accuracy, generation failures, unsafe/invalid decisions, and abstentions. Pass a previous `evaluation.json` with `--baseline` to expose regressions in the Markdown summary. Exit status `2` means a threshold or baseline regressed; `1` means the evaluation could not run. Do not commit corpus documents or results containing private or copyrighted content; only the synthetic manifest example belongs in the repository.

For reproducible multi-prompt, system/content-tagging, and system/PCC comparisons, use the locked standalone Python project in [`evaluation/`](evaluation/README.md). It consumes the same corpus manifest and produces JSON, CSV, Markdown, and chart artifacts without adding Python to the application runtime.

Bounded tool-calling candidates are also evaluated there under a documented threat model and evidence gate. Filesystem mutation remains exclusively in validated Swift code; no evaluation tool is available to the shipping app unless a future change demonstrates and reviews measurable value first.

`watch` intentionally uses a small polling loop in this first version. It is simple and reliable for a human-scale drop folder; a launch agent and event-driven watcher can come next.

## Development

```sh
swift test
```

Inference is behind `FileAnalyzing`, so filesystem behavior and safety can be tested without a model. Provider selection prefers Apple `fm` when available and otherwise uses the configured local Ollama endpoint.

## Release status

Release archives are currently ad-hoc signed and published as GitHub pre-releases. Before treating Sorting Hat as production-ready, releases must be signed with a **Developer ID Application** certificate using the hardened runtime, submitted to Apple for notarization, stapled, and validated with Gatekeeper. See [Apple's Gatekeeper guidance](https://support.apple.com/en-gb/102445) and [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
