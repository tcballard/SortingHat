# Sorting Hat

**A drop folder with opinions.**

Sorting Hat is a local-first macOS filing assistant for anyone who wants a clean Inbox without writing automation. Describe how receipts, screenshots, documents, and downloads should be named and filed; Sorting Hat turns that plan into editable rules, extracts useful context, and validates every rename, Finder tag, and destination in Swift before touching the filesystem. The Mac App Store build uses only Apple’s on-device Foundation Model or Ollama running on the same Mac.

![Sorting Hat showing renamed files and their rule-specific destinations](launch-pack/outputs/app-store/screenshots/01-sorted-activity.jpg)

Download the signed and notarized release from
[oss.tcballard.dev/sortinghat](https://oss.tcballard.dev/sortinghat), or install
it with `brew install --cask tcballard/tap/sorting-hat`.

Build and run from source:

```sh
./script/build_and_run.sh
```

[See exactly how Sorting Hat extends Apple’s WWDC26 file-sorting demo, including the passing shipping-path benchmark and its limits.](docs/wwdc26-comparison.md)

## Requirements

- macOS 14 or later
- macOS 26, Apple Intelligence, and a supported Mac for Apple’s on-device Foundation Model
- [Ollama](https://ollama.com/) with a local model when Apple’s model is unavailable
- Swift 6.2+ to build from source
- XcodeGen 2.44.1 only when regenerating the checked-in Xcode project

## How it works

One Inbox. One output root. The model proposes; Swift decides.

1. Add a file in the app or send it through Finder’s **Send to Sorting Hat** Quick Action.
2. Sorting Hat extracts useful text, asks the selected model for a filename, tags, and destination, then validates the answer.
3. Safe decisions move to a rule-specific folder beneath your output root. Missing folders are created automatically.
4. Uncertain or invalid decisions stay in the Inbox for review. No guessing, no mystery pile called `Sorted` inside the Inbox.

The Inbox is intake-only. Sorting Hat preserves file extensions, rejects absolute paths and traversal, protects existing files with numbered names, and refuses a “rename” that leaves the original filename unchanged. Controlled `Put ... in ...` rules compile into an allow-list, so free-form model output cannot invent a destination outside the ruleset.

## The Mac app

The dashboard is the single place to see the Inbox, Activity, rules, and anything that needs attention. Left-click the menu-bar hat to open or close the dashboard. Right-click it for quick actions such as pause, resume, and sort now.

Sorting Hat watches while it is running, shows exactly how each file was renamed and filed, supports undo and manual recovery, and uses macOS’s native launch-at-login service.

Before saving a new ruleset, preview it against up to eight representative files. Preview uses the same extraction, model, compiled routing, collision naming, and validation path as live filing while deliberately skipping every file move and Finder-tag write.

### Send to Sorting Hat from Finder

Signed builds include a first-party **Send to Sorting Hat** Quick Action. Select files in Finder, then choose **Quick Actions → Send to Sorting Hat**. The action copies each file into Sorting Hat’s App Group queue. It never changes the original.

Paused apps still import files into the Inbox. Closed apps pick up staged files on the next launch. One invocation accepts up to 256 files, with a 256 MB per-file limit, a 1 GB selection limit, and a 25-second deadline. Partial failures name the files that were not queued instead of pretending the whole batch worked.

Enable the action in **System Settings → General → Login Items & Extensions → Finder**. If Finder caches the old extension state, relaunch Finder once. **Sorting Hat Settings → Finder** shows integration health, permission repair, queued copies, failures, and **Retry** or **Remove** actions. Older Automator actions with the same name can also be migrated safely. The full contract is in the [Finder Quick Action architecture notes](docs/finder-quick-action.md).

## Rules and configuration

Rules are plain language, editable, and ordered from specific routes to the catch-all:

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
  - Put receipts in Receipts/{merchant}/{year} and tag them receipt and the merchant name.
  - Put screenshots in Screenshots/{project}/{year-month} and tag them screenshot.
  - Put everything else in Files/YYYY-MM and add one useful topic tag.
```

Dynamic destinations use controlled whole-folder components: `{merchant}`, `{client}`, `{project}`, `{source-app}`, `{year}`, `{month}`, and `{year-month}`. Sorting Hat asks the model only to select a compiled rule and identify those values; Swift validates and renders the final path. If a value is missing, uncertain, or looks like a path, the file stays in review. Fixed folders and the original `YYYY` / `YYYY-MM` date templates remain supported.

Keep `sortinghat.conf` in the directory where you launch the CLI, or pass `--config /path/to/sortinghat.conf`.

## Models and privacy

Source and Developer ID builds offer **Automatic**, **Apple**, **Ollama**, and **OpenAI**. Automatic mode prefers Apple’s in-process Foundation Models framework and can fall back to a provider you configured. OpenAI keys live in macOS Keychain in the app; the CLI reads `OPENAI_API_KEY`.

The Mac App Store build is stricter. It offers Apple’s on-device model and Ollama only on `localhost`, `127.0.0.1`, or `::1`. It contains no OpenAI route, no LAN or remote Ollama route, and no Private Cloud Compute option. Content-extraction failures, unsafe paths, and invalid decisions never trigger a silent cloud escalation.

For Apple’s model, `apple_use_case: content-tagging` enables the framework’s content-tagging specialisation. `apple_guardrails: permissive-content-transformations` relaxes content-transformation guardrails for filing material the default policy refuses; keep the default unless your rules need the exception. Apple requests use in-process guided generation and greedy sampling.

Private Cloud Compute remains a research target for the macOS 27 toolchain. It is not a shipping feature.

## Documents and OCR

Sorting Hat reads searchable PDFs, plain text, RTF, Word, and OpenDocument files. Apple’s Vision framework extracts text locally from scanned PDFs, receipts, and screenshots before inference. Searchable PDF text wins over OCR, which keeps the common path faster and simpler.

Extraction is capped at the first five pages and 12,000 characters. The source file is never modified during analysis. If a scan cannot be rendered or does not contain confident text, it stays in the Inbox with a visible extraction failure.

Each file gets an isolated model request. One failure does not block the rest of the Inbox. Sorting Hat favours reliable per-file naming and review over an unverified batching speed claim.

## CLI

```text
sorting-hat init [--config PATH]
sorting-hat once [--config PATH] [--dry-run]
sorting-hat watch [--config PATH] [--dry-run]
sorting-hat evaluate --live --corpus PATH --output PATH [--reference-date YYYY-MM-DD] [--baseline PATH] [--config PATH]
```

Build and try the CLI:

```sh
swift build -c release
.build/release/sorting-hat init
mkdir -p ~/SortingHat/Inbox
.build/release/sorting-hat once --dry-run
.build/release/sorting-hat watch
```

`watch` uses a small polling loop. That is intentionally boring and reliable for a human-scale drop folder; an event-driven watcher can come later.

## Quality, measured

The live evaluator runs the same extractor, routing policy, and validator as the shipping app without moving source files. Use a private, anonymised corpus outside the repository and copy the schema from `Tests/SortingHatTests/Fixtures/live-evaluation-corpus.example.json`:

```sh
.build/debug/sorting-hat evaluate --live \
  --corpus ~/SortingHat-Evaluation/corpus/corpus.json \
  --output ~/SortingHat-Evaluation/results/run-001 \
  --reference-date 2026-07-19 \
  --config sortinghat.conf
```

Pin `--reference-date` to the corpus's declared evaluation day so date-based folders and the model prompt remain reproducible across months. Each run records that date and writes `evaluation.json` and `summary.md`, including the raw model proposal, final validated decision, environment, latency, accuracy, failures, invalid decisions, and abstentions. Pass a compatible previous artifact with `--baseline` to expose regressions. Exit status `2` means a quality threshold or baseline check failed; `1` means the evaluation could not run.

The completed Issue #23 gate scored 108/108 exact final decisions across nine runs, held all 18 ambiguous cases for review, and produced zero invalid final decisions. It also recorded an 8.1% pre-validation latency increase against the corrected baseline. That is the honest result: routing passed; speed did not improve. Read the method and boundaries in [`evaluation/ROUTING_RESULTS.md`](evaluation/ROUTING_RESULTS.md).

The 12-case private corpus is a regression gate, not a universal accuracy claim. Do not commit corpus documents or results containing private or copyrighted content. The standalone [`evaluation/`](evaluation/README.md) project remains available for prompt, system/content-tagging, PCC research, and bounded tool-calling experiments; none of those research tools can mutate the shipping filesystem path.

## Development

```sh
swift test
./script/generate_xcode_project.sh
./script/preflight_app_store.sh
# After one-time signing and notarization setup:
./script/release_candidate.sh 0.1.1 7
# Verify the notarized ZIP, DMG, and signed Sparkle appcast, then create a draft:
./script/create_release_draft.sh
./script/create_release_draft.sh --create
```

Inference sits behind `FileAnalyzing`, so filesystem safety can be tested without a live model. The Foundation Models decision path can also be shared by a future iPhone or iPad client, but iOS cannot behave like a continuously watched Mac folder. The [iOS client boundary](docs/ios-client-architecture.md) documents what is reusable and what needs a Files or Share-extension workflow.

## Distribution status

There is one release train with two signed delivery channels. Both channels are
built from the same source commit and share the version and build number in
`Configuration/Release.xcconfig`; release tooling rejects a mismatched tag or
artifact. Their security contracts remain intentionally different.

- **Direct download:** [`v0.1.1 (7)`](https://github.com/tcballard/SortingHat/releases/tag/v0.1.1) is published as a Developer ID-signed, notarized, and stapled DMG and ZIP with a signed Sparkle appcast. Signing and notarization happen only on the maintainer's Mac; GitHub receives the finished artifacts without receiving private signing credentials.
- **GitHub and Homebrew:** the release workflow re-verifies the published ZIP, DMG, and appcast before updating the Homebrew cask from the ZIP checksum. This completes [Issue #24](https://github.com/tcballard/SortingHat/issues/24).
- **Mac App Store:** the Store target deliberately excludes Sparkle and retains its sandboxed provider contract. Store submission is a separate, deferred channel tracked in [Issue #29](https://github.com/tcballard/SortingHat/issues/29); it does not block the signed direct release.

Issue [#29](https://github.com/tcballard/SortingHat/issues/29) tracks the remaining App Store work. The [distribution guide](docs/distribution.md), [privacy policy](docs/privacy.md), and [support page](docs/support.md) hold the channel-specific details.
