# Sorting Hat

A drop folder with opinions. Sorting Hat asks Apple's on-device Foundation Model what a file is, then renames, Finder-tags, and files it using rules you write in plain English.

> [!WARNING]
> The current `v0.1.0` build is an experimental pre-release. Its app bundle is ad-hoc signed, not signed with an Apple Developer ID, and it is not notarized. Gatekeeper may block the first launch; managed Macs may prohibit it entirely. Homebrew installation confirms the archive and cask are valid, but does not bypass these macOS security checks.

- On-device by default: Apple's model on macOS 27, with guided structured output and local Ollama fallback on earlier versions.
- Safe to tinker with: inspect every proposed action with `--dry-run`.
- Yours to teach: the config is a few sentences, not a programming language.

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

The Inbox is intake-only. Sorting Hat renames each file and moves it to a rule-specific folder under `output` (for example, `~/SortingHat/Receipts/2026`). It creates those destination folders as needed, rejects absolute paths and traversal, preserves existing files with numbered names, and writes tags as Finder metadata.

If a model returns the uploaded filename unchanged, Sorting Hat leaves the source in the Inbox and reports an invalid sorting decision instead of silently skipping the requested rename.

## Commands

```text
sorting-hat init [--config PATH]
sorting-hat once [--config PATH] [--dry-run]
sorting-hat watch [--config PATH] [--dry-run]
```

`watch` intentionally uses a small polling loop in this first version. It is simple and reliable for a human-scale drop folder; a launch agent and event-driven watcher can come next.

## Development

```sh
swift test
```

Inference is behind `FileAnalyzing`, so filesystem behavior and safety can be tested without a model. Provider selection prefers Apple `fm` when available and otherwise uses the configured local Ollama endpoint.

## Release status

Release archives are currently ad-hoc signed and published as GitHub pre-releases. Before treating Sorting Hat as production-ready, releases must be signed with a **Developer ID Application** certificate using the hardened runtime, submitted to Apple for notarization, stapled, and validated with Gatekeeper. See [Apple's Gatekeeper guidance](https://support.apple.com/en-gb/102445) and [Apple's notarization documentation](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution).
